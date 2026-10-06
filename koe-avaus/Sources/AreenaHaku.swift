import Foundation

// Haun ohjaus TV:llä: kentän muutokset jonoon, yksi työ purkaa jonon (rakenne kuten Netflixin haussa,
// Kosketuslevy.swift). Laskettu paikka kelpaa vain tuoreena; kosketuslevy ja napit nollaavat sen.
@MainActor
final class AreenaHaku {
    private unowned let tv: LGTV
    private enum Op { case avaa, tuloksiin, tyhjenna, poista, kirjain(Character) }
    private var jono: [Op] = []
    var paikka: AreenaRuudukko.Paikka?
    private var aika = Date.distantPast
    private let tuoreus = 5.0
    private let viive = 0.2 // 0,15 ja 0,2 s: 64/64 oikein; 0,1 s: painalluksia hukkui ja OK osui väärään (6.10.2026)
    // OK päivittää tulokset: simulaattoritestissä 6.10.2026 ensimmäisen kirjaimen jälkeinen nuoli hukkui 0,2 s:ssa.
    private let okViive = 0.4
    private var tyo: Task<Void, Never>?
    private var tarkistus: Task<Void, Never>?
    private var kasin = false // TV:n tekstiä poistettu tyhjästä kentästä: uusi haku ei tyhjennä

    init(tv: LGTV) { self.tv = tv }

    func nollaa() {
        paikka = nil
        jono = []
        kasin = false
    }

    func syota(vanha: String, uusi: String) {
        let v = AreenaRuudukko.normalisoi(vanha), u = AreenaRuudukko.normalisoi(uusi)
        guard v != u else { return }
        if v.isEmpty && !kasin { jono.append(.tyhjenna) }
        let yhteinen = zip(v, u).prefix { $0 == $1 }.count
        jono += Array(repeating: .poista, count: v.count - yhteinen)
        jono += u.dropFirst(yhteinen).map { .kirjain($0) }
        kaynnista()
    }

    // Askelpalautin tyhjässä kentässä: poistaa merkin TV:n kentästä (teksti, jota Kauko ei kirjoittanut).
    func poista() { kasin = true; jono.append(.poista); kaynnista() }
    func avaaHaku() { jono.append(.avaa); kaynnista() }
    func tuloksiin() { jono.append(.tuloksiin); kaynnista() }
    func tyhjennaKentta() { kasin = false; jono.append(.tyhjenna); kaynnista() }

    private func kaynnista() {
        tarkistus?.cancel()
        if tyo == nil { tyo = Task { await aja() } }
    }

    private func kuva() async throws -> AreenaKuva {
        guard let pisteet = Kuvapisteet(try await tv.kuvakaappausKuva()) else { throw tv.virhe("kuvaa ei voi lukea") }
        return AreenaRuudukko.tunnista(pisteet)
    }

    private func aja() async {
        tv.hakee = true
        defer { tv.hakee = false; tyo = nil }
        do {
            if !tv.valmis { await tv.yhdista() }
            guard tv.valmis else { throw tv.virhe("ei yhteyttä TV:hen") }
            while !jono.isEmpty {
                let ops = jono
                jono = []
                var p = Date().timeIntervalSince(aika) < tuoreus ? paikka : nil
                var napit: [String] = []
                for op in ops {
                    switch op {
                    case .avaa:
                        try await paina(napit, p)
                        napit = []
                        p = try await ankkuroi()
                        continue
                    case .tyhjenna:
                        try await paina(napit, p)
                        napit = []
                        p = try await tyhjenna()
                        continue
                    default:
                        break
                    }
                    if p == nil { p = try await ankkuroi() }
                    guard var q = p else { throw tv.virhe("fokus ei löydy näppäimistöltä") }
                    switch op {
                    case .tuloksiin:
                        // Oikean reunan sarakkeeseen ja sen ohi tuloksiin (rivillä 5–6 ensin ylös riville 4).
                        if q.r >= 5 { napit += Array(repeating: "UP", count: q.r - 4); q = AreenaRuudukko.Paikka(r: 4, c: q.c) }
                        napit += Array(repeating: "RIGHT", count: 6 - q.c)
                        try await paina(napit, nil)
                        napit = []
                        p = nil
                        tv.tila = "Areena: valitse tulos kosketuslevyllä"
                        continue
                    case .poista:
                        napit += AreenaRuudukko.siirry(q, AreenaRuudukko.askelpalautin) + ["ENTER"]
                        q = AreenaRuudukko.askelpalautin
                    case .kirjain(let ch):
                        let (n, loppu) = AreenaRuudukko.painallukset(String(ch), alku: q)
                        napit += n
                        q = loppu
                    case .avaa, .tyhjenna:
                        break
                    }
                    p = q
                }
                try await paina(napit, p)
            }
            if paikka != nil { tv.tila = "Areena: haku TV:llä" }
            tarkistus = Task { await tarkista() }
        } catch {
            jono = []
            paikka = nil
            tv.tila = "Areena-haku: \(error.localizedDescription)"
        }
    }

    private func paina(_ napit: [String], _ loppu: AreenaRuudukko.Paikka?) async throws {
        guard !napit.isEmpty else { return }
        paikka = nil
        for n in napit { try await tv.painele([n], n == "ENTER" ? okViive : viive) }
        paikka = loppu
        aika = Date()
    }

    private func tarkista() async {
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !Task.isCancelled, tyo == nil, let odotettu = paikka,
              let k = try? await kuva(), !Task.isCancelled, tyo == nil else { return }
        if k.tila != .nappain(odotettu) {
            paikka = nil
            tv.tila = "Areena: fokus siirtyi — tarkista TV:n hakukenttä"
        } else {
            aika = Date()
        }
    }

    // Fokus näppäimistölle kuvan mukaan: välilehdeltä alas, tuloksista vasemmalle (palaa viimeiseen
    // näppäimeen tai välilehdelle), hakunäkymän ulkopuolelta vasemmalla sivupalkki auki ja Hae.
    // Videon aikana LEFT kelaisi: vasemmalle enintään 6 kertaa.
    private func ankkuroi() async throws -> AreenaRuudukko.Paikka {
        var k = try await kuva()
        var vasemmalle = 0, ylos = false
        for _ in 0..<12 {
            switch k.tila {
            case .nappain(let p) where p == AreenaRuudukko.tyhjenna:
                try await tv.painele(["UP"], 0.15) // Tyhjennästä siirry ei laske: ylös palaa edelliseen
            case .nappain(let p):
                return p
            case .valilehti(let podcastit):
                // Podcastit-välilehdeltä alas ei liiku, kun tuloksia ei ole ("Ei tuloksia", 6.10.2026).
                try await tv.painele(podcastit ? ["LEFT", "DOWN"] : ["DOWN"], 0.2)
            case .hakunakyma:
                try await tv.painele(["LEFT"], 0.15)
            case .sivupalkki(let hae):
                if hae {
                    try await tv.painele(["ENTER"], 0.15)
                    try await Task.sleep(nanoseconds: 600_000_000)
                } else {
                    guard !ylos else { throw tv.virhe("Areenan Hae-kohtaa ei löytynyt") }
                    ylos = true
                    try await tv.painele(Array(repeating: "UP", count: 8) + ["DOWN"], 0.15)
                }
            case .muu:
                guard vasemmalle < 6 else { throw tv.virhe("Areenan hakua ei löytynyt") }
                tv.tila = "Areena: avataan haku…"
                vasemmalle += 1
                try await tv.painele(["LEFT"], 0.2)
            }
            try await Task.sleep(nanoseconds: 500_000_000)
            k = try await kuva()
        }
        throw tv.virhe("fokus ei löydy näppäimistöltä")
    }

    // Tyhjennä-näppäin, sitten ylös (palaa edelliselle näppäimelle) ja kuva: kentän pitää olla tyhjä.
    private func tyhjenna() async throws -> AreenaRuudukko.Paikka {
        paikka = nil
        var p = try await ankkuroi()
        for _ in 0..<2 {
            try await tv.painele(AreenaRuudukko.siirry(p, AreenaRuudukko.tyhjenna), viive)
            try await tv.painele(["ENTER"], okViive)
            try await tv.painele(["UP"], viive)
            try await Task.sleep(nanoseconds: 500_000_000)
            let k = try await kuva()
            guard case .nappain(let q) = k.tila else { throw tv.virhe("fokus karkasi tyhjennyksessä") }
            p = q
            if !k.hakuteksti {
                paikka = p
                aika = Date()
                return p
            }
        }
        throw tv.virhe("hakukenttä ei tyhjentynyt")
    }
}

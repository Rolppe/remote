import Foundation

// Haku TV-sovelluksessa, joka ei avaa TV:n näppäimistöä (IME): Kauko ohjaa sovelluksen omaa kirjainruudukkoa
// nuolilla ja OK:lla. Malli kertoo ruudukon ja sen, miten fokus löytyy kuvasta (Areena: AreenaHaku.swift,
// YouTube: YouTubeHaku.swift); haun ohjaus on yhteinen (rakenne kuten Netflixin haussa, Kosketuslevy.swift).
protocol HakuRuudukko {
    associatedtype Paikka: Equatable
    static var nimi: String { get }        // tilarivi "<nimi>: haku TV:llä", virheet "<nimi>-haku: …"
    static var paikkamerkki: String { get }
    static var askelpalautin: Paikka { get }
    static var tyhjenna: Paikka { get }    // Tyhjennä-näppäin: ylös siitä palaa edelliselle näppäimelle
    static func poistonPaikka(_ p: Paikka) -> Paikka // askelpalautin paikasta p (YouTube: samalla sivulla)
    static func normalisoi(_ s: String) -> String
    static func siirry(_ p: Paikka, _ k: Paikka) -> [String]
    static func painallukset(_ teksti: String, alku: Paikka) -> ([String], Paikka)
    static func tuloksiin(_ p: Paikka) -> [String] // näppäimistöltä tuloksiin ilman OK:ta
    static func nappain(_ k: Kuvapisteet) -> (paikka: Paikka?, hakuteksti: Bool)
    static func sama(_ kuvasta: Paikka, _ odotettu: Paikka) -> Bool
    @MainActor static func ankkuroi(_ tv: LGTV) async throws -> Paikka // fokus näppäimistölle kuvan mukaan
}

extension HakuRuudukko {
    static func sama(_ kuvasta: Paikka, _ odotettu: Paikka) -> Bool { kuvasta == odotettu }
    static func poistonPaikka(_ p: Paikka) -> Paikka { askelpalautin }
}

extension LGTV {
    func kuvapisteet() async throws -> Kuvapisteet {
        guard let p = Kuvapisteet(try await kuvakaappausKuva()) else { throw virhe("kuvaa ei voi lukea") }
        return p
    }
}

// Hakukentän käyttöliittymä (Ohjaus.swift) ilman mallin tyyppiä.
@MainActor
protocol RuudukkoOhjain: AnyObject {
    var paikkamerkki: String { get }
    func tyhja(_ teksti: String) -> Bool
    func syota(vanha: String, uusi: String)
    func poista()
    func avaaHaku()
    func tuloksiin()
    func tyhjennaKentta()
}

// Kentän muutokset jonoon, yksi työ purkaa jonon. Laskettu paikka kelpaa vain tuoreena; kosketuslevy ja
// napit nollaavat sen.
@MainActor
final class RuudukkoHaku<M: HakuRuudukko>: RuudukkoOhjain {
    private unowned let tv: LGTV
    private enum Op { case avaa, tuloksiin, tyhjenna, poista, kirjain(Character) }
    private var jono: [Op] = []
    var paikka: M.Paikka?
    private var aika = Date.distantPast
    private let tuoreus = 5.0
    private let viive = 0.2 // Areena 0,15 ja 0,2 s: 64/64 oikein; 0,1 s: painalluksia hukkui ja OK osui väärään (6.10.2026)
    // OK päivittää tulokset: simulaattoritestissä 6.10.2026 ensimmäisen kirjaimen jälkeinen nuoli hukkui 0,2 s:ssa.
    private let okViive = 0.4
    private var tyo: Task<Void, Never>?
    private var tarkistus: Task<Void, Never>?
    private var kasin = false // TV:n tekstiä poistettu tyhjästä kentästä: uusi haku ei tyhjennä

    init(tv: LGTV) { self.tv = tv }

    var paikkamerkki: String { M.paikkamerkki }
    func tyhja(_ teksti: String) -> Bool { M.normalisoi(teksti).isEmpty }

    func nollaa() {
        paikka = nil
        jono = []
        kasin = false
    }

    func syota(vanha: String, uusi: String) {
        let v = M.normalisoi(vanha), u = M.normalisoi(uusi)
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

    private func aja() async {
        tv.hakee = true
        defer { tv.hakee = false; tyo = nil }
        do {
            if !tv.valmis { await tv.yhdista() }
            guard tv.valmis else { throw tv.virhe("ei yhteyttä TV:hen") }
            // Vanhentunut paikka: TV on voinut ehtiä näytönsäästäjään. Tuoreessa kirjoituksessa ei kysytä (nopeus).
            if Date().timeIntervalSince(aika) >= tuoreus { await tv.herataNaytto() }
            while !jono.isEmpty {
                let ops = jono
                jono = []
                var p = Date().timeIntervalSince(aika) < tuoreus ? paikka : nil
                var napit: [String] = []
                var ensimmainen = false
                for op in ops {
                    switch op {
                    case .avaa:
                        try await paina(napit, p)
                        napit = []
                        p = try await M.ankkuroi(tv)
                        continue
                    case .tyhjenna:
                        try await paina(napit, p)
                        napit = []
                        p = try await tyhjenna()
                        ensimmainen = true
                        continue
                    default:
                        break
                    }
                    if p == nil { p = try await M.ankkuroi(tv) }
                    guard var q = p else { throw tv.virhe("fokus ei löydy näppäimistöltä") }
                    switch op {
                    case .tuloksiin:
                        napit += M.tuloksiin(q)
                        try await paina(napit, nil)
                        napit = []
                        p = nil
                        tv.tila = "\(M.nimi): valitse tulos kosketuslevyllä"
                        continue
                    case .poista:
                        let k = M.poistonPaikka(q)
                        napit += M.siirry(q, k) + ["ENTER"]
                        q = k
                    case .kirjain(let ch):
                        let (n, loppu) = M.painallukset(String(ch), alku: q)
                        napit += n
                        q = loppu
                        if ensimmainen {
                            // Ensimmäinen kirjain tyhjään kenttään vaihtaa näkymän tuloksiin, ja seuraava nuoli voi
                            // hukkua okViiveestä huolimatta (a10 6.10.2026: K, sitten O U:n sijaan): paikka kuvasta.
                            ensimmainen = false
                            try await paina(napit, q)
                            napit = []
                            try await Task.sleep(nanoseconds: 500_000_000)
                            p = try await M.ankkuroi(tv)
                            continue
                        }
                    case .avaa, .tyhjenna:
                        break
                    }
                    p = q
                }
                try await paina(napit, p)
            }
            if paikka != nil { tv.tila = "\(M.nimi): haku TV:llä" }
            tarkistus = Task { await tarkista() }
        } catch {
            jono = []
            paikka = nil
            tv.tila = "\(M.nimi)-haku: \(error.localizedDescription)"
        }
    }

    private func paina(_ napit: [String], _ loppu: M.Paikka?) async throws {
        guard !napit.isEmpty else { return }
        paikka = nil
        for n in napit { try await tv.painele([n], n == "ENTER" ? okViive : viive) }
        paikka = loppu
        aika = Date()
    }

    private func tarkista() async {
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !Task.isCancelled, tyo == nil, let odotettu = paikka,
              let k = try? await tv.kuvapisteet(), !Task.isCancelled, tyo == nil else { return }
        if let p = M.nappain(k).paikka, M.sama(p, odotettu) {
            aika = Date()
        } else {
            paikka = nil
            tv.tila = "\(M.nimi): fokus siirtyi — tarkista TV:n hakukenttä"
        }
    }

    // Tyhjennä-näppäin, sitten ylös (palaa edelliselle näppäimelle) ja kuva: kentän pitää olla tyhjä.
    private func tyhjenna() async throws -> M.Paikka {
        paikka = nil
        var p = try await M.ankkuroi(tv)
        for _ in 0..<2 {
            try await tv.painele(M.siirry(p, M.tyhjenna), viive)
            try await tv.painele(["ENTER"], okViive)
            try await tv.painele(["UP"], viive)
            try await Task.sleep(nanoseconds: 500_000_000)
            let k = M.nappain(try await tv.kuvapisteet())
            guard let q = k.paikka else { throw tv.virhe("fokus karkasi tyhjennyksessä") }
            p = q
            if !k.hakuteksti {
                // Ylös palasi alarivin leveälle näppäimelle, jonka paluusaraketta kuva ei kerro: ankkurointi
                // siirtyy kirjaimelle ja lukee paikan kuvasta.
                p = try await M.ankkuroi(tv)
                paikka = p
                aika = Date()
                return p
            }
        }
        throw tv.virhe("hakukenttä ei tyhjentynyt")
    }
}

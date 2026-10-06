import Foundation

// Areenan haun malli yhteiselle ruudukkohaulle (RuudukkoHaku.swift).
extension AreenaRuudukko: HakuRuudukko {
    static let nimi = "Areena"
    static let paikkamerkki = "Hae Areenasta"

    // Oikean reunan sarakkeeseen ja sen ohi tuloksiin (rivillä 5–6 ensin ylös riville 4).
    static func tuloksiin(_ p: Paikka) -> [String] {
        let ylos = Array(repeating: "UP", count: max(0, p.r - 4))
        return ylos + Array(repeating: "RIGHT", count: 6 - p.c)
    }

    static func nappain(_ k: Kuvapisteet) -> (paikka: Paikka?, hakuteksti: Bool) {
        let kuva = tunnista(k)
        if case .nappain(let p) = kuva.tila { return (p, kuva.hakuteksti) }
        return (nil, kuva.hakuteksti)
    }

    // Fokus näppäimistölle kuvan mukaan: välilehdeltä alas, tuloksista vasemmalle (palaa viimeiseen
    // näppäimeen tai välilehdelle), hakunäkymän ulkopuolelta vasemmalla sivupalkki auki ja Hae.
    // Videon aikana LEFT kelaisi: vasemmalle enintään 6 kertaa.
    @MainActor static func ankkuroi(_ tv: LGTV) async throws -> Paikka {
        var k = tunnista(try await tv.kuvapisteet())
        var vasemmalle = 0, ylos = false
        for _ in 0..<12 {
            switch k.tila {
            case .nappain(let p) where p == tyhjenna || p.r == 5:
                // Tyhjennä ja rivin 5 leveät näppäimet: ylös palaa sarakkeeseen, josta niille tultiin, eikä kuva
                // kerro sitä (a7 ja a9 6.10.2026 kirjoittivat ⌫:ltä sarakkeen sivuun) — ylös ja paikka kuvasta.
                try await tv.painele(["UP"], 0.15)
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
            k = tunnista(try await tv.kuvapisteet())
        }
        throw tv.virhe("fokus ei löydy näppäimistöltä")
    }
}

import Foundation

// YouTuben haun malli yhteiselle ruudukkohaulle (RuudukkoHaku.swift); ruudukko YouTubeRuudukko.swift.
extension YouTubeRuudukko: HakuRuudukko {
    static let nimi = "YouTube"
    static let paikkamerkki = "Hae YouTubesta"

    static func nappain(_ k: Kuvapisteet) -> (paikka: Paikka?, hakuteksti: Bool) {
        let kuva = tunnista(k)
        if case .nappain(let p) = kuva.tila { return (p, kuva.hakuteksti) }
        return (nil, kuva.hakuteksti)
    }

    // Fokus näppäimistölle kuvan mukaan (siirrot mitattu 6.10.2026): alariviltä ylös (palaa riville 3),
    // mikrofonista alas ehdotuksiin, ehdotuksista ja takaisin-nuolesta oikealle (palaa viimeiseen näppäimeen),
    // "Tietoa tuloksista" -napista vasemmalle mikrofoniin, tuloksista ylös alariville. Haun ulkopuolelta
    // vasemmalla sivupalkki auki, Haku-kohta ja oikealle (avaa haun). Videon aikana LEFT kelaisi: vasemmalle
    // enintään 6 kertaa. OK:ta ei paineta: sivupalkin ylin kohta (profiili) ja mikrofoni ovat sen vieressä.
    @MainActor static func ankkuroi(_ tv: LGTV) async throws -> Paikka {
        var k = tunnista(try await tv.kuvapisteet())
        var vasemmalle = 0, ylos = false
        for _ in 0..<12 {
            switch k.tila {
            case .nappain(let p) where p.r == 4:
                try await tv.painele(["UP"], 0.15)
            case .nappain(let p):
                return p
            case .hakunakyma(.mikrofoni):
                try await tv.painele(["DOWN"], 0.15)
            case .hakunakyma(.tietoa):
                try await tv.painele(["LEFT"], 0.15)
            case .hakunakyma:
                try await tv.painele(["RIGHT"], 0.15)
            case .tulokset:
                try await tv.painele(["UP"], 0.15)
            case .sivupalkki(let kohta):
                if kohta == 1 {
                    try await tv.painele(["RIGHT"], 0.15)
                    try await Task.sleep(nanoseconds: 600_000_000)
                } else {
                    guard !ylos else { throw tv.virhe("YouTuben Haku-kohtaa ei löytynyt") }
                    ylos = true
                    try await tv.painele(Array(repeating: "UP", count: 12) + ["DOWN"], 0.15)
                }
            case .muu:
                guard vasemmalle < 6 else { throw tv.virhe("YouTuben hakua ei löytynyt") }
                tv.tila = "YouTube: avataan haku…"
                vasemmalle += 1
                try await tv.painele(["LEFT"], 0.2)
            }
            try await Task.sleep(nanoseconds: 500_000_000)
            k = tunnista(try await tv.kuvapisteet())
        }
        throw tv.virhe("fokus ei löydy näppäimistöltä")
    }
}

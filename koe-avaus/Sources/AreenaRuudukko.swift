import Foundation

// Areenan haku (REMOTE-ALOITUS-HAKU-AREENA): Areena ei avaa TV:n näppäimistöä (IME), joten Kauko ohjaa
// sen omaa kirjainruudukkoa nuolilla ja OK:lla kuten Netflixissä. OK lähtee vain, kun fokuksen paikka on
// kuvasta tiedossa: 6.10.2026 liian nopea sarja (0,1 s) päätyi OK:lla Draama-kategoriaan.
// Ruudukko (mitattu 6.10.2026): ABCDEF / GHIJKL / MNOPQR / STUVWX / YZÅÄÖ- /
// [&123 (sarakkeet 0–1)][välilyönti (2–3)][⌫ (4–5)] / [Tyhjennä (0–5)]. Leveältä näppäimeltä ylös vie
// sen vasempaan sarakkeeseen, alas rivin 4 sarakkeesta sen kattavalle näppäimelle; Tyhjennästä ylös
// palaa edelliselle näppäimelle (paikka luetaan siksi kuvasta).
enum AreenaRuudukko {
    static let rivit = ["ABCDEF", "GHIJKL", "MNOPQR", "STUVWX", "YZÅÄÖ-"]

    struct Paikka: Equatable {
        var r: Int, c: Int // r 5: c 0 = &123, 2 = välilyönti, 4 = askelpalautin; r 6: Tyhjennä (c 0, vain kohteena)
    }
    static let valilyonti = Paikka(r: 5, c: 2)
    static let askelpalautin = Paikka(r: 5, c: 4)
    static let tyhjenna = Paikka(r: 6, c: 0)

    static func paikka(_ ch: Character) -> Paikka? {
        if ch == " " { return valilyonti }
        for (r, rivi) in rivit.enumerated() {
            if let i = rivi.firstIndex(of: ch) { return Paikka(r: r, c: rivi.distance(from: rivi.startIndex, to: i)) }
        }
        return nil
    }

    // Isot kirjaimet; Å, Ä, Ö ja - säilyvät, muut tarkkeet pois (é → E); numerot (&123-sivu) jätetään pois.
    static func normalisoi(_ s: String) -> String {
        var tulos = ""
        for ch in s.uppercased() {
            let k = paikka(ch) != nil ? ch : String(ch).folding(options: .diacriticInsensitive,
                                                                 locale: Locale(identifier: "en_US_POSIX")).first ?? ch
            if k == " " || k == "_" {
                if !tulos.isEmpty && tulos.last != " " { tulos.append(" ") }
            } else if paikka(k) != nil {
                tulos.append(k)
            }
        }
        return tulos.trimmingCharacters(in: .whitespaces)
    }

    static func siirry(_ p: Paikka, _ k: Paikka) -> [String] {
        var out: [String] = []
        var r = p.r, c = p.c
        if r == 5 && k.r == 5 {
            return Array(repeating: k.c < c ? "LEFT" : "RIGHT", count: abs(k.c - c) / 2)
        }
        if r == 5 && k.r == 6 { return out + ["DOWN"] }
        if r == 5 { out.append("UP"); r = 4 }
        if k.r >= 5 {
            // Leveälle näppäimelle aina sen vasemmasta sarakkeesta: ylös palaa sarakkeeseen, josta näppäimelle
            // tultiin (mitattu 6.10.2026: - → ⌫ → UP = -, Ö → ⌫ → UP = Ö), ja malli olettaa sarakkeen k.c.
            let kc = k.r == 6 ? c : k.c
            out += Array(repeating: kc < c ? "LEFT" : "RIGHT", count: abs(kc - c))
            return out + Array(repeating: "DOWN", count: k.r - r)
        }
        out += Array(repeating: k.r < r ? "UP" : "DOWN", count: abs(k.r - r))
        return out + Array(repeating: k.c < c ? "LEFT" : "RIGHT", count: abs(k.c - c))
    }

    static func painallukset(_ teksti: String, alku: Paikka) -> ([String], Paikka) {
        var out: [String] = []
        var p = alku
        for ch in teksti {
            guard let k = paikka(ch) else { continue }
            out += siirry(p, k) + ["ENTER"]
            p = k
        }
        return (out, p)
    }
}

enum AreenaTila: Equatable {
    case nappain(AreenaRuudukko.Paikka) // fokus näppäimistöllä
    case valilehti(podcastit: Bool)     // TV-ohjelmat alas vie näppäimistölle; Podcastit vain, jos tuloksia on
    case hakunakyma                     // hakunäkymä, fokus tuloksissa tai aiemmissa hauissa
    case sivupalkki(hae: Bool)          // vasen valikko auki; hae = fokus Hae-kohdassa
    case muu
}

struct AreenaKuva: Equatable {
    let tila: AreenaTila
    let hakuteksti: Bool
}

extension AreenaRuudukko {
    // 960×540-kuvassa: näppäimet ~60, fokusnäppäin ~250, tausta ~20 (kuvat 6.10.2026).
    private static let xs = [205, 238, 271, 304, 337, 370], ys = [160, 193, 226, 259, 292]
    private static let leveat: [(Paikka, ClosedRange<Int>, ClosedRange<Int>)] = [
        (Paikka(r: 5, c: 0), 192...252, 312...339), (valilyonti, 258...318, 312...339),
        (askelpalautin, 324...384, 312...339), (tyhjenna, 192...384, 345...372),
    ]

    private static func laske(_ k: Kuvapisteet, _ x: ClosedRange<Int>, _ y: ClosedRange<Int>,
                              _ ehto: (Double) -> Bool) -> Int {
        var n = 0
        for a in x { for b in y where ehto(k.kirkkaus(a, b)) { n += 1 } }
        return n
    }

    static func tunnista(_ k: Kuvapisteet) -> AreenaKuva {
        var ehdokkaat: [(Double, Paikka)] = []
        for (r, y) in ys.enumerated() {
            for (c, x) in xs.enumerated() {
                let v = [(-11, -11), (11, -11), (-11, 11), (11, 11)].map { k.kirkkaus(x + $0.0, y + $0.1) }
                ehdokkaat.append((v.reduce(0, +) / 4, Paikka(r: r, c: c)))
            }
        }
        for (p, x, y) in leveat {
            let v = [(x.lowerBound + 4, y.lowerBound + 3), (x.upperBound - 4, y.lowerBound + 3),
                     (x.lowerBound + 4, y.upperBound - 3), (x.upperBound - 4, y.upperBound - 3)].map { k.kirkkaus($0.0, $0.1) }
            ehdokkaat.append((v.reduce(0, +) / 4, p))
        }
        let nappaimet = ehdokkaat.prefix(30).filter { (45...75).contains($0.0) || $0.0 > 200 }.count
        // Tyhjä kenttä: harmaa "Mitä haluat katsoa?" (~370 pistettä 121–200, valkoisia ≤ 21 = kursori).
        let harmaa = laske(k, 213...400, 38...64) { $0 > 120 && $0 <= 200 }
        let valkoinen = laske(k, 205...480, 38...64) { $0 > 200 }
        let hakuteksti = nappaimet >= 25 && !(harmaa >= 250 && valkoinen < 60)
        ehdokkaat.sort { $0.0 > $1.0 }
        if ehdokkaat[0].0 > 200 && ehdokkaat[1].0 < 100 {
            return AreenaKuva(tila: .nappain(ehdokkaat[0].1), hakuteksti: hakuteksti)
        }
        if nappaimet >= 25 {
            let tv = laske(k, 168...289, 84...87) { $0 > 220 }, podcastit = laske(k, 290...408, 84...87) { $0 > 220 }
            let tila: AreenaTila = max(tv, podcastit) > 60 ? .valilehti(podcastit: podcastit > tv) : .hakunakyma
            return AreenaKuva(tila: tila, hakuteksti: hakuteksti)
        }
        // Avattu sivupalkki: harmaat valikkotekstit (TV … Omat, ~630 pistettä) tummalla paneelilla, jonka
        // alaosa on kokonaan tumma (etusivulla siinä on tekstiä); fokusoitu "Hae" on valkoinen (~55 pistettä).
        if laske(k, 66...140, 245...360, { $0 > 80 && $0 <= 150 }) >= 500,
           laske(k, 150...250, 380...440, { $0 < 35 }) >= 6100 {
            return AreenaKuva(tila: .sivupalkki(hae: laske(k, 70...110, 178...198) { $0 > 150 } >= 30),
                              hakuteksti: false)
        }
        return AreenaKuva(tila: .muu, hakuteksti: false)
    }
}

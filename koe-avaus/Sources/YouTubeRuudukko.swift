import Foundation

// YouTuben haku (REMOTE-ALOITUS-HAKU-YOUTUBE): YouTube (youtube.leanback.v4) ei avaa TV:n näppäimistöä (IME),
// joten Kauko ohjaa sen omaa kirjainruudukkoa kuten Areenan (RuudukkoHaku.swift).
// Ruudukko (mitattu 6.10.2026): ABCDEFG ⌫ / HIJKLMN &123 / OPQRSTU 🌐 / VWXYZ-' / [Välilyönti][Tyhjennä][Hae].
// Rivillä 3 ei ole erikoissaraketta: '-näppäimeltä oikealle vie 🌐:hen ja 🌐:stä alas '-näppäimelle. Riviltä 3
// alas vie aina välilyöntiin ja alariviltä ylös palaa siihen rivin 3 näppäimeen, jolta alas tultiin; alariviltä
// alas vie tuloksiin ja tuloksista ylös alariville. Tulokset päivittyvät kirjoittaessa, joten Hae-näppäintä
// (OK) ei tarvita.
enum YouTubeRuudukko {
    static let rivit = ["ABCDEFG", "HIJKLMN", "OPQRSTU", "VWXYZ-'"]

    struct Paikka: Equatable {
        // r 0–3, c 0–7 (c 7: ⌫, &123, 🌐); r 4 = alarivi: k 0 välilyönti, 1 Tyhjennä, 2 Hae, ja c on rivin 3
        // sarake, jolle ylös palaa (kuvasta sitä ei näe: -1).
        var r: Int, c: Int, k: Int = 0
    }
    static let askelpalautin = Paikka(r: 0, c: 7)
    static let valilyonti = Paikka(r: 4, c: -1, k: 0)
    static let tyhjenna = Paikka(r: 4, c: -1, k: 1)

    static func paikka(_ ch: Character) -> Paikka? {
        if ch == " " { return valilyonti }
        for (r, rivi) in rivit.enumerated() {
            if let i = rivi.firstIndex(of: ch) { return Paikka(r: r, c: rivi.distance(from: rivi.startIndex, to: i)) }
        }
        return nil
    }

    // Isot kirjaimet, - ja '; tarkkeet pois (Ä → A: ruudukossa ei ole Å:ta, Ä:tä eikä Ö:tä); numerot (&123-sivu) pois.
    static func normalisoi(_ s: String) -> String {
        var tulos = ""
        for ch in s.uppercased() {
            let m: Character = ch == "\u{2019}" ? "'" : ch // puhelimen kaareva heittomerkki
            let k = paikka(m) != nil ? m : String(m).folding(options: .diacriticInsensitive,
                                                              locale: Locale(identifier: "en_US_POSIX")).first ?? m
            if k == " " || k == "_" {
                if !tulos.isEmpty && tulos.last != " " { tulos.append(" ") }
            } else if paikka(k) != nil {
                tulos.append(k)
            }
        }
        return tulos.trimmingCharacters(in: .whitespaces)
    }

    // Napit ja loppupaikka; alariville tultaessa loppupaikan c kertoo, mihin ylös palaa.
    static func siirto(_ p: Paikka, _ k: Paikka) -> ([String], Paikka) {
        var out: [String] = []
        var r = p.r, c = p.c
        if r == 4 {
            if k.r == 4 { return (vaaka(p.k, k.k), Paikka(r: 4, c: c, k: k.k)) }
            out.append("UP")
            r = 3
        }
        // Sarakkeesta 7 riville 3 tai alariville: ensin vasemmalle, koska rivillä 3 ei ole saraketta 7.
        if c == 7 && k.r >= 3 { out.append("LEFT"); c = 6 }
        if k.r == 4 {
            out += Array(repeating: "DOWN", count: 4 - r) + vaaka(0, k.k)
            return (out, Paikka(r: 4, c: c, k: k.k))
        }
        out += Array(repeating: k.r < r ? "UP" : "DOWN", count: abs(k.r - r))
        return (out + vaaka(c, k.c), k)
    }

    private static func vaaka(_ a: Int, _ b: Int) -> [String] {
        Array(repeating: b < a ? "LEFT" : "RIGHT", count: abs(b - a))
    }

    static func siirry(_ p: Paikka, _ k: Paikka) -> [String] { siirto(p, k).0 }

    static func painallukset(_ teksti: String, alku: Paikka) -> ([String], Paikka) {
        var out: [String] = []
        var p = alku
        for ch in teksti {
            guard let k = paikka(ch) else { continue }
            let (n, loppu) = siirto(p, k)
            out += n + ["ENTER"]
            p = loppu
        }
        return (out, p)
    }

    static func tuloksiin(_ p: Paikka) -> [String] { siirry(p, valilyonti) + ["DOWN"] }

    // Alarivin näppäimen paikka kuvasta ei kerro saraketta, jolle ylös palaa.
    static func sama(_ kuvasta: Paikka, _ odotettu: Paikka) -> Bool {
        kuvasta == odotettu || (kuvasta.r == 4 && odotettu.r == 4 && kuvasta.k == odotettu.k)
    }
}

enum YouTubeTila: Equatable {
    enum Kohta: Equatable { case mikrofoni, tietoa, takaisin, ehdotus, muu }
    case nappain(YouTubeRuudukko.Paikka) // fokus näppäimistöllä (alarivillä c = -1)
    case hakunakyma(Kohta)               // näppäimistö näkyy, fokus muualla
    case tulokset                        // haun tulokset koko ruudulla, näppäimistö piilossa
    case sivupalkki(kohta: Int)          // vasen valikko auki; fokuskohta ylhäältä (0 profiili, 1 Haku)
    case muu
}

struct YouTubeKuva: Equatable {
    let tila: YouTubeTila
    let hakuteksti: Bool
}

extension YouTubeRuudukko {
    // 960×540-kuvassa (6.10.2026): kirjaimet harmaat ~200 tummalla ~15, fokusnäppäin valkoinen ~240,
    // alarivin näppäimet ~40. Sivupalkin auki ollessa näppäimistö on 151 px oikealla.
    private static let xs = [373, 406, 439, 472, 505, 538, 571, 615], ys = [100, 133, 166, 199]
    private static let leveat: [(Int, ClosedRange<Int>)] = [(0, 362...438), (1, 447...518), (2, 527...590)]
    private static let sivupalkinKohdat = [50, 97, 136, 175, 214, 253, 311, 350, 389, 428, 467, 514]

    private static func laske(_ k: Kuvapisteet, _ x: ClosedRange<Int>, _ y: ClosedRange<Int>,
                              _ ehto: (Double) -> Bool) -> Int {
        var n = 0
        for a in x { for b in y where ehto(k.kirkkaus(a, b)) { n += 1 } }
        return n
    }

    private static func rengas(_ k: Kuvapisteet, _ x: Int, _ y: Int) -> Double {
        [(-11, 0), (11, 0), (0, -11), (0, 11)].map { k.kirkkaus(x + $0.0, y + $0.1) }.reduce(0, +) / 4
    }

    static func tunnista(_ k: Kuvapisteet) -> YouTubeKuva {
        // Näppäimistö näkyy: kirjaimen merkki (3–120 kirkasta pistettä) tai valkoinen fokusruutu ≥ 22/28 paikassa.
        var nakyvat = 0
        for y in ys {
            for x in xs.prefix(7) {
                let n = laske(k, x - 7...x + 7, y - 7...y + 7) { $0 > 150 }
                if (3...120).contains(n) || n >= 200 { nakyvat += 1 }
            }
        }
        if nakyvat >= 22 {
            let teksti = laske(k, 135...600, 38...64) { $0 > 200 } >= 10
            var ehdokkaat: [(Double, Paikka)] = []
            for (r, y) in ys.enumerated() {
                for (c, x) in xs.enumerated() where c < 7 || r < 3 {
                    let v = [(-10, -10), (10, -10), (-10, 10), (10, 10)].map { k.kirkkaus(x + $0.0, y + $0.1) }
                    ehdokkaat.append((v.reduce(0, +) / 4, Paikka(r: r, c: c)))
                }
            }
            for (n, x) in leveat {
                let v = [(x.lowerBound + 3, 224), (x.upperBound - 3, 224), (x.lowerBound + 3, 240), (x.upperBound - 3, 240)]
                ehdokkaat.append((v.map { k.kirkkaus($0.0, $0.1) }.reduce(0, +) / 4, Paikka(r: 4, c: -1, k: n)))
            }
            ehdokkaat.sort { $0.0 > $1.0 }
            if ehdokkaat[0].0 > 200 && ehdokkaat[1].0 < 100 {
                return YouTubeKuva(tila: .nappain(ehdokkaat[0].1), hakuteksti: teksti)
            }
            let kohta: YouTubeTila.Kohta
            if rengas(k, 96, 50) > 200 { kohta = .mikrofoni }
            else if rengas(k, 688, 51) > 200 { kohta = .tietoa }
            else if rengas(k, 39, 269) > 200 { kohta = .takaisin }
            else if [101, 134, 167, 200, 233].contains(where: { y in k.kirkkaus(340, y - 8) > 200 && k.kirkkaus(340, y + 8) > 200 }) {
                kohta = .ehdotus
            } else { kohta = .muu }
            return YouTubeKuva(tila: .hakunakyma(kohta), hakuteksti: teksti)
        }
        // Avattu sivupalkki: tumma rako x 250 sivupalkin ja sisällön välissä ja fokuskohdan valkoinen pohja.
        if laske(k, 250...250, 90...499, { $0 < 30 }) >= 380 {
            for (i, y) in sivupalkinKohdat.enumerated() where laske(k, 200...230, y - 1...y + 1, { $0 > 200 }) >= 80 {
                return YouTubeKuva(tila: .sivupalkki(kohta: i), hakuteksti: false)
            }
        }
        // Tulokset: "Tietoa tuloksista" oikeassa yläkulmassa ilman näppäimistöä.
        if laske(k, 713...790, 45...58, { $0 > 150 }) >= 50 {
            return YouTubeKuva(tila: .tulokset, hakuteksti: false)
        }
        return YouTubeKuva(tila: .muu, hakuteksti: false)
    }
}

import CoreGraphics
import Foundation

// Netflixin haku (REMOTE-NETFLIX-HAKU): Netflix ei ota kirjaimia vastaan tekstinä (IME) eikä näppäiminä,
// joten Kauko ohjaa sen omaa kirjainruudukkoa nuolilla ja OK:lla. OK lähtee vasta, kun TV:n
// kuvakaappaus näyttää fokuksen näppäimistöllä: 5.10.2026 sokea OK hakutuloksissa käynnisti jakson.
// Ruudukko: ylärivi [välilyönti (sarakkeet 0–2)][askelpalautin (3–5)], sitten abcdef … 567890.
// Ylöspäin riviltä a–f pääsee yläriville; ylärivistä alaspäin välilyönti → b, askelpalautin → e.
// Koordinaatit ovat 960×540-kuvassa (TV:n kaappaus skaalataan siihen), mitattu 5.10.2026.
enum NetflixRuudukko {
    static let rivit = ["abcdef", "ghijkl", "mnopqr", "stuvwx", "yz1234", "567890"]

    struct Paikka: Equatable {
        var r: Int, c: Int // r = -1: ylärivi, jossa c 1 = välilyönti ja c 4 = askelpalautin
    }
    static let valilyonti = Paikka(r: -1, c: 1)
    static let askelpalautin = Paikka(r: -1, c: 4)

    static func paikka(_ ch: Character) -> Paikka? {
        if ch == " " { return valilyonti }
        for (r, rivi) in rivit.enumerated() {
            if let i = rivi.firstIndex(of: ch) { return Paikka(r: r, c: rivi.distance(from: rivi.startIndex, to: i)) }
        }
        return nil
    }

    // Pienet kirjaimet, ä/ö/é → a/o/e, vain a–z, 0–9 ja yksittäiset välilyönnit.
    static func normalisoi(_ s: String) -> String {
        let taitettu = s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        var tulos = ""
        for ch in taitettu {
            if ch == " " || ch == "-" || ch == "_" {
                if !tulos.isEmpty && tulos.last != " " { tulos.append(" ") }
            } else if paikka(ch) != nil {
                tulos.append(ch)
            }
        }
        return tulos.trimmingCharacters(in: .whitespaces)
    }

    static func siirry(_ p: Paikka, _ k: Paikka) -> [String] {
        var out: [String] = []
        var r = p.r, c = p.c
        if r == -1 {
            if k.r == -1 { return k == p ? [] : [k == askelpalautin ? "RIGHT" : "LEFT"] }
            out.append("DOWN")
            r = 0
        }
        if k.r == -1 {
            out += Array(repeating: "UP", count: r)
            out += Array(repeating: k.c < c ? "LEFT" : "RIGHT", count: abs(k.c - c))
            return out + ["UP"]
        }
        out += Array(repeating: k.r < r ? "UP" : "DOWN", count: abs(k.r - r))
        return out + Array(repeating: k.c < c ? "LEFT" : "RIGHT", count: abs(k.c - c))
    }

    // Painallukset tekstille, kun fokus on paikassa alku; palauttaa myös loppupaikan.
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

struct Kuvapisteet {
    static let leveys = 960, korkeus = 540
    private var data: [UInt8]

    init?(_ kuva: CGImage) {
        let l = Kuvapisteet.leveys, k = Kuvapisteet.korkeus
        data = [UInt8](repeating: 0, count: l * k * 4)
        let ok = data.withUnsafeMutableBytes { puskuri -> Bool in
            guard let ctx = CGContext(data: puskuri.baseAddress, width: l, height: k, bitsPerComponent: 8,
                                      bytesPerRow: l * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(kuva, in: CGRect(x: 0, y: 0, width: l, height: k))
            return true
        }
        if !ok { return nil }
    }

    // y kasvaa alaspäin kuten kuvassa; CGContextin muistissa ensimmäinen rivi on kuvan yläreuna.
    func kirkkaus(_ x: Int, _ y: Int) -> Double {
        guard x >= 0, y >= 0, x < Kuvapisteet.leveys, y < Kuvapisteet.korkeus else { return 0 }
        let i = (y * Kuvapisteet.leveys + x) * 4
        return (Double(data[i]) + Double(data[i + 1]) + Double(data[i + 2])) / 3
    }

    func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
        guard x >= 0, y >= 0, x < Kuvapisteet.leveys, y < Kuvapisteet.korkeus else { return (0, 0, 0) }
        let i = (y * Kuvapisteet.leveys + x) * 4
        return (Double(data[i]), Double(data[i + 1]), Double(data[i + 2]))
    }
}

// "Kuka katsoo?" -ruudun profiilit puhelimen profiilinäkymälle (Netflix ja YouTube): ruudut = profiilien neliöt
// 960×540-kuvassa, fokus = isompana näkyvän (valkoreunaisen) profiilin indeksi, nil = ei tiedossa.
struct Profiilit: Equatable {
    let fokus: Int?
    let ruudut: [CGRect]
}

// Netflixin "Kuka katsoo?" -ruutu (REMOTE-ALOITUS-PROFIILI): profiilit ovat pystylistana x = 148 ympärillä.

extension NetflixRuudukko {
    // Mitattu 5.10.2026: punainen NETFLIX-sana x 90..<205, y 25..<58 (904–908 pistettä); ruutu on rivi,
    // jonka kohdalla jokin x = 130, 148, 165 on pohjaa (< 45) kirkkaampi. Fokusruudun kehys katkoo
    // jakson, joten ≤ 8 pisteen raot yhdistetään. Fokusruutu 95–96 pistettä, muut 63–64.
    static func tunnistaProfiilit(_ k: Kuvapisteet) -> Profiilit? {
        var sana = 0
        for x in 90..<205 {
            for y in 25..<58 {
                let (r, g, b) = k.rgb(x, y)
                if r > 170 && g < 70 && b < 70 { sana += 1 }
            }
        }
        guard sana >= 600 else { return nil }
        var jaksot: [(Int, Int)] = [] // (alku, loppu), loppu poissulkeva
        for y in 80..<Kuvapisteet.korkeus {
            let ruutu = [130, 148, 165].contains { x in let (r, g, b) = k.rgb(x, y); return max(r, g, b) > 45 }
            guard ruutu else { continue }
            if let viimeinen = jaksot.last, y - viimeinen.1 <= 8 {
                jaksot[jaksot.count - 1].1 = y + 1
            } else {
                jaksot.append((y, y + 1))
            }
        }
        jaksot = jaksot.filter { $0.1 - $0.0 >= 50 }
        let korkeudet = jaksot.map { $0.1 - $0.0 }
        guard (2...8).contains(jaksot.count), korkeudet.filter({ $0 >= 80 }).count == 1,
              let fokus = korkeudet.firstIndex(where: { $0 >= 80 }) else { return nil }
        let ruudut = jaksot.map { j -> CGRect in
            let puoli = Double(j.1 - j.0)
            return CGRect(x: 148 - puoli / 2, y: Double(j.0), width: puoli, height: puoli)
        }
        return Profiilit(fokus: fokus, ruudut: ruudut)
    }
}

enum NetflixTila: Equatable {
    case nappain(NetflixRuudukko.Paikka) // fokus näppäimistöllä
    case nav                             // fokus yläpalkin hakukuvakkeessa: alas vie näppäimistölle
    case genre                           // fokus näppäimistön alla olevalla listalla: ylös vie näppäimistölle
    case hakunakyma                      // hakunäkymä näkyy, fokus tuloksissa: vasemmalle vie näppäimistölle
    case muu                             // ei hakunäkymää (esim. video): ei painalluksia
}

struct NetflixKuva {
    let tila: NetflixTila
    let hakuteksti: Bool // hakukentässä on tekstiä (suurennuslasi otsikon paikalla)
}

extension NetflixRuudukko {
    private struct Solu { let p: Paikka; let x, y, puoli: Int }
    private static let solut: [Solu] = [Solu(p: valilyonti, x: 83, y: 78, puoli: 46),
                                        Solu(p: askelpalautin, x: 183, y: 78, puoli: 46)]
        + rivit.enumerated().flatMap { r, rivi in
            (0..<rivi.count).map { c in Solu(p: Paikka(r: r, c: c), x: 50 + 33 * c, y: 112 + 33 * r, puoli: 15) }
        }

    // Fokusruudun valkoinen kehys: keskiarvo kehyksen kohdalta (kirkkaus ~155–190, muut ~22).
    private static func rengas(_ k: Kuvapisteet, _ s: Solu, _ dy: Int) -> Double {
        var summa = 0.0, n = 0
        for d in (-s.puoli + 2)..<(s.puoli - 1) {
            for (a, b) in [(s.x + d, s.y + dy - 15), (s.x + d, s.y + dy + 15),
                           (s.x - s.puoli, s.y + dy + d / 3), (s.x + s.puoli, s.y + dy + d / 3)] {
                summa += k.kirkkaus(a, b); n += 1
            }
        }
        return summa / Double(n)
    }

    private static func laske(_ k: Kuvapisteet, _ x: ClosedRange<Int>, _ y: ClosedRange<Int>, yli: Double) -> Int {
        var n = 0
        for a in x { for b in y where k.kirkkaus(a, b) > yli { n += 1 } }
        return n
    }

    static func tunnista(_ k: Kuvapisteet) -> NetflixKuva {
        let hakuteksti = laske(k, 281...289, 62...84, yli: 150) == 0 && laske(k, 292...306, 62...84, yli: 150) > 5
        // Näppäimistö voi olla siirtynyt muutaman pisteen (vierityksen animaatio).
        var paras: [(Double, Paikka)] = []
        var hakunakyma = 0
        for dy in stride(from: -10, through: 10, by: 2) {
            let p = solut.map { (rengas(k, $0, dy), $0.p) }.sorted { $0.0 > $1.0 }
            if paras.isEmpty || p[0].0 > paras[0].0 { paras = p }
            // Ruutujen tasaisen harmaa pohja (~26) ja musta rako (~2) niiden välissä.
            hakunakyma = max(hakunakyma, solut.filter { $0.puoli == 15 }.filter { s in
                let pohja = k.kirkkaus(s.x - 11, s.y - 11 + dy)
                let rako = min(k.kirkkaus(s.x + 16, s.y - 11 + dy), k.kirkkaus(s.x + 17, s.y - 11 + dy))
                return (18...40).contains(pohja) && rako < 12
            }.count)
        }
        if paras[0].0 > 100 && paras[1].0 < 60 { return NetflixKuva(tila: .nappain(paras[0].1), hakuteksti: hakuteksti) }
        if laske(k, 246...265, 18...37, yli: 200) > 200 { return NetflixKuva(tila: .nav, hakuteksti: hakuteksti) }
        let genre = stride(from: 100, to: 540, by: 2).contains { y in [40, 120, 200].allSatisfy { k.kirkkaus($0, y) > 200 } }
        if genre { return NetflixKuva(tila: .genre, hakuteksti: hakuteksti) }
        return NetflixKuva(tila: hakunakyma >= 30 ? .hakunakyma : .muu, hakuteksti: hakuteksti)
    }
}

import CoreGraphics
import Foundation

// YouTuben "Kuka katsoo?" (REMOTE-ALOITUS-YOUTUBE-PROFIILI): profiilit ovat vaakarivinä ympyröinä. Mitattu
// 6.10.2026 (960×540, kuvat Macin /tmp/lgtv-koe/s1–s6): kylmäkäynnistyksessä YouTube-logo ylhäällä ja ympyröiden
// keskirivi y 251, sivupalkin ylimmästä kohdasta avattuna otsikko "Kuka katsoo?" ja keskirivi y 230. Ympyrä 148 px,
// fokusympyrä 158–173 px valkoisella kehällä, keskiväli 175–180 px. Rivin perässä "Lisää tili" ja "Lisää lastentili"
// (harmaa ympyrä ja valkoinen risti; fokuksessa valkoinen ympyrä). Rivi vierii fokuksen mukana niin, että fokuksen
// vasemmalla puolella näkyy aina yksi ympyrä: fokus on vasemmassa reunassa (paikka 0) vain ensimmäisessä
// profiilissa. Muualla fokuksen indeksiä ei voi lukea kuvasta, joten valinta lähtee aina paikasta 0.
struct YouTubeProfiiliKuva {
    let ruudut: [CGRect]         // näkyvät profiilit vasemmalta (ilman lisäysympyröitä)
    let fokusPaikka: Int         // fokusympyrän järjestys näkyvissä ympyröissä; 0 = ensimmäinen profiili
    let fokusProfiili: Bool      // fokus profiilissa, ei lisäysympyrässä
    let allekirjoitus: [Double]  // fokuksen paikka ja ympyröiden värit: siirtymän tunnistus
}

extension YouTubeRuudukko {
    private static let riviY = 240, taustaY = 140 // rivi leikkaa molempien näkymien ympyrät; tausta ympyröiden yllä

    private static func ero(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2)
    }

    private static func keskiväri(_ k: Kuvapisteet, _ cx: Int, _ cy: Int, _ r: Int) -> (Double, Double, Double) {
        var s = (0.0, 0.0, 0.0), n = 0.0
        for dx in stride(from: -r, through: r, by: 6) {
            for dy in stride(from: -r, through: r, by: 6) where dx * dx + dy * dy <= r * r {
                let p = k.rgb(cx + dx, cy + dy)
                s = (s.0 + p.0, s.1 + p.1, s.2 + p.2); n += 1
            }
        }
        return (s.0 / n, s.1 / n, s.2 / n)
    }

    static func tunnistaProfiilit(_ k: Kuvapisteet) -> YouTubeProfiiliKuva? {
        // Ympyröiden yläpuoli on tummaa taustaa: aloitusnäkymän pikkukuvat eivät käy profiiliriviksi.
        var tumma = 0
        for x in stride(from: 200, to: 760, by: 4) where k.kirkkaus(x, taustaY) < 60 { tumma += 1 }
        guard tumma >= 130 else { return nil }

        // Ympyrät: rivin pisteet, jotka eroavat taustasta (> 40); ≤ 8 px raot yhdistetään (fokuksen musta risti).
        var jaksot: [(Int, Int)] = []
        for x in 0..<Kuvapisteet.leveys where ero(k.rgb(x, riviY), k.rgb(x, taustaY)) > 40 {
            if let v = jaksot.last, x - v.1 <= 8 { jaksot[jaksot.count - 1].1 = x + 1 } else { jaksot.append((x, x + 1)) }
        }
        let ympyrat = jaksot.filter { $0.0 > 1 && $0.1 < Kuvapisteet.leveys - 1 && (130...185).contains($0.1 - $0.0) }
        guard ympyrat.count >= 2 else { return nil }
        let keskit = ympyrat.map { ($0.0 + $0.1) / 2 }
        for i in 1..<keskit.count where !(160...200).contains(keskit[i] - keskit[i - 1]) { return nil }

        // Fokus: valkoinen kehä ympyrän molemmissa reunoissa, täsmälleen yhdessä ympyrässä.
        let kehat = ympyrat.map { j -> Double in
            [j.0 + 1, j.0 + 2, j.0 + 3, j.1 - 4, j.1 - 3, j.1 - 2].map { k.kirkkaus($0, riviY) }.reduce(0, +) / 6
        }
        let fokukset = kehat.indices.filter { kehat[$0] > 150 }
        guard fokukset.count == 1, let fokus = fokukset.first else { return nil }

        // Keskirivi fokuksettoman ympyrän yläreunasta (251 tai 230).
        let i0 = fokus == 0 ? 1 : 0
        guard let yla = (taustaY..<riviY).first(where: {
            ero(k.rgb(keskit[i0], $0), k.rgb(keskit[i0], taustaY)) > 40
        }) else { return nil }
        let cy = yla + (ympyrat[i0].1 - ympyrat[i0].0) / 2

        // Lisäysympyrä: harmaalla valkoinen risti (sivut 15 px kirkkaat, kulmat tummat); fokuksessa valkoinen ympyrä.
        func lisays(_ i: Int) -> Bool {
            let cx = keskit[i]
            if i == fokus {
                let v = keskiväri(k, cx, cy, 40)
                return (v.0 + v.1 + v.2) / 3 > 190 && max(v.0, v.1, v.2) - min(v.0, v.1, v.2) < 30
            }
            let risti = [(0, 0), (-15, 0), (15, 0), (0, -15), (0, 15)].map { k.kirkkaus(cx + $0.0, cy + $0.1) }
            let vino = [(-15, -15), (15, -15), (-15, 15), (15, 15)].map { k.kirkkaus(cx + $0.0, cy + $0.1) }
            return risti.min()! > 200 && vino.max()! < 90
        }
        let profiileja = ympyrat.indices.first(where: lisays) ?? ympyrat.count
        let ruudut = ympyrat.prefix(profiileja).map { j -> CGRect in
            let puoli = Double(j.1 - j.0)
            return CGRect(x: Double(j.0), y: Double(cy) - puoli / 2, width: puoli, height: puoli)
        }
        var allekirjoitus = [Double(keskit[fokus])]
        for c in keskit {
            let v = keskiväri(k, c, cy, 40)
            allekirjoitus += [v.0, v.1, v.2]
        }
        return YouTubeProfiiliKuva(ruudut: ruudut, fokusPaikka: fokus, fokusProfiili: fokus < profiileja,
                                   allekirjoitus: allekirjoitus)
    }

    // Sama kuva: fokus samassa paikassa ja ympyröiden värit ±20 (siirtymää ei tapahtunut).
    static func sama(_ a: [Double], _ b: [Double]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 20 }
    }
}

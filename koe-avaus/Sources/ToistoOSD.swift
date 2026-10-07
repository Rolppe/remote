import CoreGraphics
import Vision

// Jakson kohta ja kesto tauon OSD:stä tekstintunnistuksella (REMOTE-VAAKA-AREENA, REMOTE-VAAKA-NETFLIX). Mitattu
// 960×540-kuvista 7.10.2026 (Macilla `~/remote-koe-avaus/vaaka/` Areena, `~/remote-koe-avaus/nfx/` Netflix).
// Areena: palkki y 441, kohta vasemmalla, kesto oikealla (hh:mm:ss); fokus palkissa → esikatselukupla nupin
// yläpuolella. Netflix: palkki y 450, kohta vasemmalla, oikealla jäljellä oleva aika (mm:ss); esikatselussa
// vasen teksti on esikatselun kohta. `VAATIMUS: REMOTE-ANDROID`: tekstintunnistus on Androidilla ML Kitin
// vastaava kutsu; muu logiikka on pelkkää kuvan rajausta ja aritmetiikkaa.
struct ToistoOSD: Equatable {
    let kohta: Double   // sekunteja jakson alusta (Netflixin esikatselussa esikatselun kohta)
    let kesto: Double
    let kupla: Double?  // Areena, fokus palkissa: kuplan kohta, johon play siirtää (nil = ei kuplaa)

    // Kohta, johon play siirtää esikatselussa.
    var esikatselu: Double { kupla ?? kohta }
}

struct ToistoAsettelu {
    let kohtaAlue: CGRect
    let oikeaAlue: CGRect
    let oikeaJaljella: Bool // oikea teksti on jäljellä oleva aika (Netflix), ei kesto
    let kuplaAlue: CGRect?
    let avaus: String?      // pausen jälkeen esikatseluun: Areenassa UP vie fokuksen palkkiin
    let ensinTyhja: Bool    // Netflix: ensimmäinen RIGHT/LEFT avaa esikatselunauhan siirtämättä (mitattu e01, g01)

    // Rajaukset 960×540-koordinaateissa; kuvan todellinen koko skaalataan.
    static let areena = ToistoAsettelu(kohtaAlue: CGRect(x: 56, y: 428, width: 84, height: 26),
                                       oikeaAlue: CGRect(x: 824, y: 428, width: 84, height: 26), oikeaJaljella: false,
                                       kuplaAlue: CGRect(x: 56, y: 396, width: 852, height: 26),
                                       avaus: "UP", ensinTyhja: false)
    static let netflix = ToistoAsettelu(kohtaAlue: CGRect(x: 148, y: 437, width: 66, height: 26),
                                        oikeaAlue: CGRect(x: 766, y: 437, width: 66, height: 26), oikeaJaljella: true,
                                        kuplaAlue: nil, avaus: nil, ensinTyhja: true)

    static func sovellukselle(_ appId: String?) -> ToistoAsettelu? {
        switch appId {
        case "fi.yle.areena": .areena
        case "netflix": .netflix
        default: nil
        }
    }
}

enum ToistoLukija {
    static let askel = 10.0 // RIGHT/LEFT esikatselussa = ±10 s (Areena n02–n05, f01–f03; Netflix e01–e03, g01–g03)

    static func lue(_ kuva: CGImage, _ a: ToistoAsettelu) -> ToistoOSD? {
        guard let kohta = aika(kuva, a.kohtaAlue), let oikea = aika(kuva, a.oikeaAlue) else { return nil }
        let kesto = a.oikeaJaljella ? kohta + oikea : oikea
        guard kesto > 0, kohta <= kesto else { return nil }
        return ToistoOSD(kohta: kohta, kesto: kesto, kupla: a.kuplaAlue.flatMap { aika(kuva, $0) })
    }

    // Esikatselussa siirrytään kohteeseen n painalluksella; n < 0 = LEFT.
    static func askeleet(nyt: Double, kohde: Double) -> Int { Int(((kohde - nyt) / askel).rounded()) }

    static func sekunnit(_ teksti: String) -> Double? {
        // Tunnistus voi lukea kaksoispisteen pisteeksi tai O:n nollaksi; hyväksytään vain 2–3 numeroryhmää.
        let siisti = teksti.uppercased().replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: ".", with: ":").replacingOccurrences(of: " ", with: "")
        let osat = siisti.split(separator: ":")
        let luvut = osat.compactMap { $0.allSatisfy { $0.isASCII && $0.isNumber } ? Double($0) : nil }
        guard (2...3).contains(osat.count), luvut.count == osat.count, luvut.dropFirst().allSatisfy({ $0 < 60 })
        else { return nil }
        return luvut.reduce(0) { $0 * 60 + $1 }
    }

    private static func aika(_ kuva: CGImage, _ alue: CGRect) -> Double? {
        guard let rajaus = suurenna(kuva, alue) else { return nil }
        let pyynto = VNRecognizeTextRequest()
        pyynto.recognitionLevel = .accurate
        pyynto.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: rajaus, options: [:]).perform([pyynto])
        for havainto in pyynto.results ?? [] {
            for ehdokas in havainto.topCandidates(3) {
                if let s = sekunnit(ehdokas.string) { return s }
            }
        }
        return nil
    }

    // Pieni teksti (≈ 9 px 960×540:ssä) suurennetaan 4× (kuplan leveä kaista 2×) ennen tunnistusta.
    private static func suurenna(_ kuva: CGImage, _ alue: CGRect) -> CGImage? {
        let sx = Double(kuva.width) / 960, sy = Double(kuva.height) / 540
        let r = CGRect(x: alue.minX * sx, y: alue.minY * sy, width: alue.width * sx, height: alue.height * sy)
        guard let osa = kuva.cropping(to: r.integral) else { return nil }
        let kerroin = alue.width > 200 ? 2.0 : 4.0
        let l = Int(alue.width * kerroin), k = Int(alue.height * kerroin)
        guard let ctx = CGContext(data: nil, width: l, height: k, bitsPerComponent: 8, bytesPerRow: l * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(osa, in: CGRect(x: 0, y: 0, width: l, height: k))
        return ctx.makeImage()
    }
}

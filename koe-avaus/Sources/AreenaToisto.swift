import CoreGraphics
import Vision

// Areenan jakson kohta ja kesto (REMOTE-VAAKA-AREENA): tauon OSD:n aikatekstit tekstintunnistuksella. Mitattu
// 960×540-kuvista 7.10.2026 (`~/remote-koe-avaus/vaaka/` Macilla): palkki y 441, x 136–820; kohta vasemmalla
// (x ≈ 72–122), kesto oikealla (x ≈ 837–887), muoto hh:mm:ss. Fokus palkissa → esikatselukupla nupin yläpuolella.
// `VAATIMUS: REMOTE-ANDROID`: tekstintunnistus on Androidilla ML Kitin vastaava kutsu; muu logiikka on pelkkää
// kuvan rajausta ja aritmetiikkaa.
struct AreenaOSD: Equatable {
    let kohta: Double   // sekunteja jakson alusta
    let kesto: Double
    let esikatselu: Double? // fokus palkissa: kuplan kohta, johon play siirtää (nil = palkki ei fokuksessa)
}

enum AreenaToisto {
    static let askel = 10.0 // RIGHT/LEFT palkissa = ±10 s (mitattu n02–n05, f01–f03)

    // Rajaukset 960×540-koordinaateissa; kuvan todellinen koko skaalataan.
    static let kohtaAlue = CGRect(x: 56, y: 428, width: 84, height: 26)
    static let kestoAlue = CGRect(x: 824, y: 428, width: 84, height: 26)
    static let kuplaAlue = CGRect(x: 56, y: 396, width: 852, height: 26) // kupla seuraa nuppia koko leveydeltä

    static func lue(_ kuva: CGImage) -> AreenaOSD? {
        guard let kohta = aika(kuva, kohtaAlue), let kesto = aika(kuva, kestoAlue), kesto > 0, kohta <= kesto
        else { return nil }
        return AreenaOSD(kohta: kohta, kesto: kesto, esikatselu: aika(kuva, kuplaAlue))
    }

    // Palkissa siirrytään kohteeseen n painalluksella; n < 0 = LEFT.
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

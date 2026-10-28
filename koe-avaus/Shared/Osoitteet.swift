import Foundation

// Laitteelle tallennetut osoitteet (asetusnäkymä). Ei oletusarvoja: tyhjä arvo = "aseta osoite" -tila.
// UserDefaults.standard riittää: OpenKaukoIntent avaa äpin (openAppWhenRun) ja suoritetaan äpin prosessissa.
// Testit voivat antaa arvot launch-argumentteina: -kauko_palvelu <osoite> -kauko_tv <osoite>.
enum Osoitteet {
    static let palveluAvain = "kauko_palvelu"
    static let tvAvain = "kauko_tv"
    static let oletusPortti = 8090

    private static func luku(_ avain: String) -> String {
        (UserDefaults.standard.string(forKey: avain) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Palvelun perus-URL (esim. "http://host:8090") tai nil, jos osoitetta ei ole asetettu tai se on virheellinen.
    /// Syöte voi olla "host", "host:portti" tai täysi URL.
    static var palveluURL: String? {
        var s = luku(palveluAvain)
        guard !s.isEmpty else { return nil }
        if s.contains("://") {
            while s.hasSuffix("/") { s.removeLast() }
        } else {
            s = "http://" + (s.contains(":") ? s : "\(s):\(oletusPortti)")
        }
        return URL(string: s)?.host == nil ? nil : s
    }

    /// TV:n isäntänimi tai IP (ilman skeemaa ja porttia); tyhjä, jos ei asetettu.
    static var tv: String {
        var s = luku(tvAvain)
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let i = s.firstIndex(of: "/") { s = String(s[..<i]) }
        if let i = s.firstIndex(of: ":") { s = String(s[..<i]) }
        return s
    }

    static var valmis: Bool { palveluURL != nil && !tv.isEmpty }
}

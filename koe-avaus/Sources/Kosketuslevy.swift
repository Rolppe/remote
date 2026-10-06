import SwiftUI
import ImageIO
import UIKit

// LG C1:n kosketuslevy (REMOTE-TRACKPAD). Puhelin puhuu suoraan TV:lle webOS SSAP:lla:
// pääyhteys wss://<tv>:3001 → register → getPointerInputSocket → toinen websocket, johon
// liikkeet menevät tekstiviesteinä ("type:move\ndx:..\ndy:..\ndown:0\n\n"). Sama protokolla
// toimii Androidilla tavallisella websocket-kirjastolla (VAATIMUS: REMOTE-ANDROID).
// Tekstinsyöttö (REMOTE-TV-SYOTTO): pääyhteys tilaa ssap://com.webos.service.ime/registerRemoteKeyboard;
// kun TV:n tekstikenttä saa fokuksen, puhelimen näppäimistö aukeaa ja muutokset menevät
// insertText/deleteCharacters/sendEnterKey-pyyntöinä.
//
// Netflix-haku (REMOTE-NETFLIX-HAKU): Netflix ei avaa TV:n näppäimistöä, joten kun se on etualalla,
// Kauko näyttää oman hakukentän ja ohjaa Netflixin kirjainruudukkoa (NetflixHaku.swift). Fokus
// luetaan TV:n kuvakaappauksesta (tv/executeOneShot, lupa CONTROL_TV_SCREEN).

let syoteAlku = "\u{200B}" // näkymätön merkki: puhelimen askelpalautin poistaa merkkejä myös TV:ltä

let tvHost = "192.0.2.10"
private let avainKey = "lgtv_client_key"

// Sama manifesti kuin bscpylgtv:llä (LG:n testiallekirjoitus); TV hyväksyy sen kerran ruudulla.
private let manifestSignature =
    "eyJhbGdvcml0aG0iOiJSU0EtU0hBMjU2Iiwia2V5SWQiOiJ0ZXN0LXNpZ25pbmctY2VydCIsInNpZ25hdHVyZVZlcnNpb24iOjF9.hrVRgjCwXVvE2OOSpDZ58hR"
    + "+59aFNwYDyjQgKk3auukd7pcegmE2CzPCa0bJ0ZsRAcKkCTJrWo5iDzNhMBWRy"
    + "aMOv5zWSrthlf7G128qvIlpMT0YNY+n/FaOHE73uLrS/g7swl3/qH/BGFG2Hu4"
    + "RlL48eb3lLKqTt2xKHdCs6Cd4RMfJPYnzgvI4BNrFUKsjkcu+WD4OO2A27Pq1n"
    + "50cMchmcaXadJhGrOqH5YmHdOCj5NSHzJYrsW0HPlpuAx/ECMeIZYDh6RMqaFM"
    + "2DXzdKX9NmmyqzJ3o/0lkk/N97gfVRLW5hA29yeAwaCViZNCP8iC9aO0q9fQoj"
    + "oa7NQnAtw=="

private func manifest() -> [String: Any] {
    [
        "appVersion": "1.1",
        "manifestVersion": 1,
        "deviceName": "Kauko",
        "permissions": ["LAUNCH", "CONTROL_AUDIO", "CONTROL_DISPLAY", "CONTROL_INPUT_JOYSTICK",
                        "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_INPUT_TV", "CONTROL_POWER",
                        "READ_APP_STATUS", "READ_POWER_STATE", "CONTROL_INPUT_TEXT",
                        "CONTROL_MOUSE_AND_KEYBOARD", "CONTROL_TV_SCREEN", "READ_RUNNING_APPS",
                        "READ_INSTALLED_APPS"],
        "signatures": [["signature": manifestSignature, "signatureVersion": 1]],
        "signed": [
            "appId": "com.lge.test",
            "created": "20140509",
            "localizedAppNames": ["": "LG Remote App", "ko-KR": "리모컨 앱", "zxx-XX": "ЛГ Rэмotэ AПП"],
            "localizedVendorNames": ["": "LG Electronics"],
            "permissions": ["TEST_SECURE", "CONTROL_INPUT_TEXT", "CONTROL_MOUSE_AND_KEYBOARD",
                            "READ_INSTALLED_APPS", "READ_LGE_SDX", "READ_NOTIFICATIONS", "SEARCH",
                            "WRITE_SETTINGS", "WRITE_NOTIFICATION_ALERT", "CONTROL_POWER",
                            "READ_CURRENT_CHANNEL", "READ_RUNNING_APPS", "READ_UPDATE_INFO",
                            "UPDATE_FROM_REMOTE_APP", "READ_LGE_TV_INPUT_EVENTS", "READ_TV_CURRENT_TIME"],
            "serial": "2f930e2d2cfe083771f68e4fe7bb07",
            "vendorId": "com.lge",
        ],
    ]
}

@MainActor
final class LGTV: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var tila = "Ei yhteyttä"
    @Published var valmis = false
    @Published var nappaimisto = false
    @Published var netflix = false
    @Published var areena = false           // Yle Areena etualalla (AreenaHaku.swift)
    @Published var youtube = false          // YouTube etualalla (YouTubeHaku.swift)
    @Published var hakee = false
    @Published var etuala: String?          // TV:n etualalla oleva sovellus (appId)
    @Published var kaynnistys: String?      // aloitussivun valinnan eteneminen (Aloitus.swift)
    @Published var profiiliValinta = false  // Netflixin profiilin valinta napauttamalla
    @Published var profiilit: NetflixProfiilit?   // TV:n kuvakaappauksesta tunnistetut profiilit
    @Published var profiiliKuvat: [UIImage] = []  // profiilien omat kuvat (rajaukset kuvakaappauksesta)

    private var session: URLSession!
    private var paa: URLSessionWebSocketTask?
    private var osoitin: URLSessionWebSocketTask?
    private var odotusDx = 0.0, odotusDy = 0.0
    private var lahettaa = false
    private var yhdistysTyo: Task<Void, Never>?
    private var vastasi = false // TV vastasi tämän yhteyden ensimmäiseen viestiin
    private var pyyntoNro = 0
    private var odottavat: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private(set) lazy var areenaHaku = RuudukkoHaku<AreenaRuudukko>(tv: self)
    private(set) lazy var youtubeHaku = RuudukkoHaku<YouTubeRuudukko>(tv: self)
    private let netflixViive = 0.05 // 40–80 ms ruudukon sisällä: 0/52 painallusta hukkui (5.10.2026)

    override init() {
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    }

    // TV:n varmenne on itse allekirjoitettu: hyväksytään vain TV:n osoitteelle.
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host == tvHost, let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }

    // Yksi yhdistys kerrallaan: rinnakkainen kutsuja odottaa käynnissä olevaa. Sammuksissa oleva TV ei
    // vastaa lainkaan, joten yhteys katkaistaan, jos ensimmäistä vastausta ei tule aikarajassa.
    func yhdista(aikaraja: Double = 4) async {
        if valmis { return }
        if let tyo = yhdistysTyo { await tyo.value; return }
        let tyo = Task { await yhdistaNyt(aikaraja) }
        yhdistysTyo = tyo
        await tyo.value
        yhdistysTyo = nil
    }

    private func yhdistaNyt(_ aikaraja: Double) async {
        katkaise()
        let t0 = Date()
        tila = "Yhdistetään TV:hen…"
        do {
            let ws = session.webSocketTask(with: URL(string: "wss://\(tvHost):3001")!)
            ws.resume()
            paa = ws
            vastasi = false
            let vahti = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(aikaraja * 1_000_000_000))
                guard let self, !self.vastasi, self.paa === ws else { return }
                ws.cancel(with: .goingAway, reason: nil)
            }
            defer { vahti.cancel() }
            var payload: [String: Any] = ["forcePairing": false, "pairingType": "PROMPT", "manifest": manifest()]
            if let avain = UserDefaults.standard.string(forKey: avainKey) { payload["client-key"] = avain }
            try await laheta(ws, ["type": "register", "id": "reg0", "payload": payload])
            while true {
                let v = try await vastaanota(ws)
                vastasi = true
                let tyyppi = v["type"] as? String
                if tyyppi == "registered" {
                    if let avain = (v["payload"] as? [String: Any])?["client-key"] as? String {
                        UserDefaults.standard.set(avain, forKey: avainKey)
                    }
                    break
                } else if tyyppi == "error" {
                    throw NSError(domain: "LGTV", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: v["error"] as? String ?? "rekisteröinti hylätty"])
                } else if (v["payload"] as? [String: Any])?["pairingType"] != nil {
                    tila = "Hyväksy pariliitos TV:n ruudulla"
                }
            }
            try await laheta(ws, ["type": "request", "id": "ptr",
                                  "uri": "ssap://com.webos.service.networkinput/getPointerInputSocket"])
            var polku: String?
            while polku == nil {
                let v = try await vastaanota(ws)
                if v["id"] as? String == "ptr" { polku = (v["payload"] as? [String: Any])?["socketPath"] as? String }
            }
            guard let p = polku, let url = URL(string: p) else { throw NSError(domain: "LGTV", code: 2) }
            let o = session.webSocketTask(with: url)
            o.resume()
            osoitin = o
            try await laheta(ws, ["type": "subscribe", "id": "ime",
                                  "uri": "ssap://com.webos.service.ime/registerRemoteKeyboard"])
            try await laheta(ws, ["type": "subscribe", "id": "fg",
                                  "uri": "ssap://com.webos.applicationManager/getForegroundAppInfo"])
            valmis = true
            tila = "Yhdistetty \(Int(Date().timeIntervalSince(t0) * 1000)) ms"
            kuuntele(ws)
        } catch {
            katkaise()
            tila = vastasi ? "TV: \(error.localizedDescription)" : "TV ei vastaa (sammuksissa?)"
        }
    }

    // Pääyhteyden viestit luetaan, jotta katkos huomataan ja seuraava kosketus yhdistää uudelleen.
    private func kuuntele(_ ws: URLSessionWebSocketTask) {
        ws.receive { [weak self] tulos in
            Task { @MainActor in
                guard let self, ws === self.paa else { return }
                switch tulos {
                case .failure: self.katkaise(); self.tila = "Yhteys katkesi"
                case .success(let viesti): self.kasittele(viesti); self.kuuntele(ws)
                }
            }
        }
    }

    private func kasittele(_ viesti: URLSessionWebSocketTask.Message) {
        guard case .string(let s) = viesti,
              let v = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
              let id = v["id"] as? String else { return }
        if let jatko = odottavat.removeValue(forKey: id) {
            if v["type"] as? String == "error" {
                jatko.resume(throwing: virhe(v["error"] as? String ?? "TV hylkäsi pyynnön"))
            } else {
                jatko.resume(returning: v)
            }
            return
        }
        let payload = v["payload"] as? [String: Any]
        if id == "ime", let widget = payload?["currentWidget"] as? [String: Any] {
            nappaimisto = widget["focus"] as? Bool ?? false
        } else if id == "fg", let appId = payload?["appId"] as? String {
            etuala = appId
            netflix = appId == "netflix"
            if !netflix { netflixPaikka = nil; netflixKasin = false }
            areena = appId == "fi.yle.areena"
            if !areena { areenaHaku.nollaa() }
            youtube = appId == "youtube.leanback.v4"
            if !youtube { youtubeHaku.nollaa() }
        }
    }

    // Pyyntö, jonka vastaus odotetaan pääyhteydeltä (id:llä); aikakatkaisu ettei haku jää jumiin.
    func pyyda(_ uri: String, _ payload: [String: Any], aika: Double = 4) async throws -> [String: Any] {
        guard let ws = paa else { throw virhe("ei yhteyttä") }
        pyyntoNro += 1
        let id = "q\(pyyntoNro)"
        let data = try JSONSerialization.data(withJSONObject: ["type": "request", "id": id, "uri": uri,
                                                               "payload": payload])
        return try await withCheckedThrowingContinuation { jatko in
            odottavat[id] = jatko
            ws.send(.string(String(decoding: data, as: UTF8.self))) { [weak self] e in
                guard let e else { return }
                Task { @MainActor in self?.odottavat.removeValue(forKey: id)?.resume(throwing: e) }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(aika * 1_000_000_000))
                self?.odottavat.removeValue(forKey: id)?.resume(throwing: virhe("TV ei vastannut"))
            }
        }
    }

    func kuvakaappausKuva() async throws -> CGImage {
        let v = try await pyyda("ssap://tv/executeOneShot", ["path": "/tmp/capture.png", "method": "DISPLAY",
                                                             "format": "PNG"])
        guard let uri = (v["payload"] as? [String: Any])?["imageUri"] as? String,
              let url = URL(string: uri) else { throw virhe("ei kuvakaappausta") }
        let (data, _) = try await session.data(from: url)
        guard let lahde = CGImageSourceCreateWithData(data as CFData, nil),
              let kuva = CGImageSourceCreateImageAtIndex(lahde, 0, nil) else { throw virhe("kuvaa ei voi lukea") }
        return kuva
    }

    private func kuvakaappaus() async throws -> NetflixKuva {
        guard let pisteet = Kuvapisteet(try await kuvakaappausKuva()) else { throw virhe("kuvaa ei voi lukea") }
        return NetflixRuudukko.tunnista(pisteet)
    }

    func painele(_ napit: [String], _ viive: Double) async throws {
        for n in napit {
            guard osoitin != nil else { throw virhe("yhteys katkesi") }
            osoitinViesti("type:button\nname:\(n)\n\n")
            try await Task.sleep(nanoseconds: UInt64(viive * 1_000_000_000))
        }
    }

    // Netflixin "Kuka katsoo?" -vahti (REMOTE-ALOITUS-KORJAUS): kun Netflix-näkymä on auki, TV:n kuvaa katsotaan
    // 1,5 s välein (valitun profiilin jälkeen 5 s, haun ajan tauolla). Profiiliruutu näytetään puhelimessa, kun
    // se ilmestyy TV:lle: kylmäkäynnistyksessä vasta TV:n ja Netflixin heräämisen jälkeen (6.10.2026 10 s:n
    // tarkkailu ei ehtinyt), ja myös myöhemmin, kun profiilia vaihdetaan TV:llä. Oletusprofiili valitaan vain
    // käynnistyksen jälkeen (netflixOletusAsti), ei myöhemmässä vaihdossa. Kun TV poistuu profiiliruudulta
    // (valinta TV:n omalla säätimellä), puhelimen profiilinäkymä sulkeutuu.
    var netflixOletusAsti = Date.distantPast
    private var profiiliVahtiTyo: Task<Void, Never>?
    private var profiiliValitsee = false

    func profiiliVahti(_ paalla: Bool) {
        profiiliVahtiTyo?.cancel()
        profiiliVahtiTyo = nil
        guard paalla else { return }
        profiiliVahtiTyo = Task { [weak self] in
            var nakyi = false, valittu = false
            while !Task.isCancelled {
                guard let self else { return }
                if valmis && !hakee && !profiiliValitsee && netflixTyo == nil {
                    do {
                        let tulos = try await profiiliKuva()
                        if Task.isCancelled { return }
                        if let p = tulos, !nakyi {
                            profiiliValinta = true
                            valittu = false
                            if Date() < netflixOletusAsti,
                               let oletus = UserDefaults.standard.object(forKey: "netflix_oletusprofiili") as? Int,
                               oletus < p.ruudut.count {
                                netflixOletusAsti = .distantPast
                                await profiiliValitse(oletus)
                            }
                        } else if tulos == nil && nakyi {
                            profiiliValinta = false
                            valittu = true
                        }
                        nakyi = tulos != nil
                    } catch {}
                }
                try? await Task.sleep(nanoseconds: valittu ? 5_000_000_000 : 1_500_000_000)
            }
        }
    }

    // Yksi kuva: profiilit (ja niiden omat kuvat) talteen, jos TV näyttää profiiliruudun; nil = ei profiiliruutua.
    // Heittää, jos kuvaa ei saatu, jotta ohimenevä virhe ei sulje profiilinäkymää.
    private func profiiliKuva() async throws -> NetflixProfiilit? {
        let kuva = try await kuvakaappausKuva()
        guard let pisteet = Kuvapisteet(kuva) else { throw virhe("kuvaa ei voi lukea") }
        guard let p = NetflixRuudukko.tunnistaProfiilit(pisteet) else { return nil }
        profiilit = p
        profiiliKuvat = p.ruudut.map { r in
            UIGraphicsImageRenderer(size: r.size).image { _ in
                UIImage(cgImage: kuva).draw(in: CGRect(x: -r.minX, y: -r.minY, width: 960, height: 540))
            }
        }
        return p
    }

    // Napautettu profiili: fokus siirretään kuvan mukaan erotuksen verran (lista on pystysuora: alas = seuraava),
    // ja OK lähtee vasta, kun kuva näyttää fokuksen valitussa profiilissa (REMOTE-KOE-TOISTO). Jokainen siirto
    // tarkistetaan kuvasta: 6.10.2026 sokea UP×n + DOWN×i 0,15 s tahdilla vei fokuksen oikeaan profiiliin, mutta
    // heti otettu kuva ei vahvistanut sitä (animaatio kesken), joten OK jäi lähtemättä.
    func profiiliValitse(_ indeksi: Int) async {
        guard !profiiliValitsee else { return }
        profiiliValitsee = true
        defer { profiiliValitsee = false }
        for _ in 0..<6 {
            do {
                guard let nyt = try await profiiliKuva() else { tila = "Netflix: profiiliruutu ei näy TV:llä"; return }
                if nyt.fokus == indeksi {
                    nappi("ENTER")
                    profiiliValinta = false
                    profiilit = nil
                    profiiliKuvat = []
                    tila = "Netflix: profiili valittu"
                    return
                }
                let ero = indeksi - nyt.fokus
                try await painele(Array(repeating: ero > 0 ? "DOWN" : "UP", count: abs(ero)), 0.3)
            } catch {}
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
        tila = "Netflix: profiilin fokus ei täsmää — napauta uudelleen"
    }

    // Kirjoittaa haun Netflixin ruudukolla sitä mukaa kuin kenttään kirjoitetaan: muutokset jonoon,
    // yksi työ purkaa jonon. OK (ENTER) lähtee vain, kun fokuksen paikka on tiedossa: se luetaan kuvasta
    // (ja fokus palautetaan nuolilla), ja sen jälkeen lasketaan painalluksista. Laskettu paikka kelpaa
    // vain tuoreena: kosketuslevy ja Kaukon napit nollaavat sen heti (fokus seuraa osoitinta), TV:n oma
    // kaukosäädin vasta netflixTuoreus-ajan jälkeen. Tauon jälkeen kuva tarkistaa paikan.
    private enum NetflixOp { case avaa, tuloksiin, tyhjenna, poista, kirjain(Character) }
    private var netflixJono: [NetflixOp] = []
    private var netflixPaikka: NetflixRuudukko.Paikka?
    private var netflixAika = Date.distantPast // milloin paikka viimeksi laskettiin tai nähtiin
    private let netflixTuoreus = 5.0
    private var netflixKasin = false // TV:n tekstiä poistettu tyhjästä kentästä: uusi haku ei tyhjennä
    private var netflixTyo: Task<Void, Never>?
    private var netflixTarkistus: Task<Void, Never>?

    func netflixSyota(vanha: String, uusi: String) {
        let v = NetflixRuudukko.normalisoi(vanha), u = NetflixRuudukko.normalisoi(uusi)
        guard v != u else { return }
        if v.isEmpty && !netflixKasin { netflixJono.append(.tyhjenna) }
        let yhteinen = zip(v, u).prefix { $0 == $1 }.count
        netflixJono += Array(repeating: .poista, count: v.count - yhteinen)
        netflixJono += u.dropFirst(yhteinen).map { .kirjain($0) }
        netflixKaynnista()
    }

    // Askelpalautin tyhjässä kentässä: poistaa merkin TV:n kentästä (teksti, jota Kauko ei kirjoittanut).
    func netflixPoista() {
        netflixKasin = true
        netflixJono.append(.poista)
        netflixKaynnista()
    }

    // Hakukentän fokus: Netflixin haku auki TV:llä (suurennuslasi), jotta näppäimistö on valmiina.
    func netflixAvaaHaku() {
        netflixJono.append(.avaa)
        netflixKaynnista()
    }

    // Enter: fokus näppäimistöltä hakutuloksiin (oikealle näppäimistön ohi).
    func netflixTuloksiin() {
        netflixJono.append(.tuloksiin)
        netflixKaynnista()
    }

    // Tyhjennysnappi: koko TV:n hakukenttä tyhjäksi.
    func netflixTyhjennaKentta() {
        netflixKasin = false
        netflixJono.append(.tyhjenna)
        netflixKaynnista()
    }

    private func netflixKaynnista() {
        netflixTarkistus?.cancel()
        if netflixTyo == nil { netflixTyo = Task { await netflixAja() } }
    }

    private func netflixAja() async {
        hakee = true
        defer { hakee = false; netflixTyo = nil }
        do {
            if !valmis { await yhdista() }
            guard valmis else { throw virhe("ei yhteyttä TV:hen") }
            while !netflixJono.isEmpty {
                let jono = netflixJono
                netflixJono = []
                var paikka = Date().timeIntervalSince(netflixAika) < netflixTuoreus ? netflixPaikka : nil
                var napit: [String] = []
                for op in jono {
                    if case .tyhjenna = op {
                        try await netflixPaina(napit, paikka)
                        napit = []
                        paikka = try await netflixTyhjenna()
                        continue
                    }
                    if case .avaa = op {
                        try await netflixPaina(napit, paikka)
                        napit = []
                        try await netflixHakuAuki()
                        paikka = nil
                        continue
                    }
                    if paikka == nil { paikka = try await netflixAnkkuroi().0 }
                    guard var p = paikka else { throw virhe("fokus ei löydy näppäimistöltä") }
                    switch op {
                    case .avaa, .tyhjenna:
                        break
                    case .tuloksiin:
                        // Ylärivistä alas (välilyönti → b, askelpalautin → e), sitten oikealle ruudukon ohi.
                        var c = p.c
                        if p.r == -1 {
                            napit.append("DOWN")
                            c = p == NetflixRuudukko.valilyonti ? 1 : 4
                        }
                        napit += Array(repeating: "RIGHT", count: 6 - c)
                        try await netflixPaina(napit, nil)
                        napit = []
                        paikka = nil
                        tila = "Netflix: valitse tulos kosketuslevyllä"
                        continue
                    case .poista:
                        napit += NetflixRuudukko.siirry(p, NetflixRuudukko.askelpalautin) + ["ENTER"]
                        p = NetflixRuudukko.askelpalautin
                    case .kirjain(let ch):
                        let (n, loppu) = NetflixRuudukko.painallukset(String(ch), alku: p)
                        napit += n
                        p = loppu
                    }
                    paikka = p
                }
                try await netflixPaina(napit, paikka)
            }
            if netflixPaikka != nil { tila = "Netflix: haku TV:llä" }
            netflixTarkistus = Task { await netflixTarkista() }
        } catch {
            netflixJono = []
            netflixPaikka = nil
            tila = "Netflix-haku: \(error.localizedDescription)"
        }
    }

    // Kesken painallusten paikka ei ole varma; valmiina se on laskettu loppupaikka.
    private func netflixPaina(_ napit: [String], _ loppu: NetflixRuudukko.Paikka?) async throws {
        guard !napit.isEmpty else { return }
        netflixPaikka = nil
        try await painele(napit, netflixViive)
        netflixPaikka = loppu
        netflixAika = Date()
    }

    private func netflixTarkista() async {
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !Task.isCancelled, netflixTyo == nil, let odotettu = netflixPaikka,
              let kuva = try? await kuvakaappaus(), !Task.isCancelled, netflixTyo == nil else { return }
        if kuva.tila != .nappain(odotettu) {
            netflixPaikka = nil
            tila = "Netflix: fokus siirtyi — tarkista TV:n hakukenttä"
        } else {
            netflixAika = Date()
        }
    }

    // Fokus näppäimistölle: kuva kertoo paikan; muuten nuolet ja uusi kuva (enintään kolme kierrosta).
    private func netflixAnkkuroi() async throws -> (NetflixRuudukko.Paikka, Bool) {
        var kuva = try await kuvakaappaus()
        var avattu = false
        for kierros in 1...5 {
            if case .nappain(let p) = kuva.tila { return (p, kuva.hakuteksti) }
            guard kierros <= 4 else { break }
            switch kuva.tila {
            case .nav: try await painele(["DOWN"], 0.15)
            case .genre: try await painele(["UP"], 0.15)
            case .hakunakyma: try await painele(Array(repeating: "LEFT", count: 6), 0.15)
            default:
                guard !avattu else { throw virhe("Netflixin haku ei auennut") }
                avattu = true
                try await netflixHakuAuki()
            }
            try await Task.sleep(nanoseconds: 400_000_000)
            kuva = try await kuvakaappaus()
        }
        throw virhe("fokus ei löydy näppäimistöltä")
    }

    // Suurennuslasi automaattisesti: hakunäkymän ulkopuolelta ylös yläpalkkiin (UP×8) ja vasemmalle,
    // kunnes kuva näyttää fokuksen hakukuvakkeessa (tila nav), sitten OK. Haku on jo auki, jos kuva
    // näyttää näppäimistön, genrelistan tai tulokset. Videon aikana LEFT kelaisi: vasemmalle enintään 6.
    private func netflixHakuAuki() async throws {
        var kuva = try await kuvakaappaus()
        var ylhaalla = false, vasemmalle = 0
        while true {
            switch kuva.tila {
            case .nappain, .genre, .hakunakyma:
                return
            case .nav:
                try await painele(["ENTER"], 0.15)
                try await Task.sleep(nanoseconds: 700_000_000)
                if try await kuvakaappaus().tila == .muu { throw virhe("suurennuslasi ei avannut hakua") }
                return
            case .muu:
                if !ylhaalla {
                    tila = "Netflix: avataan haku…"
                    try await painele(Array(repeating: "UP", count: 8), 0.12)
                    ylhaalla = true
                } else {
                    guard vasemmalle < 6 else { throw virhe("Netflixin suurennuslasia ei löytynyt") }
                    try await painele(["LEFT"], 0.2)
                    vasemmalle += 1
                }
            }
            try await Task.sleep(nanoseconds: 400_000_000)
            kuva = try await kuvakaappaus()
        }
    }

    // Koko kenttä tyhjäksi: paikka ja teksti kuvasta (myös teksti, jota Kauko ei kirjoittanut),
    // sitten askelpalautin 20 kertaa kierroksessa, kunnes kuva näyttää tyhjän kentän.
    private func netflixTyhjenna() async throws -> NetflixRuudukko.Paikka {
        netflixPaikka = nil
        var (paikka, teksti) = try await netflixAnkkuroi()
        for kierros in 0...3 {
            if !teksti {
                netflixPaikka = paikka
                netflixAika = Date()
                return paikka
            }
            guard kierros < 3 else { break }
            try await painele(NetflixRuudukko.siirry(paikka, NetflixRuudukko.askelpalautin)
                + Array(repeating: "ENTER", count: 20), netflixViive)
            paikka = NetflixRuudukko.askelpalautin
            try await Task.sleep(nanoseconds: 500_000_000)
            let kuva = try await kuvakaappaus()
            guard kuva.tila == .nappain(paikka) else { throw virhe("fokus karkasi tyhjennyksessä") }
            teksti = kuva.hakuteksti
        }
        throw virhe("hakukenttä ei tyhjentynyt")
    }

    func virhe(_ viesti: String) -> NSError {
        NSError(domain: "LGTV", code: 3, userInfo: [NSLocalizedDescriptionKey: viesti])
    }

    // Puhelimen kentän muutos TV:lle: yhteisen alun jälkeinen osa poistetaan ja uusi kirjoitetaan.
    func syota(vanha: String, uusi: String) {
        let yhteinen = zip(vanha, uusi).prefix { $0 == $1 }.count
        let poistettavat = vanha.count - yhteinen
        if poistettavat > 0 { ime("deleteCharacters", ["count": poistettavat]) }
        let lisattava = String(uusi.dropFirst(yhteinen))
        if !lisattava.isEmpty { ime("insertText", ["text": lisattava, "replace": 0]) }
    }

    func enter() { ime("sendEnterKey", [:]) }

    private func ime(_ metodi: String, _ payload: [String: Any]) {
        guard let ws = paa else { return }
        pyyntoNro += 1
        let viesti: [String: Any] = ["type": "request", "id": "ime\(pyyntoNro)",
                                     "uri": "ssap://com.webos.service.ime/\(metodi)", "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: viesti) else { return }
        ws.send(.string(String(decoding: data, as: UTF8.self))) { [weak self] virhe in
            guard virhe != nil else { return }
            Task { @MainActor in self?.katkaise(); self?.tila = "Yhteys katkesi" }
        }
    }

    func katkaise() {
        osoitin?.cancel(with: .normalClosure, reason: nil)
        paa?.cancel(with: .normalClosure, reason: nil)
        osoitin = nil
        paa = nil
        valmis = false
        nappaimisto = false
        netflix = false
        areena = false
        areenaHaku.nollaa()
        youtube = false
        youtubeHaku.nollaa()
        etuala = nil
        netflixPaikka = nil
        netflixJono = []
        netflixKasin = false
        let kesken = odottavat
        odottavat = [:]
        for jatko in kesken.values { jatko.resume(throwing: virhe("yhteys katkesi")) }
        lahettaa = false
        odotusDx = 0
        odotusDy = 0
    }

    // Liikkeet kasataan: kun edellinen lähetys on kesken, uudet siirtymät summautuvat seuraavaan.
    func liiku(_ dx: Double, _ dy: Double) {
        netflixPaikka = nil // Netflixin fokus seuraa osoitinta
        areenaHaku.paikka = nil
        youtubeHaku.paikka = nil
        odotusDx += dx
        odotusDy += dy
        tyhjenna()
    }

    private func tyhjenna() {
        guard !lahettaa, let o = osoitin else { return }
        let dx = Int(odotusDx.rounded()), dy = Int(odotusDy.rounded())
        guard dx != 0 || dy != 0 else { return }
        odotusDx -= Double(dx)
        odotusDy -= Double(dy)
        lahettaa = true
        o.send(.string("type:move\ndx:\(dx)\ndy:\(dy)\ndown:0\n\n")) { [weak self] virhe in
            Task { @MainActor in
                guard let self else { return }
                self.lahettaa = false
                if virhe != nil { self.katkaise(); self.tila = "Yhteys katkesi" } else { self.tyhjenna() }
            }
        }
    }

    func klikkaa() { netflixPaikka = nil; areenaHaku.paikka = nil; youtubeHaku.paikka = nil; osoitinViesti("type:click\n\n") }
    func vieritä(_ dy: Int) { netflixPaikka = nil; areenaHaku.paikka = nil; youtubeHaku.paikka = nil; osoitinViesti("type:scroll\ndx:0\ndy:\(dy)\n\n") }
    func nappi(_ nimi: String) { netflixPaikka = nil; areenaHaku.paikka = nil; youtubeHaku.paikka = nil; osoitinViesti("type:button\nname:\(nimi)\n\n") }

    private func osoitinViesti(_ viesti: String) {
        guard let o = osoitin else { Task { await yhdista() }; return }
        o.send(.string(viesti)) { [weak self] virhe in
            guard virhe != nil else { return }
            Task { @MainActor in self?.katkaise(); self?.tila = "Yhteys katkesi" }
        }
    }

    private func laheta(_ ws: URLSessionWebSocketTask, _ viesti: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: viesti)
        try await ws.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func vastaanota(_ ws: URLSessionWebSocketTask) async throws -> [String: Any] {
        let viesti = try await ws.receive()
        let data: Data
        switch viesti {
        case .string(let s): data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: data = Data()
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

// Kosketuslevy ja sen oikean reunan vierityspalkki: liu'utus liikuttaa kursoria, napautus valitsee.
struct Kosketusalue: View {
    @ObservedObject var tv: LGTV
    @State private var edellinen: CGSize = .zero
    @State private var vierEdellinen: CGFloat = 0
    private let herkkyys = 1.6

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemFill))
                .overlay(Text(tv.valmis ? "Liu'uta: kursori · napauta: valitse" : tv.tila)
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding())
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let d = CGSize(width: g.translation.width - edellinen.width,
                                       height: g.translation.height - edellinen.height)
                        edellinen = g.translation
                        if tv.valmis { tv.liiku(d.width * herkkyys, d.height * herkkyys) } else { Task { await tv.yhdista() } }
                    }
                    .onEnded { g in
                        edellinen = .zero
                        if abs(g.translation.width) < 6 && abs(g.translation.height) < 6 {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            tv.klikkaa()
                        }
                    })
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 54)
                .overlay(Image(systemName: "arrow.up.and.down").foregroundStyle(.secondary))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let d = g.translation.height - vierEdellinen
                        if abs(d) >= 12 {
                            tv.vieritä(d > 0 ? -1 : 1)
                            vierEdellinen = g.translation.height
                        }
                    }
                    .onEnded { _ in vierEdellinen = 0 })
        }
    }
}

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

private let syoteAlku = "\u{200B}" // näkymätön merkki: puhelimen askelpalautin poistaa merkkejä myös TV:ltä

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
                        "CONTROL_MOUSE_AND_KEYBOARD", "CONTROL_TV_SCREEN", "READ_RUNNING_APPS"],
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
    @Published var hakee = false

    private var session: URLSession!
    private var paa: URLSessionWebSocketTask?
    private var osoitin: URLSessionWebSocketTask?
    private var odotusDx = 0.0, odotusDy = 0.0
    private var lahettaa = false
    private var yhdistaa = false
    private var pyyntoNro = 0
    private var odottavat: [String: CheckedContinuation<[String: Any], Error>] = [:]
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

    func yhdista() async {
        guard !yhdistaa, !valmis else { return }
        yhdistaa = true
        defer { yhdistaa = false }
        katkaise()
        let t0 = Date()
        tila = "Yhdistetään TV:hen…"
        do {
            let ws = session.webSocketTask(with: URL(string: "wss://\(tvHost):3001")!)
            ws.resume()
            paa = ws
            var payload: [String: Any] = ["forcePairing": false, "pairingType": "PROMPT", "manifest": manifest()]
            if let avain = UserDefaults.standard.string(forKey: avainKey) { payload["client-key"] = avain }
            try await laheta(ws, ["type": "register", "id": "reg0", "payload": payload])
            while true {
                let v = try await vastaanota(ws)
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
            tila = "TV: \(error.localizedDescription)"
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
            netflix = appId == "netflix"
        }
    }

    // Pyyntö, jonka vastaus odotetaan pääyhteydeltä (id:llä); aikakatkaisu ettei haku jää jumiin.
    private func pyyda(_ uri: String, _ payload: [String: Any], aika: Double = 4) async throws -> [String: Any] {
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

    private func kuvakaappaus() async throws -> NetflixKuva {
        let v = try await pyyda("ssap://tv/executeOneShot", ["path": "/tmp/capture.png", "method": "DISPLAY",
                                                             "format": "PNG"])
        guard let uri = (v["payload"] as? [String: Any])?["imageUri"] as? String,
              let url = URL(string: uri) else { throw virhe("ei kuvakaappausta") }
        let (data, _) = try await session.data(from: url)
        guard let lahde = CGImageSourceCreateWithData(data as CFData, nil),
              let kuva = CGImageSourceCreateImageAtIndex(lahde, 0, nil),
              let pisteet = Kuvapisteet(kuva) else { throw virhe("kuvaa ei voi lukea") }
        return NetflixRuudukko.tunnista(pisteet)
    }

    private func painele(_ napit: [String], _ viive: Double) async throws {
        for n in napit {
            guard osoitin != nil else { throw virhe("yhteys katkesi") }
            nappi(n)
            try await Task.sleep(nanoseconds: UInt64(viive * 1_000_000_000))
        }
    }

    // Kirjoittaa haun Netflixin ruudukolla sitä mukaa kuin kenttään kirjoitetaan: muutokset jonoon,
    // yksi työ purkaa jonon. OK (ENTER) lähtee vain, kun fokuksen paikka on tiedossa: ensimmäisellä
    // merkillä se luetaan kuvasta (ja fokus palautetaan nuolilla), sen jälkeen lasketaan painalluksista.
    // Tauon jälkeen kuva tarkistaa paikan; ristiriita → seuraava merkki ankkuroi uudelleen.
    private enum NetflixOp { case tyhjenna, poista, kirjain(Character) }
    private var netflixJono: [NetflixOp] = []
    private var netflixPaikka: NetflixRuudukko.Paikka?
    private var netflixTyo: Task<Void, Never>?
    private var netflixTarkistus: Task<Void, Never>?

    func netflixSyota(vanha: String, uusi: String) {
        let v = NetflixRuudukko.normalisoi(vanha), u = NetflixRuudukko.normalisoi(uusi)
        guard v != u else { return }
        if v.isEmpty { netflixJono.append(.tyhjenna) }
        let yhteinen = zip(v, u).prefix { $0 == $1 }.count
        netflixJono += Array(repeating: .poista, count: v.count - yhteinen)
        netflixJono += u.dropFirst(yhteinen).map { .kirjain($0) }
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
                var paikka: NetflixRuudukko.Paikka
                if let p = netflixPaikka {
                    paikka = p
                } else {
                    let (p, teksti) = try await netflixAnkkuroi()
                    paikka = p
                    // Uusi haku: TV:n kenttä tyhjennetään, jos siinä on tekstiä.
                    if case .tyhjenna = netflixJono.first, teksti { paikka = try await netflixTyhjenna(p) }
                }
                let jono = netflixJono
                netflixJono = []
                var napit: [String] = []
                for op in jono {
                    switch op {
                    case .tyhjenna:
                        continue
                    case .poista:
                        napit += NetflixRuudukko.siirry(paikka, NetflixRuudukko.askelpalautin) + ["ENTER"]
                        paikka = NetflixRuudukko.askelpalautin
                    case .kirjain(let ch):
                        let (n, loppu) = NetflixRuudukko.painallukset(String(ch), alku: paikka)
                        napit += n
                        paikka = loppu
                    }
                }
                netflixPaikka = nil // kesken painallusten paikka ei ole varma
                try await painele(napit, netflixViive)
                netflixPaikka = paikka
            }
            tila = "Netflix: haku TV:llä"
            netflixTarkistus = Task { await netflixTarkista() }
        } catch {
            netflixJono = []
            netflixPaikka = nil
            tila = "Netflix-haku: \(error.localizedDescription)"
        }
    }

    private func netflixTarkista() async {
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !Task.isCancelled, netflixTyo == nil, let odotettu = netflixPaikka,
              let kuva = try? await kuvakaappaus(), !Task.isCancelled, netflixTyo == nil else { return }
        if kuva.tila != .nappain(odotettu) {
            netflixPaikka = nil
            tila = "Netflix: fokus siirtyi — tarkista TV:n hakukenttä"
        }
    }

    // Fokus näppäimistölle: kuva kertoo paikan; muuten nuolet ja uusi kuva (enintään kolme kierrosta).
    private func netflixAnkkuroi() async throws -> (NetflixRuudukko.Paikka, Bool) {
        var kuva = try await kuvakaappaus()
        for kierros in 1...4 {
            if case .nappain(let p) = kuva.tila { return (p, kuva.hakuteksti) }
            guard kierros <= 3 else { break }
            switch kuva.tila {
            case .nav: try await painele(["DOWN"], 0.15)
            case .genre: try await painele(["UP"], 0.15)
            case .hakunakyma: try await painele(Array(repeating: "LEFT", count: 6), 0.15)
            default: throw virhe("avaa ensin Netflixin haku (suurennuslasi)")
            }
            try await Task.sleep(nanoseconds: 400_000_000)
            kuva = try await kuvakaappaus()
        }
        throw virhe("fokus ei löydy näppäimistöltä")
    }

    private func netflixTyhjenna(_ alku: NetflixRuudukko.Paikka) async throws -> NetflixRuudukko.Paikka {
        var paikka = alku
        for _ in 1...3 {
            try await painele(NetflixRuudukko.siirry(paikka, NetflixRuudukko.askelpalautin)
                + Array(repeating: "ENTER", count: 20), netflixViive)
            paikka = NetflixRuudukko.askelpalautin
            try await Task.sleep(nanoseconds: 500_000_000)
            let kuva = try await kuvakaappaus()
            guard kuva.tila == .nappain(paikka) else { throw virhe("fokus karkasi tyhjennyksessä") }
            if !kuva.hakuteksti { return paikka }
        }
        throw virhe("hakukenttä ei tyhjentynyt")
    }

    private func virhe(_ viesti: String) -> NSError {
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
        netflixPaikka = nil
        netflixJono = []
        let kesken = odottavat
        odottavat = [:]
        for jatko in kesken.values { jatko.resume(throwing: virhe("yhteys katkesi")) }
        lahettaa = false
        odotusDx = 0
        odotusDy = 0
    }

    // Liikkeet kasataan: kun edellinen lähetys on kesken, uudet siirtymät summautuvat seuraavaan.
    func liiku(_ dx: Double, _ dy: Double) {
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

    func klikkaa() { osoitinViesti("type:click\n\n") }
    func vieritä(_ dy: Int) { osoitinViesti("type:scroll\ndx:0\ndy:\(dy)\n\n") }
    func nappi(_ nimi: String) { osoitinViesti("type:button\nname:\(nimi)\n\n") }

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

struct KosketuslevyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tv = LGTV()
    @State private var edellinen: CGSize = .zero
    @State private var vierEdellinen: CGFloat = 0
    @State private var syote = syoteAlku
    @State private var netflixTeksti = ""
    @FocusState private var syoteFokus: Bool
    private let herkkyys = 1.6

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("TV-kosketuslevy").font(.title2.bold())
                Spacer()
                Button("Valmis") { dismiss() }.font(.headline)
            }
            if tv.nappaimisto {
                TextField("", text: Binding(get: { syote }, set: { uusi in
                    tv.syota(vanha: syote, uusi: uusi)
                    syote = uusi.isEmpty ? syoteAlku : uusi
                }))
                .focused($syoteFokus)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                .onSubmit { tv.enter(); syote = syoteAlku }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor))
            }
            if tv.netflix && !tv.nappaimisto {
                TextField("Hae Netflixistä", text: $netflixTeksti)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onChange(of: netflixTeksti) { vanha, uusi in tv.netflixSyota(vanha: vanha, uusi: uusi) }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).stroke(Color.red))
            }
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.secondary.opacity(0.18))
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
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondary.opacity(0.28))
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
            HStack(spacing: 10) {
                nappi("Takaisin", "BACK")
                nappi("Koti", "HOME")
                nappi("OK", "ENTER")
            }
            Text(tv.tila).font(.footnote).monospacedDigit().lineLimit(2)
        }
        .padding()
        .background(PiilotettuAanensaadin().frame(width: 1, height: 1))
        .onChange(of: tv.nappaimisto) { _, auki in
            syote = syoteAlku
            syoteFokus = auki
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { Task { await tv.yhdista() } } else if phase == .background { tv.katkaise() }
        }
        .onDisappear { tv.katkaise() }
    }

    func nappi(_ label: String, _ nimi: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            tv.nappi(nimi)
        } label: {
            Text(label).font(.headline).frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
    }
}

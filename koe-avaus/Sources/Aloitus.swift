import SwiftUI
import UIKit

// Aloitussivu (REMOTE-ALOITUS): valinta käynnistää laitteet ja sovelluksen. Laitteiden ei tarvitse olla
// päällä: vahvistin avataan ja lähde valitaan IR:llä palvelun kautta, TV avataan IR:llä, jos SSAP ei
// vastaa tai TV on valmiustilassa, ja sovellus käynnistetään SSAP:lla (system.launcher/launch).
// Sama ketju on alustariippumaton (VAATIMUS: REMOTE-ANDROID): HTTP-komennot ja TV:n websocket.
enum Palvelu: String, CaseIterable, Identifiable, Hashable {
    case liveTV, netflix, phono, areena, prime, youtube

    var id: String { rawValue }

    var nimi: String {
        switch self {
        case .liveTV: "Live TV"
        case .netflix: "Netflix"
        case .phono: "Phono"
        case .areena: "Yle Areena"
        case .prime: "Prime Video"
        case .youtube: "YouTube"
        }
    }

    var tvSovellus: Bool { self != .phono }
    var lahde: String { self == .phono ? "amp_phono" : "amp_network" }

    // webOS:n tunnetut sovellustunnukset; jos käynnistys epäonnistuu, tunnus haetaan TV:n listasta nimellä.
    var oletusId: String {
        switch self {
        case .liveTV: "com.webos.app.livetv"
        case .netflix: "netflix"
        case .phono: ""
        case .areena: "fi.yle.areena"
        case .prime: "amazon"
        case .youtube: "youtube.leanback.v4"
        }
    }

    var hakusanat: [String] {
        switch self {
        case .liveTV: ["live tv"]
        case .netflix: ["netflix"]
        case .phono: []
        case .areena: ["areena"]
        case .prime: ["prime video", "amazon"]
        case .youtube: ["youtube"]
        }
    }

    var kuvatiedosto: String? {
        switch self {
        case .netflix: "kuvake-netflix"
        case .areena: "kuvake-areena"
        case .prime: "kuvake-prime"
        case .youtube: "kuvake-youtube"
        case .liveTV, .phono: nil
        }
    }
}

// Vahvistin päälle ja lähde valituksi. Lähde lähetetään viiveellä, koska sammuksista heräävä Marantz
// ei ota valintaa heti vastaan; molemmat IR-koodit ovat erillisiä (päälle ≠ vaihto), joten toisto on harmiton.
func vahvistinLahteelle(_ lahde: String) {
    Task {
        _ = await lahetaKomento(label: "Vahvistin", nimi: "amp_paalle")
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        _ = await lahetaKomento(label: "Lähde", nimi: lahde)
    }
}

extension LGTV {
    func kaynnista(_ p: Palvelu) async {
        vahvistinLahteelle(p.lahde)
        guard p.tvSovellus else { return }
        profiiliValinta = false
        // Oletusprofiili valitaan, jos profiiliruutu ilmestyy tämän ajan sisällä (vahti: Kosketuslevy.swift).
        // Kylmäkäynnistys: TV:n avaus ≤ 40 s (mitattu 26–29 s) + sovelluksen käynnistys.
        let profiilit = p == .netflix || p == .youtube
        if profiilit { oletusProfiiliAsti = Date().addingTimeInterval(90) }
        kaynnistys = "Yhdistetään TV:hen…"
        defer { kaynnistys = nil }

        await yhdista(aikaraja: 2.5)
        var avattiin = false
        var paalla = false
        if valmis { paalla = await onPaalla() }
        if !paalla {
            kaynnistys = "Avataan TV…"
            _ = await lahetaKomento(label: "TV", nimi: "lg_paalle")
            avattiin = true
            let raja = Date().addingTimeInterval(40)
            while Date() < raja {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !valmis { await yhdista(aikaraja: 2) }
                if valmis, await onPaalla() { paalla = true; break }
            }
            guard paalla else { tila = "TV ei auennut — kokeile uudelleen"; return }
        }

        var ennen: String?
        if !avattiin { ennen = await etualaNyt() }
        kaynnistys = "Avataan \(p.nimi)…"
        do {
            try await avaaSovellus(p)
        } catch {
            tila = "\(p.nimi): \(error.localizedDescription)"
            return
        }
        tila = "\(p.nimi) auki"
        // Sovellus oli jo etualalla: profiiliruutu on joko jo näkyvissä tai ei tule, joten oletus vain heti.
        // YouTube näyttää "Kuka katsoo?" itse vain kylmäkäynnistyksessä (mitattu 6.10.2026).
        if profiilit && ennen == p.oletusId {
            oletusProfiiliAsti = min(oletusProfiiliAsti, Date().addingTimeInterval(3))
        }
    }

    // TV pois verkkokomennolla, IR varalla (6.10.2026: näytönsäästäjän aikana ensimmäinen IR-pois vain herätti
    // TV:n, toinen sammutti; HA: lg_pois 08.09.47 ja 08.09.54, TV off 08.09.58).
    func sammutaTV() async -> String {
        await yhdista(aikaraja: 1.5)
        if valmis, (try? await pyyda("ssap://system/turnOff", [:], aika: 2)) != nil { return "TV pois: OK" }
        return await lahetaKomento(label: "TV pois (IR)", nimi: "lg_pois")
    }

    // Active = päällä; Screen Off ja Screen Saver = päällä, kuva pois (kuva päälle); valmiustila = ei päällä.
    // Jos TV ei kerro tilaa, oletetaan päällä oleva (yhteys toimii).
    private func onPaalla() async -> Bool {
        guard let tila = await herataNaytto() else { return true }
        return tila == "Active" || tila == "Screen Off" || tila == "Screen Saver"
    }

    // Näytönsäästäjä ja "näyttö pois" nielevät ensimmäisen näppäimen herätykseen, joten ruudukon paikka
    // ajautuu (simulaattoritestit a5 ja a7 6.10.2026). turnOnScreen herättää molemmista ilman näppäintä.
    // Palauttaa tilan ennen herätystä, nil jos TV ei kerro sitä.
    @discardableResult
    func herataNaytto() async -> String? {
        guard let v = try? await pyyda("ssap://com.webos.service.tvpower/power/getPowerState", [:], aika: 2),
              let tila = (v["payload"] as? [String: Any])?["state"] as? String else { return nil }
        guard tila == "Screen Off" || tila == "Screen Saver" else { return tila }
        _ = try? await pyyda("ssap://com.webos.service.tvpower/power/turnOnScreen", [:], aika: 2)
        // Herätyksen jälkeen TV voi palata kelloon hetkeksi (a8 6.10.2026): odota Active, sitten tasaantuminen.
        let raja = Date().addingTimeInterval(3)
        while Date() < raja {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let v = try? await pyyda("ssap://com.webos.service.tvpower/power/getPowerState", [:], aika: 1),
               (v["payload"] as? [String: Any])?["state"] as? String == "Active" { break }
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        return tila
    }

    private func etualaNyt() async -> String? {
        let v = try? await pyyda("ssap://com.webos.applicationManager/getForegroundAppInfo", [:], aika: 2)
        return (v?["payload"] as? [String: Any])?["appId"] as? String ?? etuala
    }

    private func avaaSovellus(_ p: Palvelu) async throws {
        let avain = "tv_sovellukset"
        var muisti = UserDefaults.standard.dictionary(forKey: avain) as? [String: String] ?? [:]
        if (try? await kaynnistaId(muisti[p.rawValue] ?? p.oletusId)) != nil { return }
        let v = try await pyyda("ssap://com.webos.applicationManager/listLaunchPoints", [:], aika: 6)
        let lista = (v["payload"] as? [String: Any])?["launchPoints"] as? [[String: Any]] ?? []
        let osumat = lista.compactMap { lp -> (String, String)? in
            guard let id = lp["id"] as? String, let nimi = (lp["title"] as? String)?.lowercased(),
                  p.hakusanat.contains(where: { nimi.contains($0) }) else { return nil }
            return (id, nimi)
        }
        guard let id = osumat.min(by: { $0.1.count < $1.1.count })?.0 else {
            throw virhe("sovellusta ei löydy TV:ltä")
        }
        muisti[p.rawValue] = id
        UserDefaults.standard.set(muisti, forKey: avain)
        try await kaynnistaId(id)
    }

    private func kaynnistaId(_ id: String) async throws {
        let v = try await pyyda("ssap://system.launcher/launch", ["id": id], aika: 6)
        if (v["payload"] as? [String: Any])?["returnValue"] as? Bool == false { throw virhe("käynnistys hylätty") }
    }
}

// iOS-kuvakkeen muoto: palveluiden omat App Store -kuvakkeet; Live TV ja Phono piirretään samaan tyyliin.
struct PalveluKuvake: View {
    let palvelu: Palvelu
    var koko: CGFloat = 72

    var body: some View {
        let muoto = RoundedRectangle(cornerRadius: koko * 0.225, style: .continuous)
        Group {
            if let nimi = palvelu.kuvatiedosto, let kuva = UIImage(named: nimi) {
                Image(uiImage: kuva).resizable().scaledToFill().scaleEffect(1.04)
            } else if palvelu == .liveTV {
                LiveTVKuvake(koko: koko)
            } else {
                PhonoKuvake(koko: koko)
            }
        }
        .frame(width: koko, height: koko)
        .clipShape(muoto)
        .overlay(muoto.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1.5)
    }
}

private struct LiveTVKuvake: View {
    let koko: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.23, green: 0.33, blue: 0.86), Color(red: 0.09, green: 0.12, blue: 0.36)],
                           startPoint: .top, endPoint: .bottom)
            Image(systemName: "tv")
                .font(.system(size: koko * 0.5, weight: .medium))
                .foregroundStyle(.white)
                .offset(y: -koko * 0.04)
            Text("LIVE")
                .font(.system(size: koko * 0.12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, koko * 0.05)
                .background(Capsule().fill(Color.red))
                .offset(y: -koko * 0.07)
        }
    }
}

private struct PhonoKuvake: View {
    let koko: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.24), Color(red: 0.86, green: 0.27, blue: 0.18)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(white: 0.07)).frame(width: koko * 0.74)
            ForEach([0.66, 0.56, 0.46, 0.36], id: \.self) { r in
                Circle().stroke(Color.white.opacity(0.13), lineWidth: max(0.5, koko * 0.008)).frame(width: koko * r)
            }
            Circle()
                .trim(from: 0.05, to: 0.2)
                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: koko * 0.02, lineCap: .round))
                .frame(width: koko * 0.6)
            Circle().fill(Color(red: 1.0, green: 0.82, blue: 0.32)).frame(width: koko * 0.24)
            Circle().fill(Color(white: 0.07)).frame(width: koko * 0.04)
        }
    }
}

// Aloitussivu: 4×2-ruudukko ja, kun TV on päällä (yhteys valmis), Takaisin/OK ja kosketuslevy alakolmanneksella
// (käyttäjä 6.10.2026: Koti vie TV:n kotinäkymään, ja sitä pitää voida ohjata Kaukosta).
struct AloitusView: View {
    let avaa: (Palvelu) -> Void
    @Binding var laitteet: Bool
    @EnvironmentObject private var tv: LGTV
    private let sarakkeet = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4) // 4×2-ruudukko

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 14) {
                LazyVGrid(columns: sarakkeet, spacing: 28) {
                    ForEach(Palvelu.allCases) { p in
                        Button { avaa(p) } label: {
                            VStack(spacing: 6) {
                                PalveluKuvake(palvelu: p, koko: 64)
                                Text(p.nimi).font(.caption).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(p.nimi)
                    }
                }
                .padding(.top, 24)
                Spacer(minLength: 0)
                if tv.valmis {
                    HStack(spacing: 10) {
                        TVNappi(teksti: "Takaisin", kuva: "arrow.uturn.backward", nimi: "BACK")
                        TVNappi(teksti: "OK", kuva: "checkmark", nimi: "ENTER")
                    }
                    Kosketusalue(tv: tv).frame(height: geo.size.height / 3)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .toolbar { // ei otsikkoa: sovelluksen nimi ei näy näkymissä (käyttäjä 6.10.2026)
            ToolbarItem(placement: .topBarTrailing) {
                Button { laitteet = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Laitteet")
            }
        }
    }
}

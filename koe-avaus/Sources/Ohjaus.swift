import SwiftUI
import UIKit

// TV-sovelluksen ohjaus (REMOTE-ALOITUS): napit, hakukenttä suoraan kosketuslevyn yläpuolella ja
// alakolmanneksella kosketuslevy. Hakukentän fokus piilottaa kosketuslevyn puhelimen näppäimistön tieltä; Enter
// sulkee näppäimistön ja kosketuslevy palaa. Netflixin, Areenan ja YouTuben haku ohjaa niiden kirjainruudukkoa
// (NetflixHaku.swift, RuudukkoHaku.swift), muut sovellukset TV:n omaa tekstikenttää (IME), kun se on auki.
struct TVOhjausView: View {
    let palvelu: Palvelu? // nil = pelkkä kosketuslevy (Laitteet-paneelista)
    @EnvironmentObject private var tv: LGTV
    @Environment(\.dismiss) private var dismiss
    @State private var syote = syoteAlku
    @State private var ruudukkoTeksti = syoteAlku
    @FocusState private var hakuFokus: Bool

    private var netflixHaku: Bool { (palvelu == .netflix || tv.netflix) && !tv.nappaimisto }
    // Areenan tai YouTuben ruudukko: TV:n etualalla oleva sovellus ensin, muuten avattu palvelu.
    private var ruudukko: RuudukkoOhjain? {
        guard !tv.nappaimisto && !netflixHaku else { return nil }
        if tv.areena { return tv.areenaHaku }
        if tv.youtube { return tv.youtubeHaku }
        if palvelu == .areena { return tv.areenaHaku }
        if palvelu == .youtube { return tv.youtubeHaku }
        return nil
    }
    private var ruudukkoHaku: Bool { netflixHaku || ruudukko != nil }
    private var profiili: Bool { palvelu == .netflix && tv.profiiliValinta }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 14) {
                if profiili {
                    Spacer()
                    ProfiiliValinta(tv: tv)
                    Spacer()
                } else {
                    if let k = tv.kaynnistys {
                        HStack(spacing: 8) { ProgressView(); Text(k).font(.subheadline) }
                    }
                    Spacer(minLength: 0)
                    napit
                    if palvelu != .liveTV { hakukentta }
                    if !hakuFokus {
                        Kosketusalue(tv: tv).frame(height: geo.size.height / 3)
                    }
                }
                Text(tv.tila)
                    .font(.footnote).monospacedDigit().foregroundStyle(.secondary).lineLimit(2)
                    .accessibilityIdentifier("tila").accessibilityValue(tv.hakee ? "hakee" : "valmis")
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle(palvelu?.nimi ?? "Kosketuslevy")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: tv.nappaimisto) { _, auki in
            syote = syoteAlku
            if auki { hakuFokus = true }
        }
        .onChange(of: hakuFokus) { _, auki in
            if auki && netflixHaku { tv.netflixAvaaHaku() }
            if auki { ruudukko?.avaaHaku() }
        }
        .onAppear {
            Task { await tv.yhdista() }
            if palvelu == .netflix { tv.profiiliVahti(true) }
        }
        .onDisappear {
            tv.profiiliVahti(false)
            tv.profiiliValinta = false
        }
    }

    @ViewBuilder private var hakukentta: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            if ruudukkoHaku {
                // Näkymätön alkumerkki: askelpalautin tyhjässä kentässä poistaa merkin TV:n hakukentästä.
                TextField("", text: Binding(get: { ruudukkoTeksti }, set: { uusi in
                    let tyhja = netflixHaku ? NetflixRuudukko.normalisoi(ruudukkoTeksti).isEmpty
                                            : ruudukko?.tyhja(ruudukkoTeksti) ?? true
                    switch (netflixHaku, uusi.isEmpty && tyhja) {
                    case (true, true): tv.netflixPoista()
                    case (true, false): tv.netflixSyota(vanha: ruudukkoTeksti, uusi: uusi)
                    case (false, true): ruudukko?.poista()
                    case (false, false): ruudukko?.syota(vanha: ruudukkoTeksti, uusi: uusi)
                    }
                    ruudukkoTeksti = uusi.isEmpty ? syoteAlku : uusi
                }))
                .focused($hakuFokus)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    hakuFokus = false
                    if netflixHaku { tv.netflixTuloksiin() } else { ruudukko?.tuloksiin() }
                }
                .accessibilityIdentifier("hakukentta")
                .overlay(alignment: .leading) {
                    if ruudukkoTeksti == syoteAlku {
                        Text(netflixHaku ? "Hae Netflixistä" : ruudukko?.paikkamerkki ?? "")
                            .foregroundStyle(.secondary).allowsHitTesting(false)
                    }
                }
                if ruudukkoTeksti != syoteAlku || hakuFokus {
                    Button {
                        ruudukkoTeksti = syoteAlku
                        if netflixHaku { tv.netflixTyhjennaKentta() } else { ruudukko?.tyhjennaKentta() }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Tyhjennä TV:n hakukenttä")
                }
            } else {
                TextField("", text: Binding(get: { syote }, set: { uusi in
                    tv.syota(vanha: syote, uusi: uusi)
                    syote = uusi.isEmpty ? syoteAlku : uusi
                }))
                .focused($hakuFokus)
                .disabled(!tv.nappaimisto)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { tv.enter(); syote = syoteAlku; hakuFokus = false }
                .overlay(alignment: .leading) {
                    if syote == syoteAlku {
                        Text(tv.nappaimisto ? "Kirjoita TV:lle" : "Haku: valitse TV:n hakukenttä")
                            .foregroundStyle(.secondary).allowsHitTesting(false)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private var napit: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TVNappi(teksti: "Takaisin", kuva: "arrow.uturn.backward", nimi: "BACK")
                // TV:n aloitusruutu ja Kaukon aloitussivu (kosketuslevyineen) yhdessä: palvelun näkymä ei jää auki.
                TVNappi(teksti: "Koti", kuva: "house", nimi: "HOME") { dismiss() }
                TVNappi(teksti: "OK", kuva: "checkmark", nimi: "ENTER")
            }
            if palvelu == .liveTV {
                HStack(spacing: 10) {
                    TVNappi(teksti: "Kanava −", kuva: "chevron.down", nimi: "CHANNELDOWN")
                    TVNappi(teksti: "Kanava +", kuva: "chevron.up", nimi: "CHANNELUP")
                }
            }
        }
    }
}

// TV:n kaukosäätimen nappi osoitinyhteyden kautta (ohjausnäkymä ja aloitussivu).
struct TVNappi: View {
    let teksti: String
    let kuva: String
    let nimi: String
    var lisaksi: (() -> Void)? = nil
    @EnvironmentObject private var tv: LGTV

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            tv.nappi(nimi)
            lisaksi?()
        } label: {
            Label(teksti, systemImage: kuva)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(teksti)
    }
}

// Netflixin "Kuka katsoo?": profiilit TV:n kuvakaappauksesta pystylistana (oma kuva, TV:n fokus kehyksellä).
// Napautus valitsee profiilin (OK vasta kuvan vahvistamasta fokuksesta), pitkä painallus asettaa oletusprofiilin
// (tähti). Liukusäädin poistettu 6.10.2026 (käyttäjä: profiili valitaan napauttamalla puhelimen ruudulta).
struct ProfiiliValinta: View {
    @ObservedObject var tv: LGTV
    @State private var oletus = UserDefaults.standard.object(forKey: "netflix_oletusprofiili") as? Int
    private let kuvaKoko: CGFloat = 76

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                PalveluKuvake(palvelu: .netflix, koko: 44)
                Text("Kuka katsoo?").font(.title2.bold())
            }
            VStack(spacing: 12) {
                ForEach(Array(tv.profiiliKuvat.enumerated()), id: \.offset) { i, kuva in profiili(i, kuva) }
            }
            Text("Napauta profiilia · pitkä painallus: oletusprofiili").font(.footnote).foregroundStyle(.secondary)
            Button("Ohita") { tv.profiiliValinta = false }
                .font(.footnote)
        }
    }

    private func profiili(_ i: Int, _ kuva: UIImage) -> some View {
        let muoto = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Image(uiImage: kuva)
            .resizable().scaledToFill()
            .frame(width: kuvaKoko, height: kuvaKoko)
            .clipShape(muoto)
            .overlay(muoto.stroke(Color.accentColor, lineWidth: tv.profiilit?.fokus == i ? 3 : 0))
            .overlay(alignment: .topTrailing) {
                if oletus == i {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow).padding(3)
                }
            }
            .contentShape(muoto)
            .accessibilityElement()
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("profiili-\(i)")
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await tv.profiiliValitse(i) }
            }
            .onLongPressGesture {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if oletus == i {
                    oletus = nil
                    UserDefaults.standard.removeObject(forKey: "netflix_oletusprofiili")
                } else {
                    oletus = i
                    UserDefaults.standard.set(i, forKey: "netflix_oletusprofiili")
                }
            }
    }
}

struct PhonoView: View {
    @State private var status = "Vahvistin päälle, lähde Phono"

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            PalveluKuvake(palvelu: .phono, koko: 132)
            Text("Phono").font(.largeTitle.bold())
            // Äänenvoimakkuus on puhelimen omissa napeissa (AaniNapit), joten näkymässä vain mykistys.
            Text("Äänenvoimakkuus: puhelimen sivunapit").font(.subheadline).foregroundStyle(.secondary)
            nappi("Mykistys", "speaker.slash", "amp_mykistys")
            Spacer()
            Button(role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { status = await lahetaKomento(label: "Vahvistin pois", nimi: "amp_pois") }
            } label: {
                Label("Sammuta vahvistin", systemImage: "power").frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.bordered)
            Text(status).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Phono")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(AaniNapit.shared.$viesti.dropFirst()) { status = $0 }
    }

    private func nappi(_ teksti: String, _ kuva: String, _ nimi: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { status = await lahetaKomento(label: teksti, nimi: nimi) }
        } label: {
            Label(teksti, systemImage: kuva).font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.borderedProminent)
    }
}

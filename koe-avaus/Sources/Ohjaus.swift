import SwiftUI
import UIKit

// TV-sovelluksen ohjaus (REMOTE-ALOITUS): napit, hakukenttä suoraan kosketuslevyn yläpuolella ja
// alakolmanneksella kosketuslevy. Hakukentän fokus piilottaa kosketuslevyn puhelimen näppäimistön tieltä; Enter
// sulkee näppäimistön ja kosketuslevy palaa. Netflixin haku ohjaa sen kirjainruudukkoa
// (NetflixHaku.swift), muut sovellukset TV:n omaa tekstikenttää (IME), kun se on auki.
struct TVOhjausView: View {
    let palvelu: Palvelu? // nil = pelkkä kosketuslevy (Laitteet-paneelista)
    @EnvironmentObject private var tv: LGTV
    @Environment(\.dismiss) private var dismiss
    @State private var syote = syoteAlku
    @State private var netflixTeksti = syoteAlku
    @FocusState private var hakuFokus: Bool

    private var netflixHaku: Bool { (palvelu == .netflix || tv.netflix) && !tv.nappaimisto }
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
        }
        .onAppear { Task { await tv.yhdista() } }
        .onDisappear { tv.profiiliValinta = false }
    }

    @ViewBuilder private var hakukentta: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            if netflixHaku {
                // Näkymätön alkumerkki: askelpalautin tyhjässä kentässä poistaa merkin TV:n hakukentästä.
                TextField("", text: Binding(get: { netflixTeksti }, set: { uusi in
                    if uusi.isEmpty && NetflixRuudukko.normalisoi(netflixTeksti).isEmpty {
                        tv.netflixPoista()
                    } else {
                        tv.netflixSyota(vanha: netflixTeksti, uusi: uusi)
                    }
                    netflixTeksti = uusi.isEmpty ? syoteAlku : uusi
                }))
                .focused($hakuFokus)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { hakuFokus = false; tv.netflixTuloksiin() }
                .overlay(alignment: .leading) {
                    if netflixTeksti == syoteAlku {
                        Text("Hae Netflixistä").foregroundStyle(.secondary).allowsHitTesting(false)
                    }
                }
                if netflixTeksti != syoteAlku || hakuFokus {
                    Button {
                        netflixTeksti = syoteAlku
                        tv.netflixTyhjennaKentta()
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
                nappi("Takaisin", "arrow.uturn.backward", "BACK")
                // TV:n aloitusruutu ja Kaukon aloitussivu yhdessä: palvelun näkymä ei jää auki.
                nappi("Koti", "house", "HOME") { dismiss() }
                nappi("OK", "checkmark", "ENTER")
            }
            HStack(spacing: 10) {
                if palvelu == .liveTV {
                    nappi("Kanava −", "chevron.down", "CHANNELDOWN")
                    nappi("Kanava +", "chevron.up", "CHANNELUP")
                } else {
                    nappi(nil, "backward.fill", "REWIND")
                    nappi(nil, "play.fill", "PLAY")
                    nappi(nil, "pause.fill", "PAUSE")
                    nappi(nil, "forward.fill", "FASTFORWARD")
                }
            }
        }
    }

    private func nappi(_ teksti: String?, _ kuva: String, _ nimi: String, _ lisaksi: (() -> Void)? = nil) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            tv.nappi(nimi)
            lisaksi?()
        } label: {
            Group {
                if let teksti { Label(teksti, systemImage: kuva) } else { Image(systemName: kuva) }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(teksti ?? nimi)
    }
}

// Netflixin "Kuka katsoo?": liu'utus siirtää TV:n valintaa askel kerrallaan (vasen/oikea),
// sormen nosto valitsee (OK). Askel on suhteellinen, joten profiilien määrää ei tarvitse tietää.
struct ProfiiliValinta: View {
    @ObservedObject var tv: LGTV
    @State private var edellinen: CGFloat = 0
    @State private var kertyma: CGFloat = 0
    @State private var siirto: CGFloat = 0
    private let askel: CGFloat = 46
    private let nuppi: CGFloat = 64

    var body: some View {
        VStack(spacing: 18) {
            PalveluKuvake(palvelu: .netflix, koko: 64)
            Text("Kuka katsoo?").font(.title2.bold())
            Text(tv.netflix ? "Liu'uta profiilin kohdalle ja nosta sormi" : "Odotetaan Netflixiä…")
                .font(.subheadline).foregroundStyle(.secondary)
            GeometryReader { g in
                let raja = max(0, (g.size.width - nuppi) / 2 - 4)
                ZStack {
                    Capsule().fill(Color(.tertiarySystemFill))
                    HStack {
                        Image(systemName: "chevron.left")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 22)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: nuppi, height: nuppi)
                        .overlay(Image(systemName: "person.fill").font(.title2).foregroundStyle(.white))
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        .offset(x: siirto)
                }
                .contentShape(Capsule())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let d = v.translation.width - edellinen
                        edellinen = v.translation.width
                        siirto = max(-raja, min(raja, v.translation.width))
                        guard tv.netflix else { return }
                        kertyma += d
                        while kertyma >= askel { kertyma -= askel; askella(1) }
                        while kertyma <= -askel { kertyma += askel; askella(-1) }
                    }
                    .onEnded { _ in
                        edellinen = 0
                        kertyma = 0
                        withAnimation(.spring(duration: 0.3)) { siirto = 0 }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        tv.profiiliValitse()
                    })
            }
            .frame(height: nuppi + 8)
            Button("Ohita") { tv.profiiliValinta = false }
                .font(.footnote)
        }
    }

    private func askella(_ suunta: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        tv.profiiliSiirto(suunta)
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

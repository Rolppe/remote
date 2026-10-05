import SwiftUI
import UIKit
import Darwin
import AVFoundation
import MediaPlayer

let baseURL = "http://192.0.2.10:8090"

func processStartMs() -> Double {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return 0 }
    let tv = info.kp_proc.p_un.__p_starttime
    return Double(tv.tv_sec) * 1000 + Double(tv.tv_usec) / 1000
}

// Varoitus, kun oman embedded.mobileprovisionin ExpirationDate on alle 3 vrk päässä.
func allekirjoitusVaroitus() -> String? {
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
          let data = try? Data(contentsOf: url),
          let raw = String(data: data, encoding: .isoLatin1),
          let a = raw.range(of: "<?xml"), let b = raw.range(of: "</plist>"),
          let xml = String(raw[a.lowerBound..<b.upperBound]).data(using: .isoLatin1),
          let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any],
          let exp = plist["ExpirationDate"] as? Date,
          exp.timeIntervalSinceNow < 3 * 86400 else { return nil }
    let f = DateFormatter()
    f.dateFormat = "dd.MM. HH.mm"
    return "Allekirjoitus vanhenee \(f.string(from: exp)) — avaa Macin näyttö"
}

func lahetaKomento(label: String, nimi: String) async -> String {
    let now = Int(Date().timeIntervalSince1970 * 1000)
    guard let url = URL(string: baseURL + "/k/" + nimi + "?t=\(now)") else { return "\(label): virheellinen osoite" }
    var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
    req.httpMethod = "POST"
    let t0 = Date()
    do {
        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        let rtt = Int(Date().timeIntervalSince(t0) * 1000)
        return code == 200 ? "\(label): OK \(rtt) ms" : "\(label): HTTP \(code)"
    } catch {
        return "\(label): \(error.localizedDescription)"
    }
}

// Puhelimen äänenvoimakkuusnapit säätävät vahvistinta, kun Kauko on auki (REMOTE-TV-SYOTTO).
// Napin painallus näkyy outputVolumen muutoksena (KVO); muutoksen suunta lähetetään aani_ylos/aani_alas,
// ja taso palautetaan heti lähtöarvoon piilotetun MPVolumeView'n liukusäätimellä, jotta napit toimivat
// myös ääripäissä. Näkymässä oleva MPVolumeView estää järjestelmän äänenvoimakkuusilmoituksen.
@MainActor
final class AaniNapit: ObservableObject {
    static let shared = AaniNapit()
    @Published var viesti = ""

    private var havainto: NSKeyValueObservation?
    private var taso: Float = 0.5
    private let nakymat = NSHashTable<MPVolumeView>.weakObjects()

    func liita(_ v: MPVolumeView) { nakymat.add(v) }

    func kaynnista() {
        guard havainto == nil else { return }
        let istunto = AVAudioSession.sharedInstance()
        try? istunto.setCategory(.ambient, options: [.mixWithOthers])
        try? istunto.setActive(true)
        taso = istunto.outputVolume
        if taso < 0.05 || taso > 0.95 {
            taso = 0.5
            aseta(taso)
        }
        havainto = istunto.observe(\.outputVolume, options: [.new]) { [weak self] _, muutos in
            guard let uusi = muutos.newValue else { return }
            Task { @MainActor in self?.muuttui(uusi) }
        }
    }

    func pysayta() {
        havainto?.invalidate()
        havainto = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func muuttui(_ uusi: Float) {
        guard abs(uusi - taso) > 0.01 else { return } // oma palautus lähtötasolle
        let ylos = uusi > taso
        aseta(taso)
        Task {
            viesti = await lahetaKomento(label: ylos ? "Ääni +" : "Ääni −", nimi: ylos ? "aani_ylos" : "aani_alas")
        }
    }

    private func aseta(_ arvo: Float) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let kaikki = self.nakymat.allObjects
            guard let v = kaikki.first(where: { $0.window != nil }) ?? kaikki.first,
                  let liuku = v.subviews.compactMap({ $0 as? UISlider }).first else { return }
            liuku.setValue(arvo, animated: false)
        }
    }
}

struct PiilotettuAanensaadin: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        v.alpha = 0.01 // näkyvissä oleva (ei hidden) säädin piilottaa järjestelmän ilmoituksen
        AaniNapit.shared.liita(v)
        return v
    }

    func updateUIView(_ v: MPVolumeView, context: Context) {}
}

@main
struct RemoteKoeApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = "–"
    @State private var firstActive = true
    @State private var kosketuslevy = false

    var body: some View {
        VStack(spacing: 12) {
            Text("Kauko").font(.largeTitle.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section("Vahvistin")
                    big("Päälle", "amp_paalle")
                    big("Pois", "amp_pois")
                    big("Mykistys", "amp_mykistys")
                    section("Lähde")
                    big("Optical", "amp_optical")
                    big("Phono", "amp_phono")
                    section("Ääni")
                    HStack(spacing: 10) {
                        big("−", "aani_alas")
                        big("+", "aani_ylos")
                    }
                    section("TV")
                    big("Päälle", "lg_paalle")
                    big("Pois", "lg_pois")
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        kosketuslevy = true
                    } label: {
                        Text("Kosketuslevy")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text(status)
                .font(.footnote)
                .monospacedDigit()
                .lineLimit(2)
        }
        .padding(.horizontal)
        .background(PiilotettuAanensaadin().frame(width: 1, height: 1))
        .fullScreenCover(isPresented: $kosketuslevy) { KosketuslevyView() }
        .onReceive(AaniNapit.shared.$viesti.dropFirst()) { status = $0 }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .background { AaniNapit.shared.pysayta() }
            guard phase == .active else { return }
            AaniNapit.shared.kaynnista()
            var launch = 0
            if firstActive {
                firstActive = false
                launch = Int(Date().timeIntervalSince1970 * 1000 - processStartMs())
                if let varoitus = allekirjoitusVaroitus() { status = varoitus }
            }
            Task { await warmUp(launch: launch) }
        }
    }

    func section(_ title: String) -> some View {
        Text(title).font(.headline).padding(.top, 4)
    }

    func big(_ label: String, _ nimi: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { status = await lahetaKomento(label: label, nimi: nimi) }
        } label: {
            Text(label)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
    }

    func warmUp(launch: Int) async {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let painallus = UserDefaults.standard.integer(forKey: "painallus_ms")
        UserDefaults.standard.removeObject(forKey: "painallus_ms")
        let lisa = painallus > 0 && now - painallus < 30000 ? "&painallus=\(painallus)" : ""
        guard let url = URL(string: baseURL + "/ping?vaihe=active&launch_ms=\(launch)&t=\(now)" + lisa) else { return }
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        _ = try? await URLSession.shared.data(for: req)
    }
}

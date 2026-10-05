import SwiftUI
import UIKit
import Darwin

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
        .fullScreenCover(isPresented: $kosketuslevy) { KosketuslevyView() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
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
            Task { await send(label: label, nimi: nimi) }
        } label: {
            Text(label)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
    }

    func send(label: String, nimi: String) async {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        guard let url = URL(string: baseURL + "/k/" + nimi + "?t=\(now)") else { return }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        req.httpMethod = "POST"
        let t0 = Date()
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let rtt = Int(Date().timeIntervalSince(t0) * 1000)
            status = code == 200 ? "\(label): OK \(rtt) ms" : "\(label): HTTP \(code)"
        } catch {
            status = "\(label): \(error.localizedDescription)"
        }
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

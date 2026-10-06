import AppIntents
import Foundation

struct OpenKaukoIntent: AppIntent {
    static var title: LocalizedStringResource = "Avaa Controller"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        let t = Int(Date().timeIntervalSince1970 * 1000)
        UserDefaults.standard.set(t, forKey: "painallus_ms")
        let proc = Bundle.main.bundleIdentifier ?? "-"
        Task {
            guard let url = URL(string: "http://192.0.2.10:8090/ping?vaihe=painallus&t=\(t)&proc=\(proc)") else { return }
            let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
            _ = try? await URLSession.shared.data(for: req)
        }
        return .result()
    }
}

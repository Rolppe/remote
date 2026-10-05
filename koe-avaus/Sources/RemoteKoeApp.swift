import SwiftUI
import Darwin

func processStartMs() -> Double {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return 0 }
    let tv = info.kp_proc.p_un.__p_starttime
    return Double(tv.tv_sec) * 1000 + Double(tv.tv_usec) / 1000
}

@main
struct RemoteKoeApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var launchMs: Int?
    @State private var result = "–"
    @State private var rttMs: Int?
    @State private var started = false

    var body: some View {
        VStack(spacing: 24) {
            Text(launchMs.map { "\($0) ms" } ?? "…")
                .font(.system(size: 64, weight: .bold))
                .monospacedDigit()
            Text(result)
            Text(rttMs.map { "RTT \($0) ms" } ?? "")
            Button("Ping uudelleen") { Task { await ping(launch: 0) } }
        }
        .padding()
        .onAppear {
            guard !started else { return }
            started = true
            let ms = Int(Date().timeIntervalSince1970 * 1000 - processStartMs())
            launchMs = ms
            Task { await ping(launch: ms) }
        }
    }

    func ping(launch: Int) async {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        guard let url = URL(string: "http://192.0.2.10:8090/ping?launch_ms=\(launch)&t=\(now)") else { return }
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        let t0 = Date()
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            result = "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)"
        } catch {
            result = error.localizedDescription
        }
        rttMs = Int(Date().timeIntervalSince(t0) * 1000)
    }
}

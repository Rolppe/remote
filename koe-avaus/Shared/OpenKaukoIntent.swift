import AppIntents

struct OpenKaukoIntent: AppIntent {
    static var title: LocalizedStringResource = "Avaa Kauko"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

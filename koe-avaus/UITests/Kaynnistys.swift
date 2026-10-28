import XCTest

// UI-testit ajetaan oikeaa palvelua ja TV:tä vasten. Osoitteet annetaan ympäristömuuttujina
// (xcodebuild välittää TEST_RUNNER_-alkuiset testille):
//   TEST_RUNNER_KAUKO_PALVELU=<osoite> TEST_RUNNER_KAUKO_TV=<osoite> xcodebuild ... test
extension XCUIApplication {
    func kaynnista() {
        let env = ProcessInfo.processInfo.environment
        if let p = env["KAUKO_PALVELU"], !p.isEmpty { launchArguments += ["-kauko_palvelu", p] }
        if let t = env["KAUKO_TV"], !t.isEmpty { launchArguments += ["-kauko_tv", t] }
        launch()
    }
}

import XCTest

// Simulaattoritesti oikeaa TV:tä vastaan (REMOTE-NETFLIX-HAKU-TEKSTI): käyttäjän 7.10.2026 haku "space force"
// tuotti TV:n hakuun "yugeevgikbluxik". Kirjoitus merkki kerrallaan kuten puhelimella, sitten poisto ja jatko.
// TV:n kuva todennetaan Macilta (simajo.sh ottaa kuvan 1,5 s välein); Netflix etualalla selausnäkymässä.
final class NetflixHakuTesti: XCTestCase {
    func testNetflixHaku() throws {
        continueAfterFailure = false // 7.10.2026 ajo nh1 jatkoi karanneella fokuksella ja avasi Cobra Kain
        let app = XCUIApplication()
        app.launch()
        let netflix = app.buttons["Netflix"]
        XCTAssertTrue(netflix.waitForExistence(timeout: 10), "aloitussivun Netflix-nappia ei löydy")
        netflix.tap()
        sleep(8)

        let kentta = app.textFields["hakukentta"]
        XCTAssertTrue(kentta.waitForExistence(timeout: 10), "hakukenttää ei löydy")
        kentta.tap()
        for ch in "space force" { kentta.typeText(String(ch)) }
        odota(app, "Netflix: haku TV:llä", 120)
        sleep(2) // tarkistus 0,8 s tauon jälkeen: fokus kuvassa samassa paikassa
        XCTAssertEqual(app.staticTexts["tila"].label, "Netflix: haku TV:llä", "fokus karkasi")
        kuva(app, "kirjoitettu")

        kentta.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
        for ch in "force" { kentta.typeText(String(ch)) }
        odota(app, "Netflix: haku TV:llä", 90)
        sleep(2)
        XCTAssertEqual(app.staticTexts["tila"].label, "Netflix: haku TV:llä", "fokus karkasi korjauksessa")
        kuva(app, "korjattu")
    }

    private func odota(_ app: XCUIApplication, _ teksti: String, _ aika: TimeInterval) {
        let tila = app.staticTexts["tila"]
        let loppu = Date().addingTimeInterval(aika)
        sleep(1)
        while Date() < loppu {
            if tila.exists && tila.label == teksti && (tila.value as? String) == "valmis" { return }
            if tila.exists && tila.label.hasPrefix("Netflix-haku:") { XCTFail(tila.label); return }
            usleep(300_000)
        }
        XCTFail("ei tilaa \"\(teksti)\" \(Int(aika)) s:ssa; tila: \(tila.exists ? tila.label : "-")")
    }

    private func kuva(_ app: XCUIApplication, _ nimi: String) {
        let liite = XCTAttachment(screenshot: app.screenshot())
        liite.name = nimi
        liite.lifetime = .keepAlways
        add(liite)
    }
}

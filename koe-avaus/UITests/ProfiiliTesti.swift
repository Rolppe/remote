import XCTest

// Simulaattoritesti oikeaa TV:tä vastaan (REMOTE-ALOITUS vaihe 6): Netflixin kylmäkäynnistys,
// profiiliruutu ja profiilin napautus. Napautettava indeksi: ympäristömuuttuja PROFIILI (oletus 1).
final class ProfiiliTesti: XCTestCase {
    func testNetflixProfiilinNapautus() throws {
        let app = XCUIApplication()
        app.launch()
        let netflix = app.buttons["Netflix"]
        XCTAssertTrue(netflix.waitForExistence(timeout: 10), "aloitussivun Netflix-nappia ei löydy")
        netflix.tap()

        let otsikko = app.staticTexts["Kuka katsoo?"]
        XCTAssertTrue(otsikko.waitForExistence(timeout: 120), "profiiliruutu ei ilmestynyt")
        kuva(app, "profiiliruutu")

        let i = Int(ProcessInfo.processInfo.environment["PROFIILI"] ?? "") ?? 1
        let profiili = app.images["profiili-\(i)"]
        XCTAssertTrue(profiili.waitForExistence(timeout: 10), "profiilia \(i) ei löydy")
        profiili.tap()

        let poistui = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: otsikko)
        XCTAssertEqual(XCTWaiter().wait(for: [poistui], timeout: 20), .completed, "profiiliruutu ei poistunut valinnan jälkeen")
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground, "sovellus ei ole enää etualalla")
        kuva(app, "valinnan-jalkeen")
    }

    private func kuva(_ app: XCUIApplication, _ nimi: String) {
        let liite = XCTAttachment(screenshot: app.screenshot())
        liite.name = nimi
        liite.lifetime = .keepAlways
        add(liite)
    }
}

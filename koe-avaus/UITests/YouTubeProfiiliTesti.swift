import XCTest

// Simulaattoritesti oikeaa TV:tä vastaan (REMOTE-ALOITUS-YOUTUBE-PROFIILI): YouTuben "Kuka katsoo?" puhelimelle
// (kylmäkäynnistyksessä itsestään, muuten Profiili-napista sivupalkin kautta) ja profiilin napautus. Napautettava
// indeksi: ympäristömuuttuja PROFIILI (oletus 0, nykyinen tili; muut profiilit ovat TV:llä uloskirjautuneita).
final class YouTubeProfiiliTesti: XCTestCase {
    func testYouTubeProfiilinNapautus() throws {
        let app = XCUIApplication()
        app.kaynnista()
        let youtube = app.buttons["YouTube"]
        XCTAssertTrue(youtube.waitForExistence(timeout: 10), "aloitussivun YouTube-nappia ei löydy")
        youtube.tap()

        let otsikko = app.staticTexts["Kuka katsoo?"]
        let tila = app.staticTexts["tila"]
        let auki = NSPredicate(format: "label == 'YouTube auki'")
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: auki, object: tila)], timeout: 120)
        if !otsikko.waitForExistence(timeout: 8) {
            let nappi = app.buttons["Profiili"]
            XCTAssertTrue(nappi.waitForExistence(timeout: 5), "Profiili-nappia ei löydy")
            nappi.tap()
        }
        XCTAssertTrue(otsikko.waitForExistence(timeout: 60), "profiiliruutu ei ilmestynyt (tila: \(tila.label))")
        kuva(app, "profiiliruutu")

        let i = Int(ProcessInfo.processInfo.environment["PROFIILI"] ?? "") ?? 0
        let profiili = app.images["profiili-\(i)"]
        XCTAssertTrue(profiili.waitForExistence(timeout: 10), "profiilia \(i) ei löydy")
        profiili.tap()

        let poistui = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: otsikko)
        XCTAssertEqual(XCTWaiter().wait(for: [poistui], timeout: 30), .completed, "profiiliruutu ei poistunut (tila: \(tila.label))")
        XCTAssertEqual(tila.label, "YouTube: profiili valittu")
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

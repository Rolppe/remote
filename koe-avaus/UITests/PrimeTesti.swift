import XCTest

// Simulaattoritesti oikeaa TV:tä vastaan (REMOTE-ALOITUS-PRIME): aloitussivun Prime Video -nappi käynnistää
// vahvistimen, TV:n ja Prime Videon. TV:n etualan sovellus ja kuva tarkistetaan Macilta ajon rinnalla (ytaja.sh).
final class PrimeTesti: XCTestCase {
    func testPrimeKaynnistys() throws {
        let app = XCUIApplication()
        app.kaynnista()
        let prime = app.buttons["Prime Video"]
        XCTAssertTrue(prime.waitForExistence(timeout: 10), "aloitussivun Prime Video -nappia ei löydy")
        prime.tap()

        let tila = app.staticTexts["tila"]
        XCTAssertTrue(tila.waitForExistence(timeout: 20), "tila-tekstiä ei löydy")
        let auki = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Prime Video auki'"), object: tila)
        XCTAssertEqual(XCTWaiter().wait(for: [auki], timeout: 120), .completed, "Prime Video ei auennut (tila: \(tila.label))")
        kuva(app, "prime-auki")
        sleep(10)
        XCTAssertEqual(app.state, .runningForeground, "sovellus ei ole enää etualalla")
        XCTAssertEqual(tila.label, "Prime Video auki")
        kuva(app, "prime-10s")
    }

    private func kuva(_ app: XCUIApplication, _ nimi: String) {
        let liite = XCTAttachment(screenshot: app.screenshot())
        liite.name = nimi
        liite.lifetime = .keepAlways
        add(liite)
    }
}

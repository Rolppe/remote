import XCTest

// Simulaattoritesti oikeaa TV:tä vastaan (REMOTE-YOUTUBE-NUMEROT): YouTuben haussa numerot &123-sivulta ja paluu
// kirjaimiin. Laitetestissä 6.10.2026 numerot ja merkit jäivät pois. TV:n kuva todennetaan Macilta (k.py kuva).
final class YouTubeNumeroTesti: XCTestCase {
    func testYouTubeNumerot() throws {
        let app = XCUIApplication()
        app.kaynnista()
        let youtube = app.buttons["YouTube"]
        XCTAssertTrue(youtube.waitForExistence(timeout: 10), "aloitussivun YouTube-nappia ei löydy")
        youtube.tap()
        odota(app, "YouTube auki", 120)
        sleep(3)

        let kentta = app.textFields["hakukentta"]
        XCTAssertTrue(kentta.waitForExistence(timeout: 10), "hakukenttää ei löydy")
        kentta.tap()
        kentta.typeText("abba 1974")
        odota(app, "YouTube: haku TV:llä", 120)
        sleep(2)
        XCTAssertEqual(app.staticTexts["tila"].label, "YouTube: haku TV:llä", "fokus karkasi")
        kuva(app, "numerot")

        // ⌫ &123-sivulla ja kirjain sen jälkeen: sivu vaihtuu takaisin kirjaimiin.
        kentta.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "5a")
        odota(app, "YouTube: haku TV:llä", 90)
        sleep(2)
        XCTAssertEqual(app.staticTexts["tila"].label, "YouTube: haku TV:llä", "fokus karkasi")
        kuva(app, "kirjain numeron jälkeen")

        let tyhjenna = app.buttons["Tyhjennä TV:n hakukenttä"]
        XCTAssertTrue(tyhjenna.waitForExistence(timeout: 5), "tyhjennysnappia ei löydy")
        tyhjenna.tap()
        odota(app, "YouTube: haku TV:llä", 60)
        kuva(app, "tyhjennetty")
    }

    private func odota(_ app: XCUIApplication, _ teksti: String, _ aika: TimeInterval) {
        // Tila-teksti kertoo arvollaan, onko haun työ käynnissä (Ohjaus.swift): odotetaan valmista työtä.
        let tila = app.staticTexts["tila"]
        let loppu = Date().addingTimeInterval(aika)
        sleep(1)
        while Date() < loppu {
            if tila.exists && tila.label == teksti && (tila.value as? String) == "valmis" { return }
            if tila.exists && tila.label.hasPrefix("YouTube-haku:") { XCTFail(tila.label); return }
            usleep(300_000)
        }
        XCTFail("ei tilaa \"\(teksti)\" \(Int(aika)) s:ssa")
    }

    private func kuva(_ app: XCUIApplication, _ nimi: String) {
        let liite = XCTAttachment(screenshot: app.screenshot())
        liite.name = nimi
        liite.lifetime = .keepAlways
        add(liite)
    }
}

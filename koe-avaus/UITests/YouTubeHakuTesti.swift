import XCTest

// Simulaattoritesti oikeaa TV:tä vastaan (REMOTE-ALOITUS-HAKU-YOUTUBE): YouTuben haku ruudukko-ohjauksella.
// Kirjoitus, poisto ja jatko, Enter tuloksiin ja tyhjennys. TV:n kuva todennetaan Macilta (k.py kuva).
final class YouTubeHakuTesti: XCTestCase {
    func testYouTubeHaku() throws {
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
        kentta.typeText("jazz cafe")
        odota(app, "YouTube: haku TV:llä", 90)
        kentta.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        kentta.typeText("afe")
        odota(app, "YouTube: haku TV:llä", 60)
        sleep(2) // tarkistus 0,8 s tauon jälkeen: fokus kuvassa samassa paikassa
        XCTAssertEqual(app.staticTexts["tila"].label, "YouTube: haku TV:llä", "fokus karkasi")
        kuva(app, "kirjoitettu")

        kentta.typeText("\n")
        odota(app, "YouTube: valitse tulos kosketuslevyllä", 30)
        sleep(4)

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

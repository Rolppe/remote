import XCTest

// Simulaattoritesti oikeaa TV:tä vastaan (REMOTE-AREENA-KASIN): Areenan haku ihmisen tahdissa, merkki kerrallaan
// ~0,35 s välein, kun ruudukon ohjaus on vielä kesken. Laitetestissä 6.10.2026 kirjaimia puuttui tai meni väärin,
// vaikka AreenaHakuTesti (koko teksti kerralla) oli vihreä. TV:n kuva todennetaan Macilta (k.py kuva).
final class AreenaKasinTesti: XCTestCase {
    func testAreenaKasin() throws {
        let app = XCUIApplication()
        app.kaynnista()
        let areena = app.buttons["Yle Areena"]
        XCTAssertTrue(areena.waitForExistence(timeout: 10), "aloitussivun Areena-nappia ei löydy")
        areena.tap()
        odota(app, "Yle Areena auki", 120)
        sleep(3)

        let kentta = app.textFields["hakukentta"]
        XCTAssertTrue(kentta.waitForExistence(timeout: 10), "hakukenttää ei löydy")
        kentta.tap()
        for ch in "muumilaakson tarinoita" {
            kentta.typeText(String(ch))
            usleep(350_000)
        }
        odota(app, "Areena: haku TV:llä", 120)
        sleep(2)
        XCTAssertEqual(app.staticTexts["tila"].label, "Areena: haku TV:llä", "fokus karkasi")
        kuva(app, "kirjoitettu")
        sleep(3) // TV:n kuva Macille ennen tyhjennystä

        let tyhjenna = app.buttons["Tyhjennä TV:n hakukenttä"]
        XCTAssertTrue(tyhjenna.waitForExistence(timeout: 5), "tyhjennysnappia ei löydy")
        tyhjenna.tap()
        odota(app, "Areena: haku TV:llä", 60)
    }

    private func odota(_ app: XCUIApplication, _ teksti: String, _ aika: TimeInterval) {
        // Tila-teksti kertoo arvollaan, onko haun työ käynnissä (Ohjaus.swift): odotetaan valmista työtä.
        let tila = app.staticTexts["tila"]
        let loppu = Date().addingTimeInterval(aika)
        sleep(1)
        while Date() < loppu {
            if tila.exists && tila.label == teksti && (tila.value as? String) == "valmis" { return }
            if tila.exists && tila.label.hasPrefix("Areena-haku:") { XCTFail(tila.label); return }
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

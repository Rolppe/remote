# Kauko

iPhone-kaukosäädin LG webOS -televisiolle ja Home Assistantin kautta ohjattavalle vahvistimelle.

- `koe-avaus/` — iOS-äppi (SwiftUI, iOS 18) ja Ohjauskeskuksen painike. Ohjaa TV:tä suoraan webOS:n
  WebSocket-rajapinnalla (portti 3001) ja vahvistinta kauko-palvelun kautta.
- `palvelu/` — kauko-palvelu (Python 3, vain standardikirjasto): muuttaa äpin komennot Home Assistantin
  palvelukutsuiksi.

## Äpin build

Tarvitset Xcoden ja [XcodeGenin](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

1. Kopioi `koe-avaus/Config/Local.xcconfig.example` tiedostoksi `koe-avaus/Config/Local.xcconfig` ja aseta
   oma Apple-tiimitunnuksesi (`DEVELOPMENT_TEAM`) ja bundle-etuliite (`BUNDLE_ID_PREFIX`, esim. `com.nimesi`).
   Tiedosto on gitignoroitu.
2. Generoi projekti ja buildaa:

       cd koe-avaus
       xcodegen generate
       open RemoteKoe.xcodeproj

   Valitse kohteeksi oma iPhone ja aja (⌘R). Komentoriviltä:
   `xcodebuild -project RemoteKoe.xcodeproj -scheme RemoteKoe -destination 'generic/platform=iOS' build`.

3. Ensimmäisellä käynnistyksellä äppi avaa asetukset: anna kauko-palvelun osoite (esim.
   `palvelin.local:8090`; portti 8090, jos sitä ei anneta) ja TV:n IP-osoite tai nimi. Osoitteet tallentuvat
   laitteelle, ja niitä voi muuttaa myöhemmin rataskuvakkeesta.

## TV:n pariutus

Äppi käyttää LG:n julkista testiallekirjoitusta (`koe-avaus/Sources/Kosketuslevy.swift`), samaa kuin
esimerkiksi bscpylgtv. Se ei ole salaisuus. Ensimmäisellä yhteydellä TV kysyy ruudulla, sallitaanko
"Kauko"-laite. Hyväksy kaukosäätimellä. TV:n antama avain tallentuu äppiin, eikä kysymystä näytetä uudelleen.
TV:n ja puhelimen on oltava samassa verkossa.

## Kauko-palvelu

    python3 palvelu/kauko-palvelu.py --check   # preflight: osoite, token, HA ja portti
    python3 palvelu/kauko-palvelu.py           # palvelu porttiin 8090

Asetukset:

| Muuttuja | Oletus | Tarkoitus |
|---|---|---|
| `HA_URL` | — | Home Assistantin osoite, esim. `http://homeassistant.local:8123` |
| `HA_URL_FILE` | `~/.config/ha/url` | osoite tiedostosta, jos `HA_URL` puuttuu |
| `HA_TOKEN_FILE` | `~/.config/ha/token` | HA:n pitkäikäinen käyttöoikeustunnus |
| `KAUKO_PORT` | `8090` | kuunteluportti |
| `KAUKO_LOCK` | `~/.local/state/kauko-palvelu.lock` | lukko: vain yksi instanssi kerrallaan |

Lukon ansiosta palvelun voi käynnistää cronista minuutin välein; ylimääräinen käynnistys päättyy heti.

Home Assistantissa palvelu odottaa näitä entiteettejä:

- `button.ir_kaukosaadin_<komento>` komennoille `amp_paalle`, `amp_pois`, `amp_optical`, `amp_phono`,
  `amp_mykistys`, `lg_paalle` ja `lg_pois` (esim. IR-lähettimen painikkeet)
- `script.marantz_lahde_network` (komento `amp_network`)
- `input_number.marantz_nupin_kohde` ja `script.marantz_nuppiajuri` (äänenvoimakkuus, enintään 45)

Rajapinta: `GET /ping`, `GET /komennot`, `POST /k/<komento>`.

Testit: `cd palvelu && python3 -m unittest test_kauko_palvelu`.

## UI-testit

UI-testit ajetaan oikeaa palvelua ja TV:tä vasten. Osoitteet annetaan ympäristömuuttujina:

    TEST_RUNNER_KAUKO_PALVELU=<osoite> TEST_RUNNER_KAUKO_TV=<osoite> \
      xcodebuild -project RemoteKoe.xcodeproj -scheme RemoteKoe -destination '<laite>' test

# Development notes

How Kauko was developed, what record of that work exists in this repository, and a glossary of the Finnish terms
used in code and file names.

## How the work was done

The author, Mikko Paaso, defined the requirements, designed the architecture (two processes, direct SSAP, screenshot
verification) and decided what to keep. Claude Code agents wrote the code from written task briefs. A task was
accepted only when it passed a gate: the service tests, a build, or a run in the iOS simulator or on the phone against
the real TV. Failures became new measurements and new fixes, and the findings were written into the code.

Because the system under test is a physical TV and a physical amplifier, many gates were runs on hardware. The
UI tests in `koe-avaus/UITests` are the repeatable form of those runs. Several of them say in their header comment which
bug or device test (with a date) made them necessary. For example `AreenaKasinTesti` exists because typing at human
pace lost letters on the phone even though `AreenaHakuTesti` (the whole text at once) was green.

## What this repository contains of the process

This repository was extracted from the author's private monorepo (the first commit is 2026-10-05; the last two,
on 2026-10-28, prepare it for publishing: addresses moved to a settings screen, team id moved to a local
`xcconfig`). The briefs and the working registers stayed in the monorepo, so they are **not** in this repository. What
is here:

| Evidence | Where | What it shows |
|---|---|---|
| Commit history | `git log` | 34 commits, 2026-10-05 to 2026-10-28; 31 on 5-7 October |
| `Co-Authored-By: Claude` trailers | every commit | which commits had agent authorship |
| Task identifiers | commit subjects, code comments | 20 distinct `REMOTE-*` ids, such as `REMOTE-TRACKPAD`, `REMOTE-NETFLIX-HAKU`, `REMOTE-VAAKA` |
| Measurement notes | code comments | dated measurements and the failed attempt behind a constant (`RuudukkoHaku.swift`, `NetflixHaku.swift`, `AreenaRuudukko.swift`, `ToistoOSD.swift`) |
| Requirement tags | code comments | `VAATIMUS: REMOTE-NOPEA` (speed) and `VAATIMUS: REMOTE-ANDROID` (keep the logic portable) mark why a design choice was made |
| Acceptance tests | `koe-avaus/UITests`, `palvelu/test_kauko_palvelu.py` | the repeatable gates |

## The author's working files (in the monorepo, not here)

The author works with Finnish-language notes. Descriptions of their purpose follow; I could not inspect the
monorepo copies of these files from this repository, so no contents are claimed.

| File | Purpose |
|---|---|
| `REKISTERI.md` | the register: backlog and current state of a scope |
| `HISTORIA.md` | change history |
| `ARKISTO.md` | archive of closed work |
| briefs | one short written task per agent run: goal, files to touch, acceptance gate |
| delegation logs | records of which agent ran which brief and the result |

The notes are in Finnish and are working notes, not documentation.

## How to work on it

- Service: `cd palvelu && python3 -m unittest test_kauko_palvelu`. No dependencies.
- App build: see "Getting started" in `README.md`. A build with signing disabled works for compile checks:
  `xcodebuild -project RemoteKoe.xcodeproj -scheme RemoteKoe -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`.
- Changing a classifier: save real TV frames first (the capture is `tv/executeOneShot`), measure the region values,
  put the numbers and the date in a comment next to the threshold. That is the convention in all the grid files.
- Changing key timing: the constants (`viive`, `okViive`, `netflixViive`) each carry the measured result that justifies
  them. Re-measure before editing them.

## Glossary

Identifiers are Finnish. Terms are listed with their English meaning and where they appear.

| Term | English | Where |
|---|---|---|
| kauko, kaukosäädin | remote, remote control | project name; README |
| koe-avaus | "trial opening": named after the first on-device trial, `REMOTE-KOE-AVAUS` | directory name |
| palvelu | service; also the `Palvelu` enum of TV services (Netflix, ...) | `palvelu/`, `Aloitus.swift` |
| kauko-palvelu | the command service | `palvelu/kauko-palvelu.py` |
| komento, komennot | command, commands | service endpoints `/k/<command>`, `/komennot` |
| aloitus, aloitussivu | start, start page | `Aloitus.swift` |
| ohjaus | control | `Ohjaus.swift` (control views) |
| kosketuslevy, kosketusalue | touchpad, touch area | `Kosketuslevy.swift` |
| haku | search | `*Haku.swift` |
| ruudukko | grid (the on-screen keyboard grid) | `RuudukkoHaku.swift`, `*Ruudukko.swift` |
| painallus, painallukset | key press, key presses (the planned arrow sequence) | `painallukset()` in each grid |
| siirry | "move to": path between two grid positions | `siirry()` |
| ankkuroi | anchor: put focus on the keyboard, read its position | `ankkuroi()` |
| paikka | position (row, column) | `Paikka` structs |
| fokus | focus | everywhere |
| kuvakaappaus, kuvapisteet | screenshot, image pixels | `Kuvapisteet`, `kuvakaappausKuva()` |
| tunnista | recognise or classify | `NetflixRuudukko.tunnista()` etc. |
| askelpalautin, välilyönti, tyhjennä | backspace, space, clear | grid models |
| nappain, hakunakyma, valilehti | keyboard, search view, tab | classifier states (`NetflixTila`, `AreenaTila`) |
| profiili, "Kuka katsoo?" | profile, "Who is watching?" | `YouTubeProfiili.swift`, `Ohjaus.swift` |
| etuala | foreground (app) | `LGTV.etuala` |
| toisto, tauko, kohta, kesto | playback, pause, position, duration | `ToistoOSD.swift` |
| vaaka | horizontal (landscape) | `VaakaToisto` |
| herataNaytto | wake the screen | `Aloitus.swift` |
| kaynnista, kylmäkäynnistys | start, cold start | `LGTV.kaynnista` |
| vahvistin, lähde, mykistys | amplifier, input source, mute | `Aloitus.swift`; commands `amp_*` |
| ääni ylös, ääni alas | volume up, volume down | `aani_ylos`, `aani_alas` |
| nuppi | knob (the amplifier's volume knob target value) | `input_number.marantz_nupin_kohde` |
| lukko | lock | `KAUKO_LOCK`, `flock` in the service |
| tila | status or state | `LGTV.tila`, the status line |
| osoitteet | addresses | `Osoitteet.swift` |
| allekirjoitus | signature or code signing | `allekirjoitusVaroitus()` |
| testi | test | `UITests/*Testi.swift` |
| käsin | by hand (human pace) | `AreenaKasinTesti` |

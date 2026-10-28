#!/usr/bin/env python3
"""Kauko-palvelu: komentolista → HA-palvelukutsut (stdlib). Cron + lukko = yksi instanssi; --check = preflight."""
import fcntl
import json
import os
import socket
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

PORTTI = int(os.environ.get("KAUKO_PORT", "8090"))
URL_FILE = os.path.expanduser(os.environ.get("HA_URL_FILE", "~/.config/ha/url"))
TOKEN_FILE = os.path.expanduser(os.environ.get("HA_TOKEN_FILE", "~/.config/ha/token"))
LUKKO = os.path.expanduser(os.environ.get("KAUKO_LOCK", "~/.local/state/kauko-palvelu.lock"))
HA_AIKA_S = 3
NUPPI = "input_number.marantz_nupin_kohde"
NUPPI_MAX = 45
NAPIT = ["amp_paalle", "amp_pois", "amp_optical", "amp_phono", "amp_mykistys", "lg_paalle", "lg_pois"]
# Lähde Network (DAC): TV, AirPlay, HA ja palvelimen äänet; HA:ssa skriptinä (RC5x send_raw), ei IR-korttinappina.
SKRIPTIT = {"amp_network": "script.marantz_lahde_network"}
KOMENNOT = NAPIT + list(SKRIPTIT) + ["aani_ylos", "aani_alas"]


class HaVirhe(Exception):
    pass


def ha_url():
    # HA:n osoite ympäristöstä (HA_URL) tai tiedostosta (HA_URL_FILE); ei oletusosoitetta.
    url = os.environ.get("HA_URL", "")
    if not url:
        try:
            url = open(URL_FILE).read()
        except OSError:
            pass
    return url.strip().rstrip("/")


def ha(metodi, polku, data=None):
    url = ha_url()
    if not url:
        raise HaVirhe("url")
    try:
        token = open(TOKEN_FILE).read().strip()
    except OSError:
        raise HaVirhe("token")
    req = urllib.request.Request(url + polku, method=metodi,
                                 data=None if data is None else json.dumps(data).encode(),
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=HA_AIKA_S) as r:
            return json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        raise HaVirhe("HA %d" % e.code)
    except (urllib.error.URLError, OSError) as e:
        raise HaVirhe("yhteys: %s" % type(getattr(e, "reason", e)).__name__)
    except ValueError:
        raise HaVirhe("vastaus")


def aja(nimi):
    if nimi in NAPIT:
        ha("POST", "/api/services/button/press", {"entity_id": "button.ir_kaukosaadin_" + nimi})
        return
    if nimi in SKRIPTIT:
        ha("POST", "/api/services/script/turn_on", {"entity_id": SKRIPTIT[nimi]})
        return
    tila = ha("GET", "/api/states/" + NUPPI)
    try:
        nyt = int(float(tila["state"]))
    except (TypeError, KeyError, ValueError):
        raise HaVirhe("nupin tila")
    uusi = max(0, min(NUPPI_MAX, nyt + (3 if nimi == "aani_ylos" else -3)))
    ha("POST", "/api/services/input_number/set_value", {"entity_id": NUPPI, "value": uusi})
    ha("POST", "/api/services/script/turn_on", {"entity_id": "script.marantz_nuppiajuri"})


class Kasittelija(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"  # keep-alive: sovelluksen lämmitysping pitää yhteyden auki

    def log_message(self, *args):
        pass

    def vastaa(self, koodi, runko, tyyppi="application/json", ha_ms=None):
        data = runko.encode() if isinstance(runko, str) else json.dumps(runko).encode()
        self.send_response(koodi)
        self.send_header("Content-Type", tyyppi)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)
        print("%s %s %s %s %d %s" % (datetime.now().astimezone().isoformat(timespec="seconds"),
                                     self.client_address[0], self.command, self.path, koodi,
                                     "-" if ha_ms is None else ha_ms), flush=True)

    def do_GET(self):
        polku = urlsplit(self.path).path
        if polku == "/ping":
            self.vastaa(200, "ok", "text/plain")
        elif polku == "/komennot":
            self.vastaa(200, KOMENNOT)
        else:
            self.vastaa(404, {"ok": False, "virhe": "ei löydy"})

    def do_POST(self):
        pituus = int(self.headers.get("Content-Length") or 0)
        if pituus:
            self.rfile.read(pituus)
        polku = urlsplit(self.path).path
        nimi = polku[3:] if polku.startswith("/k/") else None
        if nimi not in KOMENNOT:
            self.vastaa(404, {"ok": False, "virhe": "ei löydy"})
            return
        alku = time.monotonic()
        try:
            aja(nimi)
        except HaVirhe as e:
            ms = int((time.monotonic() - alku) * 1000)
            self.vastaa(502, {"ok": False, "virhe": str(e)}, ha_ms=ms)
            return
        ms = int((time.monotonic() - alku) * 1000)
        self.vastaa(200, {"ok": True, "ha_ms": ms}, ha_ms=ms)

    def do_PUT(self):
        self.vastaa(404, {"ok": False, "virhe": "ei löydy"})

    do_DELETE = do_PATCH = do_HEAD = do_PUT


class Palvelin(ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        if isinstance(sys.exc_info()[1], (ConnectionResetError, BrokenPipeError, TimeoutError)):
            return  # asiakas katkaisi (nollaus / jouten jäänyt keep-alive): ei tracebackia
        super().handle_error(request, client_address)


def tarkista():
    tulos = {}
    tulos["url"] = bool(ha_url())
    tulos["token"] = os.access(TOKEN_FILE, os.R_OK)
    try:
        ha("GET", "/api/")
        tulos["ha"] = True
    except HaVirhe:
        tulos["ha"] = False
    s = socket.socket()
    try:
        s.bind(("0.0.0.0", PORTTI))
        tulos["portti"] = True
    except OSError:
        tulos["portti"] = False
    finally:
        s.close()
    print("preflight: " + " ".join("%s=%s" % (k, "ok" if v else "VIRHE") for k, v in tulos.items())
          + " (portti %d, %s)" % (PORTTI, ha_url() or "HA-osoite puuttuu"), flush=True)
    return 0 if all(tulos.values()) else 1


def main():
    if "--check" in sys.argv[1:]:
        return tarkista()
    os.makedirs(os.path.dirname(LUKKO) or ".", exist_ok=True)
    lukko = open(LUKKO, "w")
    try:
        fcntl.flock(lukko, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return 0
    palvelin = Palvelin(("0.0.0.0", PORTTI), Kasittelija)
    print("%s kauko-palvelu käynnissä portissa %d (pid %d)" % (
        datetime.now().astimezone().isoformat(timespec="seconds"), PORTTI, os.getpid()), flush=True)
    try:
        palvelin.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())

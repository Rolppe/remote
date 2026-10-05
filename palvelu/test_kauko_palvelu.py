"""Kauko-palvelun testit: väärennetty HA satunnaisportissa, palvelu aliprosessina."""
import http.client
import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PALVELU = os.path.join(os.path.dirname(os.path.abspath(__file__)), "kauko-palvelu.py")
TOKEN = "testitoken-5f3a9c-salainen"


class FakeHa(BaseHTTPRequestHandler):
    kutsut = []
    kohde = "26.0"
    virhe = False

    log_message = lambda self, *args: None

    def kasittele(self):
        pituus = int(self.headers.get("Content-Length") or 0)
        runko = json.loads(self.rfile.read(pituus)) if pituus else None
        FakeHa.kutsut.append((self.command, self.path, runko, self.headers.get("Authorization")))
        if FakeHa.virhe:
            koodi, data = 500, {"message": "rikki"}
        elif self.path == "/api/states/input_number.marantz_nupin_kohde":
            koodi, data = 200, {"state": FakeHa.kohde}
        else:
            koodi, data = 200, [] if self.path.startswith("/api/services/") else {"message": "API running."}
        self.send_response(koodi)
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    do_GET = do_POST = kasittele


def vapaa_portti():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class KaukoPalveluTesti(unittest.TestCase):
    vastaukset = []

    @classmethod
    def setUpClass(cls):
        cls.ha = ThreadingHTTPServer(("127.0.0.1", 0), FakeHa)
        threading.Thread(target=cls.ha.serve_forever, daemon=True).start()
        cls.tmp = tempfile.TemporaryDirectory()
        token = os.path.join(cls.tmp.name, "token")
        with open(token, "w") as f: f.write(TOKEN + "\n")
        cls.portti = vapaa_portti()
        cls.env = dict(os.environ, KAUKO_PORT=str(cls.portti), HA_TOKEN_FILE=token,
                       HA_URL="http://127.0.0.1:%d" % cls.ha.server_address[1],
                       KAUKO_LOCK=os.path.join(cls.tmp.name, "kauko.lock"))
        cls.loki = open(os.path.join(cls.tmp.name, "stdout"), "w+")
        cls.p = subprocess.Popen([sys.executable, PALVELU], env=cls.env, stdout=cls.loki,
                                 stderr=subprocess.STDOUT)
        loppu = time.time() + 10
        while True:
            try:
                urllib.request.urlopen("http://127.0.0.1:%d/ping" % cls.portti, timeout=1).read()
                break
            except OSError:
                if time.time() > loppu or cls.p.poll() is not None:
                    raise RuntimeError("palvelu ei käynnistynyt")
                time.sleep(0.1)

    @classmethod
    def tearDownClass(cls):
        cls.p.terminate(), cls.p.wait(5)
        cls.ha.shutdown(), cls.ha.server_close()
        cls.loki.close()
        cls.tmp.cleanup()

    def setUp(self):
        FakeHa.kutsut.clear()
        FakeHa.virhe = False
        FakeHa.kohde = "26.0"

    def pyynto(self, metodi, polku):
        req = urllib.request.Request("http://127.0.0.1:%d%s" % (self.portti, polku), method=metodi,
                                     data=b"" if metodi == "POST" else None)
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                koodi, runko = r.status, r.read().decode()
        except urllib.error.HTTPError as e:
            koodi, runko = e.code, e.read().decode()
        self.vastaukset.append(runko)
        return koodi, runko

    def test_amp_paalle(self):
        koodi, runko = self.pyynto("POST", "/k/amp_paalle")
        self.assertEqual((koodi, json.loads(runko)["ok"]), (200, True))
        self.assertIsInstance(json.loads(runko)["ha_ms"], int)
        self.assertEqual(FakeHa.kutsut, [("POST", "/api/services/button/press",
                                          {"entity_id": "button.ir_kaukosaadin_amp_paalle"},
                                          "Bearer " + TOKEN)])

    def nuppi(self, komento, kohde):
        FakeHa.kohde = kohde
        self.assertEqual(self.pyynto("POST", "/k/" + komento)[0], 200)
        self.assertEqual([k[:2] for k in FakeHa.kutsut], [
            ("GET", "/api/states/input_number.marantz_nupin_kohde"),
            ("POST", "/api/services/input_number/set_value"),
            ("POST", "/api/services/script/turn_on")])
        self.assertEqual(FakeHa.kutsut[2][2], {"entity_id": "script.marantz_nuppiajuri"})
        runko = FakeHa.kutsut[1][2]
        self.assertEqual(runko["entity_id"], "input_number.marantz_nupin_kohde")
        return runko["value"]

    def test_aani_ylos(self):
        self.assertEqual(self.nuppi("aani_ylos", "26.0"), 29)

    def test_aani_ylos_katto(self):
        self.assertEqual(self.nuppi("aani_ylos", "44.0"), 45)

    def test_aani_alas_lattia(self):
        self.assertEqual(self.nuppi("aani_alas", "1.0"), 0)

    def test_tuntematon(self):
        self.assertEqual(self.pyynto("POST", "/k/ei_ole")[0], 404)
        self.assertEqual(self.pyynto("GET", "/muu")[0], 404)
        self.assertEqual(FakeHa.kutsut, [])

    def test_ping_ja_komennot(self):
        self.assertEqual(self.pyynto("GET", "/ping"), (200, "ok"))
        koodi, runko = self.pyynto("GET", "/komennot")
        self.assertEqual((koodi, json.loads(runko)[0]), (200, "amp_paalle"))

    def test_ha_virhe_502(self):
        FakeHa.virhe = True
        koodi, runko = self.pyynto("POST", "/k/lg_pois")
        self.assertEqual((koodi, json.loads(runko)["ok"]), (502, False))

    def test_toinen_instanssi(self):
        alku = time.monotonic()
        r = subprocess.run([sys.executable, PALVELU], env=self.env, capture_output=True, timeout=10)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout + r.stderr, b"")
        self.assertLess(time.monotonic() - alku, 5)

    def test_keepalive(self):
        c = http.client.HTTPConnection("127.0.0.1", self.portti, timeout=10)
        c.request("GET", "/ping")
        r = c.getresponse()
        self.assertEqual((r.status, r.read(), r.version), (200, b"ok", 11))
        paikallinen = c.sock.getsockname()
        c.request("HEAD", "/ping")
        r = c.getresponse()
        self.assertEqual(r.read(), b"")
        c.request("POST", "/k/amp_pois", body=b"{}")
        r = c.getresponse()
        self.assertEqual((r.status, json.loads(r.read())["ok"]), (200, True))
        self.assertEqual(c.sock.getsockname(), paikallinen)
        c.close()

    def test_yhteyden_nollaus_ei_lokita(self):
        s = socket.create_connection(("127.0.0.1", self.portti), timeout=5)
        s.sendall(b"GET /ping HTTP/1.1\r\nHost: x\r\n")
        s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        s.close()
        time.sleep(0.5)
        self.loki.flush()
        loki = self.loki.seek(0) or self.loki.read()
        self.assertNotIn("Traceback", loki)
        self.assertNotIn("ConnectionResetError", loki)
        self.assertEqual(self.pyynto("GET", "/ping"), (200, "ok"))

    def test_zz_token_ei_vuoda(self):
        self.pyynto("POST", "/k/amp_pois")
        self.pyynto("GET", "/ping?x=1")
        self.assertTrue(self.vastaukset)
        for runko in self.vastaukset:
            self.assertNotIn(TOKEN, runko)
        time.sleep(0.2)
        loki = self.loki.seek(0) or self.loki.read()
        self.assertIn("GET /ping?x=1 200", loki)
        self.assertNotIn(TOKEN, loki)


if __name__ == "__main__":
    unittest.main()

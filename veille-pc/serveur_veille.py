#!/usr/bin/env python3
"""
Télécommande de veille pour PC, pilotable depuis un téléphone.

- Lance un mini serveur web sur le PC (réseau local).
- Ouvre l'adresse affichée sur ton téléphone : un gros bouton « Mettre en veille ».
- Le réveil se fait par Wake-on-LAN (voir README.md) : un PC en veille ne peut
  pas écouter ce serveur, c'est le téléphone qui envoie le « paquet magique ».

Aucune dépendance : Python 3.8+ suffit. Windows, macOS et Linux.
"""
import hmac
import json
import os
import platform
import secrets
import socket
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

DOSSIER = Path(__file__).resolve().parent
FICHIER_CONFIG = DOSSIER / "veille-config.json"
PORT_PAR_DEFAUT = 8765
SIMULATION = os.environ.get("VEILLE_SIMULATION") == "1"  # pour tester sans mettre en veille


# ---------------------------------------------------------------- configuration
def charger_config():
    if FICHIER_CONFIG.exists():
        cfg = json.loads(FICHIER_CONFIG.read_text(encoding="utf-8"))
    else:
        cfg = {}
    modifie = False
    if not cfg.get("cle"):
        cfg["cle"] = secrets.token_urlsafe(16)
        modifie = True
    if not cfg.get("port"):
        cfg["port"] = PORT_PAR_DEFAUT
        modifie = True
    if modifie:
        FICHIER_CONFIG.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    return cfg


def ip_locale():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.168.0.1", 9))  # aucun paquet envoyé, sert à choisir l'interface
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


def adresse_mac():
    n = uuid.getnode()
    if n & (1 << 40):  # adresse aléatoire : la vraie MAC n'a pas pu être lue
        return "non détectée (voir README)"
    return ":".join(f"{(n >> s) & 0xFF:02X}" for s in range(40, -1, -8))


# ---------------------------------------------------------------- mise en veille
def mettre_en_veille():
    systeme = platform.system()
    if SIMULATION:
        print(f"[simulation] mise en veille demandée ({systeme})", flush=True)
        return
    if systeme == "Windows":
        import ctypes
        # (Hibernate=False, ForceCritical=True, DisableWakeEvent=False)
        # Si l'hibernation est activée sous Windows, cet appel hiberne au lieu
        # de mettre en veille : voir README (powercfg /hibernate off).
        ctypes.windll.powrprof.SetSuspendState(False, True, False)
    elif systeme == "Darwin":
        subprocess.run(["pmset", "sleepnow"], check=False)
    else:
        subprocess.run(["systemctl", "suspend"], check=False)


def veille_differee(delai=2.0):
    # Laisse le temps à la réponse HTTP d'arriver sur le téléphone.
    def _run():
        time.sleep(delai)
        mettre_en_veille()
    threading.Thread(target=_run, daemon=True).start()


# ---------------------------------------------------------------- page web
PAGE = """<!doctype html>
<html lang="fr"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="theme-color" content="#111827">
<title>Veille PC</title>
<style>
 :root{color-scheme:dark}
 body{margin:0;min-height:100vh;display:flex;flex-direction:column;align-items:center;
      justify-content:center;gap:24px;background:#111827;color:#e5e7eb;
      font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;padding:16px;box-sizing:border-box}
 h1{font-size:20px;font-weight:600;margin:0}
 #etat{font-size:15px;color:#9ca3af}
 #etat.ok{color:#34d399} #etat.ko{color:#f87171}
 button{width:220px;height:220px;border-radius:50%;border:0;font-size:22px;font-weight:700;
        background:#4f46e5;color:#fff;box-shadow:0 10px 30px rgba(79,70,229,.45);cursor:pointer}
 button:active{transform:scale(.96)}
 button:disabled{background:#374151;box-shadow:none}
 .aide{max-width:420px;font-size:13px;color:#9ca3af;line-height:1.5;text-align:center}
 code{color:#e5e7eb}
</style></head><body>
<h1>__NOM__</h1>
<div id="etat">Vérification…</div>
<button id="b">Mettre en veille</button>
<p class="aide">Pour <b>réveiller</b> : utilise ton app Wake-on-LAN avec l'adresse MAC
<code>__MAC__</code> (à confirmer, voir README).</p>
<script>
const CLE = "__CLE__";
const etat = document.getElementById("etat"), b = document.getElementById("b");
async function verifier(){
  try{
    const r = await fetch("/etat", {headers:{"X-Cle":CLE}, cache:"no-store"});
    if(!r.ok) throw 0;
    etat.textContent = "PC allumé"; etat.className = "ok"; b.disabled = false;
  }catch(e){ etat.textContent = "PC injoignable (en veille ou éteint)"; etat.className = "ko"; b.disabled = true; }
}
b.onclick = async () => {
  b.disabled = true;
  try{
    const r = await fetch("/veille", {method:"POST", headers:{"X-Cle":CLE}});
    if(!r.ok) throw 0;
    etat.textContent = "Mise en veille…"; etat.className = "";
    setTimeout(verifier, 8000);
  }catch(e){ etat.textContent = "Échec de la commande"; etat.className = "ko"; b.disabled = false; }
};
verifier(); setInterval(verifier, 15000);
</script></body></html>"""


def fabriquer_handler(cfg):
    cle = cfg["cle"]
    nom = cfg.get("nom") or socket.gethostname()
    mac = cfg.get("mac") or adresse_mac()

    class Handler(BaseHTTPRequestHandler):
        server_version = "VeillePC/1.0"

        def log_message(self, fmt, *args):
            print(f"{self.address_string()} - {fmt % args}", flush=True)

        def _autorise(self):
            fournie = self.headers.get("X-Cle") or parse_qs(urlparse(self.path).query).get("k", [""])[0]
            return hmac.compare_digest(fournie.encode(), cle.encode())

        def _repondre(self, code, corps, type_="application/json; charset=utf-8"):
            data = corps.encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", type_)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            chemin = urlparse(self.path).path
            if not self._autorise():
                return self._repondre(403, '{"erreur":"cle invalide"}')
            if chemin == "/":
                html = PAGE.replace("__CLE__", cle).replace("__NOM__", nom).replace("__MAC__", mac)
                return self._repondre(200, html, "text/html; charset=utf-8")
            if chemin == "/etat":
                return self._repondre(200, json.dumps({"ok": True, "nom": nom}))
            return self._repondre(404, '{"erreur":"introuvable"}')

        def do_POST(self):
            if not self._autorise():
                return self._repondre(403, '{"erreur":"cle invalide"}')
            if urlparse(self.path).path == "/veille":
                veille_differee()
                return self._repondre(200, '{"ok":true,"action":"veille"}')
            return self._repondre(404, '{"erreur":"introuvable"}')

    return Handler


def main():
    if sys.stdout is None:  # lancé sans console (pythonw) : on écrit dans un journal
        sys.stdout = sys.stderr = open(DOSSIER / "veille.log", "a", encoding="utf-8", buffering=1)
    cfg = charger_config()
    port = int(cfg["port"])
    serveur = ThreadingHTTPServer(("0.0.0.0", port), fabriquer_handler(cfg))
    url = f"http://{ip_locale()}:{port}/?k={cfg['cle']}"
    print("=" * 64)
    print(" Télécommande de veille prête.")
    print(f" Sur ton téléphone (même Wi-Fi), ouvre :\n   {url}")
    print(f" Adresse MAC détectée (pour le réveil) : {adresse_mac()}")
    print(" Garde ce lien privé : il contient ta clé d'accès.")
    print("=" * 64, flush=True)
    try:
        serveur.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())

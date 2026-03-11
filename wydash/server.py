#!/usr/bin/env python3
"""
WyDash server — browser-based CKB node management
Serves index.html + status API + config API
Config: wydash.conf (INI format) — controls which modules are active

Usage: python3 server.py [--port 9999] [--config wydash.conf]
"""

import http.server
import urllib.request
import urllib.error
import os
import json
import argparse
import configparser
from concurrent.futures import ThreadPoolExecutor, as_completed

# ── Args ──────────────────────────────────────────────────────────────────────
parser = argparse.ArgumentParser()
parser.add_argument("--port",   type=int, default=9999)
parser.add_argument("--host",   default="0.0.0.0")
parser.add_argument("--config", default=os.path.join(os.path.dirname(__file__), "wydash.conf"))
args = parser.parse_args()

STATIC_DIR = os.path.dirname(os.path.abspath(__file__))

# ── Config ────────────────────────────────────────────────────────────────────
def load_config(path):
    cfg = configparser.ConfigParser()
    # Defaults — all modules off
    cfg.read_dict({'modules': {
        'ckb_node':   'false',
        'mining':     'false',
        'fiber':      'false',
        'dob_minter': 'false',
        'dob_burner': 'false',
    }})
    if os.path.exists(path):
        cfg.read(path)
    return cfg

def modules_enabled(cfg):
    m = cfg['modules']
    return {k: m.getboolean(k) for k in m}

def config_as_dict(cfg):
    return {s: dict(cfg[s]) for s in cfg.sections()}

# ── Service checks (only for enabled modules) ─────────────────────────────────
def check_url(url, timeout=2):
    try:
        return urllib.request.urlopen(url, timeout=timeout).status == 200
    except Exception:
        return False

def check_services(cfg):
    mods = modules_enabled(cfg)
    checks = {}

    if mods.get('ckb_node'):
        url = cfg.get('ckb_node', 'dash_url', fallback='http://127.0.0.1:8080')
        checks['ckb_node'] = lambda u=url: check_url(u + '/health')

    if mods.get('mining'):
        url = cfg.get('mining', 'dash_url', fallback='http://127.0.0.1:8081')
        checks['mining'] = lambda u=url: check_url(u + '/health')

    if mods.get('fiber'):
        url = cfg.get('fiber', 'dash_url', fallback='http://127.0.0.1:8229')
        checks['fiber'] = lambda u=url: check_url(u + '/')

    if mods.get('dob_minter'):
        url = cfg.get('dob_minter', 'dash_url', fallback='http://127.0.0.1:5173')
        checks['dob_minter'] = lambda u=url: check_url(u + '/')

    if not checks:
        return {}

    results = {}
    with ThreadPoolExecutor(max_workers=max(len(checks), 1)) as ex:
        futures = {ex.submit(fn): key for key, fn in checks.items()}
        for f in as_completed(futures):
            results[futures[f]] = f.result()
    return results

# ── HTTP handler ──────────────────────────────────────────────────────────────
class DashHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=STATIC_DIR, **kwargs)

    def log_message(self, fmt, *a):
        pass  # Silent

    def _json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        cfg = load_config(args.config)

        if self.path == '/health':
            self._json({'ok': True})
            return

        if self.path == '/api/status':
            self._json(check_services(cfg))
            return

        if self.path == '/api/config':
            # Expose enabled modules + section configs to the frontend
            self._json({
                'modules': modules_enabled(cfg),
                'sections': config_as_dict(cfg),
            })
            return

        # Static files — no-cache for HTML
        if self.path.endswith('.html') or self.path in ('/', ''):
            path = self.translate_path(self.path)
            if os.path.isdir(path):
                path = os.path.join(path, 'index.html')
            try:
                with open(path, 'rb') as f:
                    data = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            except Exception:
                pass
        super().do_GET()

# ── Main ──────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    cfg = load_config(args.config)
    active = [k for k, v in modules_enabled(cfg).items() if v]
    print(f"WyDash → http://{args.host}:{args.port}")
    print(f"Modules: {', '.join(active) if active else '(none enabled)'}")
    print(f"Config:  {args.config}")
    server = http.server.HTTPServer((args.host, args.port), DashHandler)
    server.serve_forever()

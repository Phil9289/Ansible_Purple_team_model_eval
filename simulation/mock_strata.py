#!/usr/bin/env python3
"""
Faux Strata pour la simulation : imite l'API du LXC 242 (compatible OpenAI) sans GPU.

- GET  /v1/models            -> qwen3.8-flash-next-iq2_xs, n_ctx configurable
- POST /v1/chat/completions  -> réponses déterministes (texte, appels d'outils, streaming SSE)
                                 avec reasoning_content, usage et timings comme le vrai Strata
- GET  /                     -> fausse interface web (doit rester invisible depuis le labo)
- POST /api/models/delete    -> fausse route d'admin (doit rester invisible depuis le labo)
- GET  /sim/stats            -> compteurs de la simulation (concurrence maximale observée, etc.)

Le délai de réponse suit les vitesses mesurées le 20 nov (Dual-3-A1 : ~330 tok/s en
lecture, ~47 tok/s en écriture), multipliées par MOCK_SPEED (0.02 = 50 fois plus vite).
"""
import json
import os
import re
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODEL = os.environ.get("MOCK_MODEL", "qwen3.8-flash-next-iq2_xs")
N_CTX = int(os.environ.get("MOCK_N_CTX", "65536"))
SPEED = float(os.environ.get("MOCK_SPEED", "0.02"))
PREFILL_TPS, DECODE_TPS = 330.0, 47.0
PORT = int(os.environ.get("MOCK_PORT", "8080"))

STATS = {"requests": 0, "active": 0, "max_active": 0, "admin_hits": 0, "ui_hits": 0,
         "clients": {}, "streamed": 0, "tool_calls": 0}
LOCK = threading.Lock()


def toks(obj):
    return max(1, len(json.dumps(obj, ensure_ascii=False)) // 3)


def text_of(msg):
    c = msg.get("content")
    if isinstance(c, list):
        return " ".join(p.get("text", "") for p in c if isinstance(p, dict))
    return c or ""


def pick_tool(tools):
    names = [t.get("function", {}).get("name") for t in tools or []]
    for wanted in ("terminal", "shell", "run_command", "execute_command", "bash"):
        if wanted in names:
            return wanted
    return names[0] if names else None


def decide(body):
    """Retourne (reasoning, content, tool_calls)."""
    msgs = body.get("messages", [])
    last = msgs[-1] if msgs else {}
    users = [text_of(m) for m in msgs if m.get("role") == "user"]
    last_user = users[-1] if users else ""

    m = re.search(r"(?:Reply exactly|Réponds seulement\s*:)\s*([A-Z0-9_]+)", last_user)
    if m and last.get("role") == "user":
        return f"L'utilisateur veut exactement {m.group(1)}.", m.group(1), None

    if last.get("role") == "tool":
        out = text_of(last)
        ports = re.findall(r"(\d+/tcp\s+open\s+\S+(?:\s+\S+)*)", out)
        summary = "; ".join(p.strip() for p in ports[:5]) or out.strip()[:300]
        return ("J'ai le résultat de l'outil, je résume.",
                f"Résultat du scan : {summary}. Le serveur web expose un listage de répertoire "
                f"(autoindex) : prochaine étape suggérée, `curl -s http://10.30.0.20:8080/`.", None)

    tool = pick_tool(body.get("tools"))
    if tool and re.search(r"nmap|scan|sous-réseau|subnet", last_user, re.I):
        target = re.search(r"\d+\.\d+\.\d+\.\d+(?:/\d+)?", last_user)
        cmd = f"nmap -sV -p 8080 {target.group(0) if target else '10.30.0.20'}"
        args = {"command": cmd} if tool in ("terminal", "shell", "bash", "run_command", "execute_command") else {}
        call = {"id": "call_" + uuid.uuid4().hex[:24], "type": "function",
                "function": {"name": tool, "arguments": json.dumps(args)}}
        return (f"Il faut d'abord scanner la cible avec l'outil {tool}.", "", [call])

    if "nmap" in last_user.lower() or "scan" in last_user.lower():
        service = "nginx" if "nginx" in last_user.lower() else "un serveur HTTP"
        return ("Le scan montre un service web. Je propose un test de listage.",
                f"Service détecté : {service} sur le port 8080/tcp. Le listage de répertoire est "
                "probablement actif. Commande de test : `curl -s -i http://10.30.0.20:8080/`", None)

    return ("Question générale.", "Bonjour, ici le faux Strata de la simulation.", None)


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        return

    def send(self, status, obj, ctype="application/json"):
        data = obj if isinstance(obj, bytes) else json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n)) if n else {}

    def do_GET(self):
        with LOCK:
            STATS["clients"][self.client_address[0]] = STATS["clients"].get(self.client_address[0], 0) + 1
        if self.path == "/v1/models":
            return self.send(200, {"object": "list", "data": [
                {"id": MODEL, "object": "model", "owned_by": "strata", "meta": {"n_ctx_train": N_CTX}}]})
        if self.path == "/sim/stats":
            with LOCK:
                return self.send(200, STATS)
        if self.path == "/":
            with LOCK:
                STATS["ui_hits"] += 1
            return self.send(200, b"<html><title>Strata</title><body>Interface web Strata (fausse)</body></html>",
                             "text/html")
        self.send(404, {"error": "not found"})

    def do_POST(self):
        if self.path.startswith("/api/"):
            with LOCK:
                STATS["admin_hits"] += 1
            self.body()
            return self.send(200, {"deleted": True, "warning": "route d'admin atteinte !"})
        if self.path != "/v1/chat/completions":
            return self.send(404, {"error": "not found"})
        body = self.body()
        with LOCK:
            STATS["requests"] += 1
            STATS["active"] += 1
            STATS["max_active"] = max(STATS["max_active"], STATS["active"])
            STATS["clients"][self.client_address[0]] = STATS["clients"].get(self.client_address[0], 0) + 1
        try:
            self.chat(body)
        finally:
            with LOCK:
                STATS["active"] -= 1

    def chat(self, body):
        p_tok = toks(body.get("messages", [])) + toks(body.get("tools", []))
        if p_tok + int(body.get("max_tokens") or 0) > N_CTX:
            return self.send(400, {"error": {"message": f"context exceeded: {p_tok} > n_ctx {N_CTX}"}})
        reasoning, content, calls = decide(body)
        c_tok = toks(reasoning) + toks(content) + (toks(calls) if calls else 0)
        time.sleep((p_tok / PREFILL_TPS + c_tok / DECODE_TPS) * SPEED)
        usage = {"prompt_tokens": p_tok, "completion_tokens": c_tok, "total_tokens": p_tok + c_tok}
        timings = {"prompt_per_second": PREFILL_TPS, "predicted_per_second": DECODE_TPS, "draft_n_accepted": 3}
        finish = "tool_calls" if calls else "stop"
        cid = "chatcmpl-" + uuid.uuid4().hex[:20]
        if calls:
            with LOCK:
                STATS["tool_calls"] += 1
        if body.get("stream"):
            with LOCK:
                STATS["streamed"] += 1
            return self.stream(cid, reasoning, content, calls, finish, usage, timings)
        msg = {"role": "assistant", "content": content, "reasoning_content": reasoning}
        if calls:
            msg["tool_calls"] = calls
        self.send(200, {"id": cid, "object": "chat.completion", "created": int(time.time()), "model": MODEL,
                        "choices": [{"index": 0, "message": msg, "finish_reason": finish}],
                        "usage": usage, "timings": timings})

    def stream(self, cid, reasoning, content, calls, finish, usage, timings):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        def ev(delta, fin=None, extra=None):
            obj = {"id": cid, "object": "chat.completion.chunk", "created": int(time.time()), "model": MODEL,
                   "choices": [{"index": 0, "delta": delta, "finish_reason": fin}]}
            obj.update(extra or {})
            data = b"data: " + json.dumps(obj, ensure_ascii=False).encode() + b"\n\n"
            self.wfile.write(f"{len(data):x}\r\n".encode() + data + b"\r\n")
            self.wfile.flush()

        ev({"role": "assistant", "content": ""})
        for w in reasoning.split(" "):
            ev({"reasoning_content": w + " "})
        for w in re.findall(r"\S+\s*", content):
            ev({"content": w})
        if calls:
            for i, c in enumerate(calls):
                ev({"tool_calls": [{"index": i, "id": c["id"], "type": "function",
                                    "function": {"name": c["function"]["name"], "arguments": ""}}]})
                ev({"tool_calls": [{"index": i, "function": {"arguments": c["function"]["arguments"]}}]})
        ev({}, finish)
        ev({}, None, {"choices": [], "usage": usage, "timings": timings})
        data = b"data: [DONE]\n\n"
        self.wfile.write(f"{len(data):x}\r\n".encode() + data + b"\r\n0\r\n\r\n")
        self.wfile.flush()


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), H)
    srv.daemon_threads = True
    print(f"faux Strata sur 0.0.0.0:{PORT}, modèle {MODEL}, n_ctx {N_CTX}, vitesse x{1 / SPEED:.0f}", flush=True)
    srv.serve_forever()

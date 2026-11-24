#!/usr/bin/env python3
"""
Passerelle LLM du labo Purple Team : seul chemin entre l'agent (vmbr3) et Strata (vmbr4).

Bibliothèque standard Python uniquement (aucun pip, aucun binaire AVX2) :
le Xeon E5-2620 v1 du Proxmox n'a que l'AVX.

Ce qu'elle fait, dans l'ordre, pour chaque requête :
  1. Liste blanche de routes : GET /v1/models, POST /v1/chat/completions, GET /health.
     Tout le reste (interface web de Strata, routes d'admin...) -> 404.
  2. Clé API obligatoire (Authorization: Bearer ...), comparée en temps constant.
  3. Limites : taille du corps, nombre de messages, taille estimée du prompt,
     max_tokens plafonné, débit par client.
  4. Le champ "model" est imposé : l'agent ne peut pas choisir un autre modèle.
  5. File d'attente : une seule requête à la fois vers Strata (P100 passive,
     Strata recommande 1 requête). Les autres attendent, jusqu'à un plafond.
  6. Relais vers Strata, en streaming (SSE) ou non.
  7. Une ligne JSON par requête vers syslog (-> serveur de journaux du labo).

Configuration : variables d'environnement GW_* (fichier /etc/strata-gateway/gateway.env).
"""
import hashlib
import hmac
import http.client
import json
import logging
import logging.handlers
import os
import socket
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def env(name, default):
    return os.environ.get(name, default)


CFG = {
    "listen_host": env("GW_LISTEN_HOST", "0.0.0.0"),
    "listen_port": int(env("GW_LISTEN_PORT", "8000")),
    "api_key": env("GW_API_KEY", ""),
    "upstream_host": env("GW_UPSTREAM_HOST", "10.40.0.42"),
    "upstream_port": int(env("GW_UPSTREAM_PORT", "8080")),
    "upstream_key": env("GW_UPSTREAM_KEY", "strata-local"),
    "upstream_timeout": float(env("GW_UPSTREAM_TIMEOUT", "900")),
    "model_id": env("GW_MODEL_ID", "qwen3.8-flash-next-iq2_xs"),
    "context_tokens": int(env("GW_CONTEXT_TOKENS", "65536")),
    "max_body_bytes": int(env("GW_MAX_BODY_BYTES", str(1024 * 1024))),
    "max_messages": int(env("GW_MAX_MESSAGES", "400")),
    "default_max_tokens": int(env("GW_DEFAULT_MAX_TOKENS", "4096")),
    "max_tokens_cap": int(env("GW_MAX_TOKENS_CAP", "8192")),
    "queue_max": int(env("GW_QUEUE_MAX", "4")),
    "queue_timeout": float(env("GW_QUEUE_TIMEOUT", "900")),
    "rate_per_minute": int(env("GW_RATE_PER_MINUTE", "30")),
    "cooldown_seconds": float(env("GW_COOLDOWN_SECONDS", "0")),
    "syslog_address": env("GW_SYSLOG_ADDRESS", "/dev/log"),
    "log_prompt_preview": int(env("GW_LOG_PROMPT_PREVIEW", "0")),
}

ALLOWED = {("GET", "/v1/models"), ("POST", "/v1/chat/completions"), ("GET", "/health")}
# Champs que l'agent a le droit d'envoyer à Strata. Le reste est retiré.
ALLOWED_FIELDS = {
    "messages", "temperature", "top_p", "max_tokens", "max_completion_tokens", "stream",
    "stream_options", "tools", "tool_choice", "parallel_tool_calls", "stop", "seed",
    "presence_penalty", "frequency_penalty", "response_format", "n", "model",
}


# ---------------------------------------------------------------- journaux
def build_logger():
    log = logging.getLogger("strata-gateway")
    log.setLevel(logging.INFO)
    addr = CFG["syslog_address"]
    try:
        if addr.startswith("tcp://"):
            host, port = addr[6:].rsplit(":", 1)
            h = logging.handlers.SysLogHandler(address=(host, int(port)), socktype=socket.SOCK_STREAM,
                                               facility=logging.handlers.SysLogHandler.LOG_LOCAL5)
            h.append_nul = False
        elif addr.startswith("udp://"):
            host, port = addr[6:].rsplit(":", 1)
            h = logging.handlers.SysLogHandler(address=(host, int(port)),
                                               facility=logging.handlers.SysLogHandler.LOG_LOCAL5)
        else:
            h = logging.handlers.SysLogHandler(address=addr, facility=logging.handlers.SysLogHandler.LOG_LOCAL5)
        h.setFormatter(logging.Formatter("strata-gateway: %(message)s\n" if addr.startswith("tcp://")
                                         else "strata-gateway: %(message)s"))
        log.addHandler(h)
    except OSError as exc:  # pas de syslog : on garde au moins la console (journald)
        print(f"syslog indisponible ({exc}), journal sur la console seulement", file=sys.stderr)
    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(logging.Formatter("%(message)s"))
    log.addHandler(console)
    return log


LOG = build_logger()


def audit(**fields):
    fields.setdefault("ts", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
    LOG.info(json.dumps(fields, ensure_ascii=False, sort_keys=True))


# ------------------------------------------------- file d'attente et débit
class Queue:
    """Une seule requête à la fois vers Strata ; au plus queue_max en attente."""

    def __init__(self):
        self.lock = threading.Lock()
        self.cond = threading.Condition()
        self.waiting = 0
        self.last_end = 0.0

    def acquire(self, timeout):
        with self.cond:
            if self.waiting >= CFG["queue_max"]:
                return None
            self.waiting += 1
        t0 = time.monotonic()
        got = self.lock.acquire(timeout=timeout)
        with self.cond:
            self.waiting -= 1
        if not got:
            return None
        pause = CFG["cooldown_seconds"] - (time.monotonic() - self.last_end)
        if pause > 0:  # laisser souffler la P100 entre deux requêtes
            time.sleep(pause)
        return time.monotonic() - t0

    def release(self):
        self.last_end = time.monotonic()
        self.lock.release()


QUEUE = Queue()


class RateLimiter:
    def __init__(self):
        self.hits = {}
        self.lock = threading.Lock()

    def allow(self, client):
        now = time.monotonic()
        with self.lock:
            recent = [t for t in self.hits.get(client, []) if now - t < 60]
            if len(recent) >= CFG["rate_per_minute"]:
                self.hits[client] = recent
                return False
            recent.append(now)
            self.hits[client] = recent
            return True


RATE = RateLimiter()


def estimate_tokens(obj):
    """Estimation prudente : ~3 caractères par token (français, JSON, journaux)."""
    return len(json.dumps(obj, ensure_ascii=False)) // 3


# ---------------------------------------------------------------- serveur
class Handler(BaseHTTPRequestHandler):
    server_version = "strata-gateway"
    sys_version = ""
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # l'audit JSON remplace le journal par défaut
        return

    # --- utilitaires
    def client(self):
        return self.client_address[0]

    def send_json(self, status, obj, extra=None):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def refuse(self, status, reason, rid, **more):
        audit(event="refus", request_id=rid, client=self.client(), method=self.command,
              path=self.path, status=status, reason=reason, **more)
        self.send_json(status, {"error": {"message": reason, "type": "gateway_refusal", "code": status}},
                       {"X-Request-Id": rid})

    def authorized(self):
        header = self.headers.get("Authorization", "")
        if not CFG["api_key"] or not header.startswith("Bearer "):
            return False
        return hmac.compare_digest(header[7:].strip().encode(), CFG["api_key"].encode())

    def upstream(self):
        return http.client.HTTPConnection(CFG["upstream_host"], CFG["upstream_port"],
                                          timeout=CFG["upstream_timeout"])

    def upstream_headers(self):
        return {"Content-Type": "application/json", "Authorization": f"Bearer {CFG['upstream_key']}",
                "User-Agent": "strata-gateway"}

    # --- routage
    def do_GET(self):
        self.route()

    def do_POST(self):
        self.route()

    def do_PUT(self):
        self.route()

    def do_DELETE(self):
        self.route()

    def do_PATCH(self):
        self.route()

    def route(self):
        rid = uuid.uuid4().hex[:12]
        path = self.path.split("?", 1)[0]
        # Corps lu et jeté pour les routes refusées (garde la connexion propre)
        if (self.command, path) not in ALLOWED:
            self.drain()
            return self.refuse(404, "route non permise par la passerelle", rid)
        if path == "/health":
            return self.health(rid)
        if not self.authorized():
            self.drain()
            return self.refuse(401, "clé API absente ou invalide", rid)
        if not RATE.allow(self.client()):
            self.drain()
            return self.refuse(429, "trop de requêtes par minute", rid)
        if path == "/v1/models":
            return self.models(rid)
        return self.chat(rid)

    def drain(self):
        n = int(self.headers.get("Content-Length") or 0)
        if 0 < n <= CFG["max_body_bytes"]:
            self.rfile.read(n)
        elif n > CFG["max_body_bytes"]:
            self.close_connection = True

    def health(self, rid):
        try:
            c = self.upstream()
            c.timeout = 5
            c.request("GET", "/v1/models", headers=self.upstream_headers())
            ok = c.getresponse().status == 200
            c.close()
        except OSError:
            ok = False
        self.send_json(200 if ok else 503, {"gateway": "ok", "strata": "ok" if ok else "injoignable",
                                            "queue_waiting": QUEUE.waiting}, {"X-Request-Id": rid})

    def models(self, rid):
        # Réponse construite par la passerelle : un seul modèle, avec la taille de contexte.
        audit(event="models", request_id=rid, client=self.client(), status=200)
        self.send_json(200, {"object": "list", "data": [{
            "id": CFG["model_id"], "object": "model", "owned_by": "strata",
            "context_length": CFG["context_tokens"], "max_model_len": CFG["context_tokens"],
            "meta": {"n_ctx_train": CFG["context_tokens"], "n_ctx": CFG["context_tokens"]}}]},
            {"X-Request-Id": rid})

    def read_body(self, rid):
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            self.close_connection = True
            self.refuse(411, "corps chunked refusé : envoyer Content-Length", rid)
            return None
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0:
            self.refuse(400, "corps JSON manquant", rid)
            return None
        if n > CFG["max_body_bytes"]:
            self.close_connection = True
            self.refuse(413, f"requête trop grosse ({n} octets)", rid, size=n)
            return None
        try:
            body = json.loads(self.rfile.read(n))
        except (ValueError, UnicodeDecodeError):
            self.refuse(400, "JSON invalide", rid)
            return None
        if not isinstance(body, dict) or not isinstance(body.get("messages"), list) or not body["messages"]:
            self.refuse(400, "champ messages manquant ou vide", rid)
            return None
        return body

    def chat(self, rid):
        body = self.read_body(rid)
        if body is None:
            return
        if len(body["messages"]) > CFG["max_messages"]:
            return self.refuse(413, "trop de messages", rid, messages=len(body["messages"]))
        asked_model = body.get("model")
        clean = {k: v for k, v in body.items() if k in ALLOWED_FIELDS}
        dropped = sorted(set(body) - ALLOWED_FIELDS)
        clean["model"] = CFG["model_id"]          # l'agent ne choisit pas le modèle
        clean.pop("max_completion_tokens", None)
        mt = body.get("max_tokens") or body.get("max_completion_tokens") or CFG["default_max_tokens"]
        try:
            mt = int(mt)
        except (TypeError, ValueError):
            mt = CFG["default_max_tokens"]
        clean["max_tokens"] = max(1, min(mt, CFG["max_tokens_cap"]))
        clean["n"] = 1
        prompt_est = estimate_tokens(clean["messages"]) + estimate_tokens(clean.get("tools", []))
        if prompt_est + clean["max_tokens"] > CFG["context_tokens"]:
            return self.refuse(413, "prompt trop long pour le contexte de Strata", rid,
                               prompt_tokens_est=prompt_est, context=CFG["context_tokens"])
        stream = bool(clean.get("stream"))
        digest = hashlib.sha256(json.dumps(clean["messages"], ensure_ascii=False).encode()).hexdigest()[:16]
        base = dict(request_id=rid, client=self.client(), model_asked=asked_model, stream=stream,
                    messages=len(clean["messages"]), tools=len(clean.get("tools") or []),
                    prompt_tokens_est=prompt_est, max_tokens=clean["max_tokens"], prompt_sha256=digest,
                    dropped_fields=dropped)
        if CFG["log_prompt_preview"] > 0:
            last = clean["messages"][-1].get("content")
            base["prompt_preview"] = (last if isinstance(last, str) else json.dumps(last))[:CFG["log_prompt_preview"]]

        waited = QUEUE.acquire(CFG["queue_timeout"])
        if waited is None:
            return self.refuse(503, "file d'attente pleine ou délai dépassé : Strata est occupé", rid, **base)
        t0 = time.monotonic()
        status, usage, timings, finish, err = 0, None, None, None, None
        try:
            conn = self.upstream()
            conn.request("POST", "/v1/chat/completions", body=json.dumps(clean).encode(),
                         headers=self.upstream_headers())
            resp = conn.getresponse()
            status = resp.status
            if stream and status == 200:
                usage, timings, finish = self.relay_stream(resp, rid)
            else:
                data = resp.read()
                try:
                    parsed = json.loads(data)
                    usage, timings = parsed.get("usage"), parsed.get("timings")
                    finish = (parsed.get("choices") or [{}])[0].get("finish_reason")
                    if isinstance(parsed, dict) and "model" in parsed:
                        parsed["model"] = CFG["model_id"]
                    data = json.dumps(parsed, ensure_ascii=False).encode()
                except ValueError:
                    pass
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("X-Request-Id", rid)
                self.end_headers()
                self.wfile.write(data)
            conn.close()
        except (OSError, http.client.HTTPException) as exc:
            err = f"{type(exc).__name__}: {exc}"
            status = 502
            try:
                self.send_json(502, {"error": {"message": "Strata injoignable ou trop lent", "type": "upstream_error"}},
                               {"X-Request-Id": rid})
            except OSError:
                pass
        finally:
            QUEUE.release()
            audit(event="chat", status=status, queue_wait_s=round(waited, 2),
                  latency_s=round(time.monotonic() - t0, 2), usage=usage, finish_reason=finish,
                  predicted_per_second=(timings or {}).get("predicted_per_second"),
                  prompt_per_second=(timings or {}).get("prompt_per_second"), error=err, **base)

    def relay_stream(self, resp, rid):
        """Relaye le flux SSE de Strata tel quel, en notant usage/timings au passage."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Transfer-Encoding", "chunked")
        self.send_header("X-Request-Id", rid)
        self.end_headers()
        usage = timings = finish = None
        buf = b""
        while True:
            chunk = resp.read1(65536) if hasattr(resp, "read1") else resp.read(65536)
            if not chunk:
                break
            buf += chunk
            while b"\n\n" in buf:
                event, buf = buf.split(b"\n\n", 1)
                for line in event.split(b"\n"):
                    if line.startswith(b"data: ") and line[6:].strip() != b"[DONE]":
                        try:
                            obj = json.loads(line[6:])
                        except ValueError:
                            continue
                        usage = obj.get("usage") or usage
                        timings = obj.get("timings") or timings
                        ch = (obj.get("choices") or [{}])
                        if ch and ch[0].get("finish_reason"):
                            finish = ch[0]["finish_reason"]
                self.write_chunk(event + b"\n\n")
        if buf:
            self.write_chunk(buf)
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()
        return usage, timings, finish

    def write_chunk(self, data):
        self.wfile.write(f"{len(data):x}\r\n".encode() + data + b"\r\n")
        self.wfile.flush()


def main():
    if len(CFG["api_key"]) < 20:
        print("GW_API_KEY absente ou trop courte (20 caractères min.) : refus de démarrer.", file=sys.stderr)
        sys.exit(2)
    srv = ThreadingHTTPServer((CFG["listen_host"], CFG["listen_port"]), Handler)
    srv.daemon_threads = True
    audit(event="start", listen=f"{CFG['listen_host']}:{CFG['listen_port']}",
          upstream=f"{CFG['upstream_host']}:{CFG['upstream_port']}", model=CFG["model_id"],
          context=CFG["context_tokens"], queue_max=CFG["queue_max"])
    srv.serve_forever()


if __name__ == "__main__":
    main()

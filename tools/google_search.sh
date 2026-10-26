#!/usr/bin/env bash
# @desc 本地 Google 搜索：用本机 Chrome CDP 打开 Google，提取结果正文和外部链接
# @usage tools/google_search.sh "关键词" [count]
# @rule 本地优先；headless 会被 Google 拦，必须用 headful Chrome CDP
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
[ $# -ge 1 ] || { echo "用法: $0 \"关键词\" [count]" >&2; exit 2; }
QUERY="$1"
COUNT="${2:-10}"
PORT="${CDP_PORT:-9222}"

if ! curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
  echo "[google] 启动本地 Chrome CDP..." >&2
  setsid nohup "$DIR/chrome.sh" cdp "$PORT" >/tmp/myagent-google-chrome.log 2>&1 &
  for _ in $(seq 1 20); do
    curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1 && break
    sleep 0.5
  done
fi

if ! curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
  echo "[google] Chrome CDP 启动失败" >&2
  exit 1
fi

set +e
python3 - "$QUERY" "$COUNT" "$PORT" <<'PY'
import json
import sys
import time
import urllib.parse
import urllib.request

import websocket

query, count, port = sys.argv[1], int(sys.argv[2]), sys.argv[3]
url = "https://www.google.com/search?" + urllib.parse.urlencode({
    "q": query,
    "num": max(1, min(count, 30)),
    "hl": "zh-CN",
})

req = urllib.request.Request(f"http://127.0.0.1:{port}/json/new?about:blank", method="PUT")
target = json.load(urllib.request.urlopen(req, timeout=10))
ws = websocket.create_connection(target["webSocketDebuggerUrl"], timeout=20, suppress_origin=True)

def call(mid, method, params=None):
    ws.send(json.dumps({"id": mid, "method": method, "params": params or {}}))
    while True:
        msg = json.loads(ws.recv())
        if msg.get("id") == mid:
            return msg

def evaluate(expr, mid):
    msg = call(mid, "Runtime.evaluate", {"expression": expr, "returnByValue": True})
    return msg.get("result", {}).get("result", {}).get("value")

try:
    call(1, "Page.navigate", {"url": url})
    for _ in range(40):
        time.sleep(0.5)
        ready = evaluate("document.readyState", 100)
        if ready == "complete":
            body = evaluate("document.body ? document.body.innerText : ''", 101) or ""
            if len(body) > 300:
                break

    data = evaluate("""
    (() => {
      const txt = document.body ? document.body.innerText : '';
      const links = Array.from(document.querySelectorAll('a[href^="http"]'))
        .map(a => ({t: (a.innerText || '').trim(), h: a.href}))
        .filter(x => {
          if (!x.t) return false;
          try {
            const h = new URL(x.h).hostname;
            return !/google\\.(com|com\\.hk)|accounts\\.google|support\\.google|policies\\.google/.test(h);
          } catch (e) { return false; }
        });
      return JSON.stringify({txt, links});
    })()
    """, 102)
    parsed = json.loads(data)
    txt = parsed.get("txt", "")
    links = parsed.get("links", [])
finally:
    try:
        urllib.request.urlopen(f"http://127.0.0.1:{port}/json/close/{target['id']}", timeout=5).read()
    except Exception:
        pass
    ws.close()

for marker in ("搜索结果", "AI 概览"):
    i = txt.find(marker)
    if i >= 0:
        txt = txt[i:]
        break
txt = txt.strip()
blocked = any(m in txt for m in (
    "reCAPTCHA", "unusual traffic", "enablejs", "consent.google", "我们的系统检测到"
))
if blocked:
    print("[google] Google 拦截/CAPTCHA", file=sys.stderr)
    sys.exit(3)
if not txt:
    print("[google] 没有提取到结果", file=sys.stderr)
    sys.exit(1)

print(f"[Google] {query}\n")
print(txt[:3500])
if links:
    print("\nLinks:")
    seen = set()
    n = 0
    for x in links:
        key = (x["t"], x["h"])
        if key in seen:
            continue
        seen.add(key)
        print(f"- {x['t']} | {x['h']}")
        n += 1
        if n >= 10:
            break
PY
RC=$?
set -e
if [ "$RC" -eq 3 ]; then
  echo "[google] Google 被拦截，回退 DeepSeek 搜索" >&2
  exec "$DIR/deepseek_search.sh" "$QUERY" "$COUNT"
fi
exit "$RC"

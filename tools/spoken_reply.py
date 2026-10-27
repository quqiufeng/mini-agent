#!/usr/bin/env python3
# @desc 抓取大脑对某条消息的短回复并用本地 TTS 朗读（send.sh 后台调用）
# @usage spoken_reply.py "<发送的文本>" <发送前 epoch_ms>
import os
import re
import subprocess
import sys
import time

import requests

PORT = os.getenv("AGENT_PORT", "4097")
BASE = f"http://127.0.0.1:{PORT}"
LIMIT = int(os.getenv("SPEAK_LIMIT", "40"))
TIMEOUT = float(os.getenv("SPEAK_TIMEOUT", "60"))
MAXLEN = int(os.getenv("SPEAK_MAX", "240"))


def norm(s):
    return re.sub(r"\s+", " ", s or "").strip()


def get(path):
    r = requests.get(BASE + path, timeout=5)
    r.raise_for_status()
    return r.json()


def msg_texts(m):
    return [p.get("text", "") for p in m.get("parts", [])
            if p.get("type") == "text" and p.get("text")]


def find_reply(text, start_ms):
    deadline = time.time() + TIMEOUT
    while time.time() < deadline:
        try:
            sessions = get("/session")
        except Exception:
            time.sleep(0.6)
            continue
        cands = [s for s in sessions
                 if s.get("time", {}).get("updated", 0) >= start_ms - 20000]
        cands.sort(key=lambda s: s.get("time", {}).get("updated", 0), reverse=True)
        for s in cands:
            sid = s.get("id")
            try:
                msgs = get(f"/session/{sid}/message?limit={LIMIT}")
            except Exception:
                continue
            if not isinstance(msgs, list):
                continue
            for i in range(len(msgs) - 1, -1, -1):
                info = msgs[i].get("info", msgs[i])
                if info.get("role") != "user":
                    continue
                if info.get("time", {}).get("created", 0) < start_ms - 10000:
                    continue
                utext = norm(" ".join(msg_texts(msgs[i])))
                if utext != text and text not in utext:
                    continue
                out = []
                for m in msgs[i + 1:]:
                    ai = m.get("info", m)
                    if ai.get("role") != "assistant":
                        continue
                    out.extend(t for t in msg_texts(m) if t.strip())
                if out:
                    return norm(" ".join(out))
        time.sleep(0.6)
    return None


def clean(s):
    s = re.sub(r"```.*?```", "", s, flags=re.S)
    s = re.sub(r"`[^`]*`", "", s)
    s = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", s)
    s = re.sub(r"https?://\S+", "", s)
    s = re.sub(r"[*_#>|]+", "", s)
    s = norm(s)
    s = re.sub(r"^(assistant|回复)[:：]\s*", "", s, flags=re.I)
    return s


def main():
    if len(sys.argv) < 3:
        print("usage: spoken_reply.py <text> <start_ms>", file=sys.stderr)
        return 2
    text = norm(sys.argv[1])
    start_ms = int(sys.argv[2])

    reply = find_reply(text, start_ms)
    if not reply:
        print("[speak] no reply", file=sys.stderr)
        return 1
    reply = clean(reply)
    if not reply:
        print("[speak] empty reply", file=sys.stderr)
        return 0
    if len(reply) > MAXLEN:
        reply = reply[:MAXLEN].rstrip() + "……"
    print(f"[speak] {reply}", file=sys.stderr)
    tts = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tts.sh")
    subprocess.run([tts, reply], check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

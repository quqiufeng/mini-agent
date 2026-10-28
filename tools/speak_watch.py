#!/usr/bin/env python3
# @desc 监听本地大脑会话，把新完成的助手回复用本地 TTS 念出来（语音/文字输入都覆盖）
# @usage tools/speak_watch.py   （start.sh 自动后台启动；单实例由 flock 保证）
import fcntl
import os
import re
import re
import subprocess
import sys
import time

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spoken_reply import clean, msg_texts, norm  # noqa: E402

PORT = os.getenv("AGENT_PORT", "4097")
BASE = f"http://127.0.0.1:{PORT}"
MAXLEN = int(os.getenv("SPEAK_MAX", "240"))
SENTENCE_MAX = int(os.getenv("SPEAK_SENTENCE_MAX", "90"))
STABLE = float(os.getenv("SPEAK_STABLE", "1.5"))
LOCK = "/tmp/myagent-speak-watch.lock"
WANT = "/tmp/myagent_speak_want"
WANT_SEC = float(os.getenv("SPEAK_WANT_SEC", "180"))
TTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tts.sh")


def get(path):
    r = requests.get(BASE + path, timeout=5)
    r.raise_for_status()
    return r.json()


def acquire_lock():
    f = open(LOCK, "w")
    try:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return None
    f.write(str(os.getpid()))
    f.flush()
    return f


def speakable(text):
    text = (text or "").strip()
    if not text:
        return ""
    cut = re.split(r"[。！？!?\n]|：\s*[-*・•]", text, maxsplit=1)[0].strip()
    if not cut:
        return ""
    if len(cut) > SENTENCE_MAX:
        cut = cut[:SENTENCE_MAX].rstrip("，、,;；:：-— ") + "……"
    return cut


def speak(text):
    text = speakable(text)
    if not text:
        return
    if len(text) > MAXLEN:
        text = text[:MAXLEN].rstrip() + "……"
    print(f"[speak-watch] {text}", flush=True)
    try:
        subprocess.run([TTS, text], check=False, timeout=120)
    except Exception as e:
        print(f"[speak-watch] tts error: {e}", flush=True)


def main():
    lock = acquire_lock()
    if not lock:
        print("[speak-watch] already running", flush=True)
        return 0
    started_ms = int(time.time() * 1000)
    pending_key = None
    pending_text = ""
    pending_since = 0.0
    spoken_key = ""
    while True:
        try:
            sessions = get("/session")
            if isinstance(sessions, list) and sessions:
                sessions.sort(key=lambda s: s.get("time", {}).get("updated", 0), reverse=True)
                sid = sessions[0].get("id")
                msgs = get(f"/session/{sid}/message?limit=50")
                if isinstance(msgs, list) and msgs:
                    infos = [m.get("info", m) for m in msgs]
                    last = msgs[-1]
                    info = last.get("info", last)
                    text = norm(clean(" ".join(msg_texts(last))))
                    done = info.get("time", {}).get("completed", 0)
                    key = info.get("id", "")
                    if (info.get("role") == "assistant" and key and text and
                            done >= started_ms and done and key != spoken_key):
                        if key != pending_key or text != pending_text:
                            pending_key, pending_text, pending_since = key, text, time.time()
                        elif time.time() - pending_since >= STABLE:
                            try:
                                want = time.time() - os.path.getmtime(WANT)
                            except OSError:
                                want = 1e9
                            if want <= WANT_SEC:
                                speak(text)
                                spoken_key = key
                                pending_key = None
                                try:
                                    os.unlink(WANT)
                                except OSError:
                                    pass
                            else:
                                pending_key = None
                    else:
                        pending_key = None
        except requests.RequestException:
            pass
        except Exception as e:
            print(f"[speak-watch] {e}", flush=True)
        time.sleep(0.8)


if __name__ == "__main__":
    raise SystemExit(main())

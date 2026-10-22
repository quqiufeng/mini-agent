#!/usr/bin/env bash
# @desc 抓取 USB 麦克风音频频谱流（JSON Lines）
# @usage tools/spectrum.sh [band_count] [fps]
# @rule 默认抓 USB 麦克风，不抓播放 monitor；可用 SPECTRUM_SOURCE 覆盖
# 依赖: parec、python3-numpy
set -euo pipefail

BANDS="${1:-32}"
FPS="${2:-30}"
SRC="${SPECTRUM_SOURCE:-}"
if [ -z "$SRC" ]; then
  SRC="$(pactl list short sources 2>/dev/null | awk '/[Cc]omica|COMICA/ && $2 !~ /\.monitor$/ {print $2; exit}')"
fi
[ -n "$SRC" ] || SRC="@DEFAULT_SOURCE@"

exec python3 - "$SRC" "$BANDS" "$FPS" <<'PY'
import json
import os
import subprocess
import sys
import time

import numpy as np

src, nbands, fps = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
rate = 48000
chunk = 2048
proc = subprocess.Popen(
    ["parec", "--device=" + src, "--format=s16le", "--rate=" + str(rate),
     "--channels=1", "--client-name=myagent-spectrum"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
)

freqs = np.fft.rfftfreq(chunk, 1.0 / rate)
edges = np.geomspace(40, 16000, nbands + 1)
bins = [np.where((freqs >= edges[i]) & (freqs < edges[i + 1]))[0] for i in range(nbands)]
window = np.hanning(chunk)
interval = 1.0 / max(fps, 1.0)
last = 0.0

try:
    while True:
        raw = proc.stdout.read(chunk * 2)
        if not raw or len(raw) < chunk * 2:
            break
        x = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
        spec = np.abs(np.fft.rfft(x * window))
        bands = []
        for idx in bins:
            v = float(spec[idx].mean()) if len(idx) else 0.0
            db = 20.0 * np.log10(v + 1e-9)
            bands.append(round(float(np.clip((db + 80.0) / 80.0, 0.0, 1.0)), 4))
        rms = float(np.sqrt(np.mean(x * x)))
        peak = float(np.max(np.abs(x)))
        out = {
            "ts": round(time.time(), 3),
            "rms": round(rms, 4),
            "peak": round(peak, 4),
            "bands": bands,
        }
        print(json.dumps(out, separators=(",", ":")), flush=True)
        now = time.time()
        dt = now - last
        if dt < interval:
            time.sleep(interval - dt)
        last = time.time()
except (KeyboardInterrupt, BrokenPipeError):
    try:
        sys.stdout = open(os.devnull, "w")
    except Exception:
        pass
finally:
    proc.terminate()
    try:
        proc.wait(timeout=1)
    except Exception:
        proc.kill()
PY

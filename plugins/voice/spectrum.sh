#!/usr/bin/env bash
# @desc 抓取 USB 麦克风音频频谱流（JSON Lines；LuaJIT FFI + FFTW3）
# @usage plugins/voice/spectrum.sh [band_count] [fps]
# @rule 默认抓 USB 麦克风；可用 SPECTRUM_SOURCE 覆盖
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
BANDS="${1:-32}"
FPS="${2:-30}"
[[ "$BANDS" =~ ^[1-9][0-9]*$ ]] && [ "$BANDS" -le 128 ] || { echo "bands 范围 1-128" >&2; exit 2; }
[[ "$FPS" =~ ^[1-9][0-9]*$ ]] && [ "$FPS" -le 60 ] || { echo "fps 范围 1-60" >&2; exit 2; }
SRC="${SPECTRUM_SOURCE:-}"
if [ -z "$SRC" ]; then
    SRC="$(pactl list short sources 2>/dev/null | awk '/[Cc]omica|COMICA/ && $2 !~ /\.monitor$/ {print $2; exit}')"
fi
[ -n "$SRC" ] || SRC="@DEFAULT_SOURCE@"
ROOT="$(cd "$DIR/../.." && pwd)"
exec "$DIR/../../tools/spectrum" "$SRC" "$BANDS" "$FPS"

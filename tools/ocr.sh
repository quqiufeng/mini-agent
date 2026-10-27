#!/usr/bin/env bash
# @desc OCR：本机 PP-OCRv4 优先，失败再回退远程 agentkit OCR
# @usage ocr.sh <图片路径>
# @rule 本地依赖 /opt/WordCard（libocr_simple + 模型）与 /opt/onnxruntime-1.26.0
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
IMG=${1:-}
[ -f "$IMG" ] || { echo "用法: ocr.sh <图片路径>" >&2; exit 2; }

OCR_LIB="${OCR_LIB:-/opt/WordCard/voice/libs/libocr_simple.so}"
OCR_MODELS="${OCR_MODELS:-/opt/WordCard/models/ocr/}"
OCR_ORT="${OCR_ORT:-/opt/onnxruntime-1.26.0/lib/libonnxruntime.so.1}"

if [ "${OCR_LOCAL:-1}" != "0" ] && [ -r "$OCR_LIB" ] && [ -r "$OCR_MODELS/ch_PP-OCRv4_det_infer.onnx" ] && [ -r "$OCR_ORT" ]; then
    OUT="$(LD_LIBRARY_PATH="$(dirname "$OCR_ORT"):${LD_LIBRARY_PATH:-}" \
        OCR_ORT="$OCR_ORT" OCR_LIB="$OCR_LIB" OCR_MODELS="$OCR_MODELS" \
        timeout 90 "$DIR/lua.sh" "$DIR/ocr_local.lua" "$IMG" 2>/tmp/myagent-ocr.log)"
    JSON="$(printf '%s\n' "$OUT" | grep -a '^\[{' | tail -1)"
    if [ -n "$JSON" ]; then
        printf '%s\n' "$JSON"
        exit 0
    fi
    echo "[ocr] 本地识别失败，回退远程" >&2
    tail -3 /tmp/myagent-ocr.log >&2 || true
fi

REMOTE=${OCR_REMOTE:-quqiufeng@192.168.1.10}
TMP="/tmp/ocr_$$_$(basename "$IMG")"
scp -q "$IMG" "$REMOTE:$TMP" || { echo "scp 失败" >&2; exit 1; }
ssh -o BatchMode=yes "$REMOTE" "cd /opt/my-agent && luajit -e 'package.path=package.path..\";./?.lua\"; local ocr=require(\"agentkit.ocr\"); local b=ocr.run(\"$TMP\"); local c=require(\"cjson\"); print(c.encode(b))'" 2>/dev/null | grep -a '^\[{' | tail -1
ssh -o BatchMode=yes "$REMOTE" "rm -f '$TMP'" >/dev/null 2>&1

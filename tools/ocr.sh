#!/usr/bin/env bash
# tools/ocr.sh — 远程 PP-OCRv4 识别本地图片（返回文字和坐标 JSON）
# @desc 调远程 agentkit OCR：scp 图片到 192.168.1.10，返回 JSON 文本框
# @usage ocr.sh <图片路径>
set -uo pipefail
IMG=${1:-}
[ -f "$IMG" ] || { echo "用法: ocr.sh <图片路径>" >&2; exit 2; }

REMOTE=${OCR_REMOTE:-quqiufeng@192.168.1.10}
TMP="/tmp/ocr_$$_$(basename "$IMG")"

scp -q "$IMG" "$REMOTE:$TMP" || { echo "scp 失败" >&2; exit 1; }
ssh -o BatchMode=yes "$REMOTE" "cd /opt/my-agent && luajit -e 'package.path=package.path..\";./?.lua\"; local ocr=require(\"agentkit.ocr\"); local b=ocr.run(\"$TMP\"); local c=require(\"cjson\"); print(c.encode(b))'" 2>/dev/null | grep -a '^\[{' | tail -1
ssh -o BatchMode=yes "$REMOTE" "rm -f '$TMP'" >/dev/null 2>&1

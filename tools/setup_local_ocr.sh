#!/usr/bin/env bash
# @desc 安装本地 OCR：PP-OCRv4 库/模型 + ONNX Runtime 1.26 CPU
# @usage tools/setup_local_ocr.sh
# @rule 需要到 192.168.1.10 的免密 SSH、sudo、curl；目标机需 OpenCV 4 运行库
set -euo pipefail

HOST="${REMOTE_HOST:-quqiufeng@192.168.1.10}"
ORT_DIR=/opt/onnxruntime-1.26.0
ORT_URL="https://github.com/microsoft/onnxruntime/releases/download/v1.26.0/onnxruntime-linux-x64-1.26.0.tgz"

if ! sudo -n true 2>/dev/null; then
    echo "[ocr] sudo 需要密码：请先在终端执行 sudo -v，或直接在终端运行本脚本" >&2
    exit 1
fi

if [ ! -r /opt/WordCard/voice/libs/libocr_simple.so ] || \
   [ ! -r /opt/WordCard/models/ocr/ch_PP-OCRv4_det_infer.onnx ]; then
    echo "[ocr] 从主电脑复制 PP-OCRv4 库和模型 …"
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/models"
    scp -q "$HOST:/opt/WordCard/voice/libs/libocr_simple.so" "$tmp/"
    scp -q "$HOST:/opt/WordCard/models/ocr/"* "$tmp/models/"
    sudo mkdir -p /opt/WordCard/voice/libs /opt/WordCard/models/ocr
    sudo cp -a "$tmp/libocr_simple.so" /opt/WordCard/voice/libs/
    sudo cp -a "$tmp/models/"* /opt/WordCard/models/ocr/
    rm -rf "$tmp"
fi

if [ ! -r "$ORT_DIR/lib/libonnxruntime.so.1" ]; then
    echo "[ocr] 下载 ONNX Runtime 1.26 CPU …"
    tmp="$(mktemp -d)"
    curl -L --fail -o "$tmp/ort.tgz" "$ORT_URL"
    tar xzf "$tmp/ort.tgz" -C "$tmp"
    sudo mkdir -p "$ORT_DIR"
    sudo cp -a "$tmp/onnxruntime-linux-x64-1.26.0/"* "$ORT_DIR/"
    rm -rf "$tmp"
fi

if ! ldconfig -p 2>/dev/null | grep -q 'libopencv_imgcodecs' && \
   ! ls /usr/lib/x86_64-linux-gnu/libopencv_imgcodecs.so.* >/dev/null 2>&1; then
    echo "[ocr] 警告：缺少 OpenCV 4 运行库；Ubuntu 可装 libopencv-imgcodecs-dev" >&2
fi

echo "[ocr] 完成。"
echo "  lib:    /opt/WordCard/voice/libs/libocr_simple.so"
echo "  models: /opt/WordCard/models/ocr/"
echo "  ort:    $ORT_DIR/lib/libonnxruntime.so.1"

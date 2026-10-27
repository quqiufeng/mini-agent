#!/usr/bin/env bash
# @desc 安装本地语音栈：sherpa-onnx(KWS + Kokoro TTS) + SenseVoice.cpp CPU ASR
# @usage tools/setup_local_voice.sh
# @rule 需要到 192.168.1.10 的免密 SSH、sudo、git/cmake/g++/python3；只在首次或升级时运行
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${REMOTE_HOST:-quqiufeng@192.168.1.10}"
SHERPA="${SHERPA_DIR:-/opt/sherpa-onnx}"
SV="${SENSEVOICE_DIR:-/opt/SenseVoice.cpp}"
KWS_NAME=sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01
KWS_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/${KWS_NAME}.tar.bz2"
KOKORO_NAME=kokoro-multi-lang-v1_0

if ! sudo -n true 2>/dev/null; then
    echo "[voice] sudo 需要密码：请先在终端执行 sudo -v，或直接在终端运行本脚本" >&2
    exit 1
fi

if [ ! -r "$SHERPA/lib/libsherpa-onnx-c-api.so" ]; then
    echo "[voice] 安装 sherpa-onnx 运行时 …"
    tmp="$(mktemp -d)"
    scp -q -r "$HOST:/opt/sherpa-onnx/bin" "$HOST:/opt/sherpa-onnx/lib" \
        "$HOST:/opt/sherpa-onnx/include" "$tmp/"
    sudo mkdir -p "$SHERPA"
    sudo cp -a "$tmp/bin" "$tmp/lib" "$tmp/include" "$SHERPA/"
    rm -rf "$tmp"
fi

if [ ! -d "$SHERPA/models/$KWS_NAME" ]; then
    echo "[voice] 下载中文 KWS 模型 …"
    tmp="$(mktemp -d)"
    curl -L --fail -o "$tmp/kws.tar.bz2" "$KWS_URL"
    tar xjf "$tmp/kws.tar.bz2" -C "$tmp"
    sudo mkdir -p "$SHERPA/models"
    sudo cp -a "$tmp/$KWS_NAME" "$SHERPA/models/"
    rm -rf "$tmp"
fi

if [ ! -r "$SHERPA/models/$KOKORO_NAME/model.onnx" ]; then
    echo "[voice] 复制 Kokoro 多语种 TTS 模型 …"
    tmp="$(mktemp -d)"
    scp -q -r "$HOST:/data/models/$KOKORO_NAME" "$tmp/"
    sudo mkdir -p "$SHERPA/models"
    sudo cp -a "$tmp/$KOKORO_NAME" "$SHERPA/models/"
    rm -rf "$tmp"
fi

if [ ! -x "$SV/bin/sense-voice-main" ]; then
    echo "[voice] 编译 SenseVoice.cpp（CPU）…"
    if [ ! -d "$SV/.git" ]; then
        sudo mkdir -p "$SV"
        sudo chown "$(id -u):$(id -g)" "$SV"
        git clone --recursive --depth 1 https://github.com/lovemefan/SenseVoice.cpp.git "$SV"
    fi
    cmake -S "$SV" -B "$SV/build-cpu" -DCMAKE_BUILD_TYPE=Release \
        -DGGML_CUDA=OFF -DGGML_VULKAN=OFF
    cmake --build "$SV/build-cpu" -j"$(nproc)"
    mkdir -p "$SV/bin" "$SV/lib" "$SV/models"
    cp -f "$SV/build-cpu/bin/sense-voice-main" "$SV/bin/"
    cp -a "$SV/build-cpu/lib/libggml"*.so* "$SV/lib/" 2>/dev/null || true
fi

if [ ! -r "$SV/models/sense-voice-small-q4_k.gguf" ]; then
    echo "[voice] 复制 SenseVoice 模型 …"
    mkdir -p "$SV/models"
    scp -q "$HOST:/data/models/sense-voice-small-q4_k.gguf" "$SV/models/"
fi

if ! python3 -c 'import pypinyin' >/dev/null 2>&1; then
    echo "[voice] 安装 python3-pypinyin …"
    sudo apt-get install -y python3-pypinyin
fi

if [ ! -s "$ROOT/gui/kws/keywords.txt" ]; then
    mkdir -p "$ROOT/gui/kws"
    "$ROOT/tools/kws_keywords.py" "你好星期五,星期五,开发者,开发者模式,退出开发者" \
        > "$ROOT/gui/kws/keywords.txt"
fi

echo "[voice] 完成。"
echo "  KWS:    $SHERPA/models/$KWS_NAME"
echo "  Kokoro: $SHERPA/models/$KOKORO_NAME"
echo "  ASR:    $SV/bin/sense-voice-main + $SV/models/sense-voice-small-q4_k.gguf"

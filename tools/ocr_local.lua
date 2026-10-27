#!/usr/bin/env luajit
-- tools/ocr_local.lua — 本机 PP-OCRv4（LuaJIT FFI，无需 cjson）
-- 用法: tools/lua.sh tools/ocr_local.lua <图片>
local ffi = require("ffi")

ffi.cdef[[
typedef struct ocr_simple_t ocr_simple_t;
ocr_simple_t* ocr_simple_create(const char* det, const char* rec, const char* dict);
char*         ocr_simple_run(ocr_simple_t* h, const char* image_path);
void          ocr_simple_free(char* s);
void          ocr_simple_destroy(ocr_simple_t* h);
]]

local ORT = os.getenv("OCR_ORT") or "/opt/onnxruntime-1.26.0/lib/libonnxruntime.so.1"
local LIB = os.getenv("OCR_LIB") or "/opt/WordCard/voice/libs/libocr_simple.so"
local MODELS = os.getenv("OCR_MODELS") or "/opt/WordCard/models/ocr/"

local img = arg[1]
if not img or img == "" then
    io.stderr:write("用法: ocr_local.lua <图片>\n")
    os.exit(2)
end

-- onnxruntime 必须先于 OCR 库载入（全局符号）
pcall(function() ffi.load(ORT, true) end)
local lib = ffi.load(LIB)
local h = lib.ocr_simple_create(
    MODELS .. "ch_PP-OCRv4_det_infer.onnx",
    MODELS .. "ch_PP-OCRv4_rec_infer.onnx",
    MODELS .. "ppocr_keys_v1.txt")
if h == nil then
    io.stderr:write("[ocr] create failed\n")
    os.exit(1)
end

local p = lib.ocr_simple_run(h, img)
if p == nil then
    lib.ocr_simple_destroy(h)
    io.stderr:write("[ocr] run failed\n")
    os.exit(1)
end
print(ffi.string(p))
lib.ocr_simple_free(p)
lib.ocr_simple_destroy(h)

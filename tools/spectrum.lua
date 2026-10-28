#!/usr/bin/env luajit
-- @desc USB 麦克风实时频谱（LuaJIT FFI: parec + FFTW3），输出 JSON Lines
-- @usage tools/spectrum.lua <source> [bands] [fps]
local DIR = (arg[0] or ""):match("^(.*)/") or "."
local ffi = require("ffi")

ffi.cdef[[
typedef struct fftwf_plan_s *fftwf_plan;
fftwf_plan fftwf_plan_dft_r2c_1d(int n, float *in, float *out, unsigned flags);
void fftwf_execute(const fftwf_plan p);
void fftwf_destroy_plan(fftwf_plan p);
struct timespec { long tv_sec; long tv_nsec; };
int clock_gettime(int clk_id, struct timespec *tp);
int usleep(unsigned int usec);
]]
local lib
for _, n in ipairs({ "fftw3f", "libfftw3f.so.3" }) do
    local ok, h = pcall(ffi.load, n)
    if ok then lib = h; break end
end
assert(lib, "无法加载 libfftw3f")

local src = arg[1] or "@DEFAULT_SOURCE@"
local nbands = math.max(1, math.min(128, tonumber(arg[2]) or 32))
local fps = math.max(1, math.min(60, tonumber(arg[3]) or 30))
local rate, chunk = 48000, 2048
local nout = chunk / 2 + 1

local function now_s()
    local ts = ffi.new("struct timespec")
    ffi.C.clock_gettime(0, ts)
    return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) / 1e9
end

local inp = ffi.new("float[?]", chunk)
local out = ffi.new("float[?]", nout * 2)
local plan = lib.fftwf_plan_dft_r2c_1d(chunk, inp, out, 64)
assert(plan ~= nil, "FFTW plan 失败")

local win = ffi.new("float[?]", chunk)
for i = 0, chunk - 1 do
    win[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (chunk - 1))
end

local freqs = {}
for i = 0, nout - 1 do freqs[i] = i * rate / chunk end
local edges = {}
for i = 0, nbands do
    edges[i] = 40 * math.pow(16000 / 40, i / nbands)
end
local bins = {}
for b = 1, nbands do
    local t = {}
    for i = 0, nout - 1 do
        if freqs[i] >= edges[b - 1] and freqs[i] < edges[b] then t[#t + 1] = i end
    end
    bins[b] = t
end

local cmd = os.getenv("SPECTRUM_CMD") or string.format(
    "parec --device=%s --format=s16le --rate=%d --channels=1 --client-name=myagent-spectrum 2>/dev/null",
    src, rate)
local p = io.popen(cmd)
if not p then io.stderr:write("[spectrum] 启动 parec 失败\n"); os.exit(1) end

local interval = 1 / fps
local last = 0
while true do
    local raw = p:read(chunk * 2)
    if not raw or #raw < chunk * 2 then
        io.stderr:write("[spectrum] parec 结束\n")
        break
    end
    local s = ffi.cast("short *", raw)
    local sumsq, peak = 0.0, 0.0
    for i = 0, chunk - 1 do
        local x = s[i] / 32768.0
        sumsq = sumsq + x * x
        local ax = math.abs(x)
        if ax > peak then peak = ax end
        inp[i] = x * win[i]
    end
    lib.fftwf_execute(plan)
    local outb = {}
    for b = 1, nbands do
        local idx = bins[b]
        local v = 0.0
        if #idx > 0 then
            for _, i in ipairs(idx) do
                local re, im = out[2 * i], out[2 * i + 1]
                v = v + math.sqrt(re * re + im * im)
            end
            v = v / #idx
        end
        local db = 20 * math.log10(v + 1e-9)
        local n = (db + 80) / 80
        if n < 0 then n = 0 elseif n > 1 then n = 1 end
        outb[b] = string.format("%.4f", n)
    end
    local rms = math.sqrt(sumsq / chunk)
    print(string.format('{"ts":%.3f,"rms":%.4f,"peak":%.4f,"bands":[%s]}',
        now_s(), rms, peak, table.concat(outb, ",")))
    io.stdout:flush()
    local now = now_s()
    local dt = now - last
    if dt < interval then ffi.C.usleep(math.floor((interval - dt) * 1e6)) end
    last = now_s()
end
lib.fftwf_destroy_plan(plan)
p:close()

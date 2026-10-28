-- ws.lua — 最小 WebSocket 客户端（LuaJIT FFI + libc socket，仅 ws://，供 CDP 用）
local ffi = require("ffi")
local bit = require("bit")
local U = require("util")

ffi.cdef[[
typedef unsigned int socklen_t;
struct sockaddr_in { unsigned short sin_family; unsigned short sin_port; unsigned int sin_addr; char sin_zero[8]; };
struct pollfd { int fd; short events; short revents; };
int socket(int, int, int);
int connect(int, const struct sockaddr *, socklen_t);
long send(int, const void *, unsigned long, int);
long recv(int, void *, unsigned long, int);
int close(int);
int poll(struct pollfd *, unsigned long, int);
unsigned int inet_addr(const char *);
struct timespec { long tv_sec; long tv_nsec; };
int clock_gettime(int, struct timespec *);
]]
local C = ffi.C
local AF_INET, SOCK_STREAM, POLLIN = 2, 1, 1

local M = {}
local WS = {}
WS.__index = WS

local function now_ms()
    local ts = ffi.new("struct timespec")
    C.clock_gettime(0, ts)
    return tonumber(ts.tv_sec) * 1000 + math.floor(tonumber(ts.tv_nsec) / 1e6)
end

local function htons(p)
    return bit.bor(bit.band(bit.lshift(p, 8), 0xff00), bit.rshift(p, 8))
end

function WS:_send_all(data)
    local i, n = 0, #data
    while i < n do
        local sent = C.send(self.fd, data:sub(i + 1), n - i, 0)
        if sent <= 0 then return false end
        i = i + sent
    end
    return true
end

function WS:_read_exact(n, timeout_ms)
    local deadline = now_ms() + (timeout_ms or 20000)
    while #self.buf < n do
        local left = deadline - now_ms()
        if left <= 0 then return nil, "timeout" end
        local pfd = ffi.new("struct pollfd[1]")
        pfd[0].fd = self.fd; pfd[0].events = POLLIN; pfd[0].revents = 0
        local rc = C.poll(pfd, 1, left)
        if rc <= 0 then return nil, "timeout" end
        local tmp = ffi.new("char[8192]")
        local r = C.recv(self.fd, tmp, 8192, 0)
        if r <= 0 then return nil, "closed" end
        self.buf = self.buf .. ffi.string(tmp, r)
    end
    local out = self.buf:sub(1, n)
    self.buf = self.buf:sub(n + 1)
    return out
end

function WS:_frame(opcode, payload)
    local h = { string.char(0x80 + opcode) }
    local n = #payload
    local maskbit = 0x80
    if n < 126 then
        h[#h + 1] = string.char(maskbit + n)
    elseif n < 65536 then
        h[#h + 1] = string.char(maskbit + 126, math.floor(n / 256) % 256, n % 256)
    else
        h[#h + 1] = string.char(maskbit + 127, 0, 0, 0, 0,
            math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
            math.floor(n / 256) % 256, n % 256)
    end
    local mask = {}
    for i = 1, 4 do mask[i] = math.random(0, 255) end
    h[#h + 1] = string.char(mask[1], mask[2], mask[3], mask[4])
    local out = {}
    for i = 1, n do
        out[i] = string.char(bit.bxor(payload:byte(i), mask[(i - 1) % 4 + 1]))
    end
    return table.concat(h) .. table.concat(out)
end

function WS:send_text(s)
    return self:_send_all(self:_frame(1, s))
end

function WS:recv_text(timeout_ms)
    local chunks = {}
    while true do
        local h, err = self:_read_exact(2, timeout_ms)
        if not h then return nil, err end
        local b1, b2 = h:byte(1), h:byte(2)
        local fin = bit.band(b1, 0x80) ~= 0
        local opcode = bit.band(b1, 0x0f)
        local masked = bit.band(b2, 0x80) ~= 0
        local len = bit.band(b2, 0x7f)
        if len == 126 then
            local e = self:_read_exact(2, timeout_ms); if not e then return nil, "eof" end
            len = e:byte(1) * 256 + e:byte(2)
        elseif len == 127 then
            local e = self:_read_exact(8, timeout_ms); if not e then return nil, "eof" end
            len = 0
            for i = 1, 8 do len = len * 256 + e:byte(i) end
        end
        local mask
        if masked then mask = self:_read_exact(4, timeout_ms); if not mask then return nil, "eof" end end
        local payload = len > 0 and self:_read_exact(len, timeout_ms) or ""
        if not payload then return nil, "eof" end
        if masked then
            local out = {}
            for i = 1, #payload do
                out[i] = string.char(bit.bxor(payload:byte(i), mask:byte((i - 1) % 4 + 1)))
            end
            payload = table.concat(out)
        end
        if opcode == 8 then return nil, "closed" end
        if opcode == 9 then
            self:_send_all(self:_frame(10, payload))
        elseif opcode == 1 or opcode == 0 then
            chunks[#chunks + 1] = payload
            if fin then return table.concat(chunks) end
        end
    end
end

function WS:close()
    if self.fd and self.fd >= 0 then
        pcall(function() self:_send_all(self:_frame(8, "")) end)
        C.close(self.fd)
        self.fd = -1
    end
end

function M.connect(url, timeout_ms)
    local host, port, path = tostring(url):match("^ws://([^:/]+):(%d+)(/.*)$")
    if not host then return nil, "bad ws url" end
    local fd = C.socket(AF_INET, SOCK_STREAM, 0)
    if fd < 0 then return nil, "socket failed" end
    local sa = ffi.new("struct sockaddr_in")
    sa.sin_family = AF_INET
    sa.sin_port = htons(tonumber(port))
    sa.sin_addr = C.inet_addr(host)
    if C.connect(fd, ffi.cast("struct sockaddr *", sa), ffi.sizeof(sa)) ~= 0 then
        C.close(fd); return nil, "connect failed"
    end
    math.randomseed(os.time() + math.floor(os.clock() * 1e6))
    local rnd = {}
    for i = 1, 16 do rnd[i] = string.char(math.random(0, 255)) end
    local key = U.base64(table.concat(rnd))
    local req = "GET " .. path .. " HTTP/1.1\r\n" ..
        "Host: " .. host .. ":" .. port .. "\r\n" ..
        "Upgrade: websocket\r\nConnection: Upgrade\r\n" ..
        "Sec-WebSocket-Key: " .. key .. "\r\nSec-WebSocket-Version: 13\r\n\r\n"
    local self = setmetatable({ fd = fd, buf = "" }, WS)
    if not self:_send_all(req) then C.close(fd); return nil, "send failed" end
    local header
    local deadline = now_ms() + (timeout_ms or 10000)
    while true do
        local i = self.buf:find("\r\n\r\n", 1, true)
        if i then header = self.buf:sub(1, i + 3); self.buf = self.buf:sub(i + 4); break end
        if now_ms() > deadline then C.close(fd); return nil, "handshake timeout" end
        local tmp = ffi.new("char[4096]")
        local r = C.recv(fd, tmp, 4096, 0)
        if r <= 0 then C.close(fd); return nil, "handshake closed" end
        self.buf = self.buf .. ffi.string(tmp, r)
    end
    if not header:match("^HTTP/1%.1 101") then C.close(fd); return nil, "handshake failed" end
    return self
end

return M

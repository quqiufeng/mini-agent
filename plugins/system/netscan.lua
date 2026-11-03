#!/usr/bin/env luajit
-- @desc 局域网探测（LuaJIT FFI + libc socket）：UDP 触发 ARP / TCP 端口扫描
-- @usage plugins/system/netscan.sh udp <prefix> (e.g. 192.168.1)
--        plugins/system/netscan.sh tcp <prefix> <port> [timeout_ms]
local ffi = require("ffi")
local bit = require("bit")

ffi.cdef[[
typedef unsigned int socklen_t;
struct sockaddr_in {
    unsigned short sin_family;
    unsigned short sin_port;
    unsigned int sin_addr;
    char sin_zero[8];
};
struct pollfd { int fd; short events; short revents; };
int socket(int domain, int type, int protocol);
int connect(int fd, const struct sockaddr *addr, socklen_t len);
int sendto(int fd, const void *buf, unsigned long len, int flags, const struct sockaddr *addr, socklen_t alen);
int close(int fd);
int fcntl(int fd, int cmd, ...);
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
unsigned int inet_addr(const char *cp);
int getsockopt(int fd, int level, int optname, void *optval, socklen_t *optlen);
struct timespec { long tv_sec; long tv_nsec; };
int clock_gettime(int clk_id, struct timespec *tp);
]]

local C = ffi.C
local AF_INET, SOCK_STREAM, SOCK_DGRAM = 2, 1, 2
local POLLOUT, SOL_SOCKET, SO_ERROR, F_SETFL, O_NONBLOCK = 4, 1, 4, 4, 0x800

local function htons(p)
    return bit.bor(bit.band(bit.lshift(p, 8), 0xff00), bit.rshift(p, 8))
end

local function now_ms()
    local ts = ffi.new("struct timespec")
    C.clock_gettime(0, ts)
    return tonumber(ts.tv_sec) * 1000 + math.floor(tonumber(ts.tv_nsec) / 1e6)
end

local function addr(ip, port)
    local sa = ffi.new("struct sockaddr_in")
    sa.sin_family = AF_INET
    sa.sin_port = htons(port)
    sa.sin_addr = C.inet_addr(ip)
    return sa
end

local mode, prefix, port, timeout = arg[1], arg[2], tonumber(arg[3] or "5555"), tonumber(arg[4] or "250")
if not mode or not prefix then
    io.stderr:write("usage: netscan.sh udp <prefix> | tcp <prefix> <port> [timeout_ms]\n")
    os.exit(2)
end

if mode == "udp" then
    local one = ffi.new("char[1]", 0)
    for i = 1, 254 do
        local ip = prefix .. "." .. i
        local fd = C.socket(AF_INET, SOCK_DGRAM, 0)
        if fd >= 0 then
            local sa = addr(ip, 9)
            C.sendto(fd, one, 1, 0, ffi.cast("struct sockaddr *", sa), ffi.sizeof(sa))
            C.close(fd)
        end
    end
    os.exit(0)
end

if mode == "tcp" then
    local n = 254
    local fds = ffi.new("int[?]", n)
    local pfds = ffi.new("struct pollfd[?]", n)
    for i = 1, n do
        local fd = C.socket(AF_INET, SOCK_STREAM, 0)
        fds[i - 1] = fd
        if fd >= 0 then
            C.fcntl(fd, F_SETFL, ffi.cast("int", O_NONBLOCK))
            local sa = addr(prefix .. "." .. i, port)
            C.connect(fd, ffi.cast("struct sockaddr *", sa), ffi.sizeof(sa))
            pfds[i - 1].fd = fd
            pfds[i - 1].events = POLLOUT
            pfds[i - 1].revents = 0
        else
            pfds[i - 1].fd = -1
        end
    end
    local remaining = n
    local deadline = now_ms() + timeout
    while remaining > 0 do
        local left = deadline - now_ms()
        if left <= 0 then break end
        local rc = C.poll(pfds, n, left)
        if rc <= 0 then break end
        for i = 1, n do
            local fd = fds[i - 1]
            if fd >= 0 and pfds[i - 1].revents ~= 0 then
                local re = pfds[i - 1].revents
                if bit.band(re, POLLOUT) ~= 0 or bit.band(re, 8) ~= 0 or bit.band(re, 16) ~= 0 then
                    local err = ffi.new("int[1]")
                    local len = ffi.new("socklen_t[1]", ffi.sizeof("int"))
                    C.getsockopt(fd, SOL_SOCKET, SO_ERROR, err, len)
                    if err[0] == 0 then print(prefix .. "." .. i) end
                end
                C.close(fd)
                fds[i - 1] = -1
                pfds[i - 1].fd = -1
                pfds[i - 1].revents = 0
                remaining = remaining - 1
            end
        end
    end
    for i = 1, n do
        if fds[i - 1] >= 0 then C.close(fds[i - 1]) end
    end
    os.exit(0)
end

io.stderr:write("unknown mode: " .. mode .. "\n")
os.exit(2)

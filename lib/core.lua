-- lib/core.lua — 本地最小内核：argv/fs/log/proc/dir
-- 新代码禁止 os.execute / io.popen；外部命令统一走 core.exec.argv。
local ffi = require("ffi")
local C = ffi.C

ffi.cdef[[
typedef int pid_t;
typedef unsigned int mode_t;
typedef long ssize_t;
typedef unsigned long size_t;
typedef struct __dirstream DIR;
struct dirent {
    unsigned long d_ino;
    long d_off;
    unsigned short d_reclen;
    unsigned char d_type;
    char d_name[256];
};
DIR *opendir(const char *name);
struct dirent *readdir(DIR *dirp);
int closedir(DIR *dirp);
int mkdir(const char *path, mode_t mode);
int access(const char *path, int mode);
int pipe(int fds[2]);
pid_t fork(void);
pid_t getpid(void);
int dup2(int oldfd, int newfd);
int close(int fd);
int execvp(const char *file, char *const argv[]);
void _exit(int status);
pid_t waitpid(pid_t pid, int *status, int options);
ssize_t read(int fd, void *buf, size_t count);
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
pid_t setsid(void);
int kill(pid_t pid, int sig);
int usleep(unsigned int usec);
int open(const char *path, int flags, mode_t mode);
struct pollfd { int fd; short events; short revents; };
struct timeval { long tv_sec; long tv_usec; };
int gettimeofday(struct timeval *tv, void *tz);
typedef struct { int __allocated; int __used; void *__actions; int __pad[16]; } posix_spawn_file_actions_t;
int posix_spawn_file_actions_init(posix_spawn_file_actions_t *fa);
int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *fa);
int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *fa, int fd);
int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *fa, int fd, int newfd);
int posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *fa,
                 const void *attr, char *const argv[], char *const envp[]);
extern char **environ;
]]

local M = {}

function M.getpid()
    return tonumber(C.getpid())
end

function M.home()
    return os.getenv("HOME") or "/tmp"
end

function M.now()
    return os.time()
end

function M.ms()
    return M.now_ms()
end

function M.now_ms()
    local tv = ffi.new("struct timeval[1]")
    C.gettimeofday(tv, nil)
    return tonumber(tv[0].tv_sec) * 1000 + math.floor(tonumber(tv[0].tv_usec) / 1000)
end

function M.exists(path)
    return C.access(path, 0) == 0
end

function M.which(bin)
    if bin:find("/", 1, true) then return M.exists(bin) and bin or nil end
    local path = os.getenv("PATH") or ""
    for dir in path:gmatch("[^:]+") do
        local p = dir .. "/" .. bin
        if C.access(p, 1) == 0 then return p end
    end
    return nil
end

function M.mkdirp(path)
    if not path or path == "" then return false, "empty path" end
    local cur = path:sub(1, 1) == "/" and "" or "."
    for seg in path:gmatch("[^/]+") do
        cur = cur .. "/" .. seg
        if C.mkdir(cur, 493) ~= 0 and not M.exists(cur) then
            return false, "mkdir failed: " .. cur
        end
    end
    return true
end

function M.read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

function M.write_atomic(path, data)
    local tmp = path .. ".tmp." .. tostring(tonumber(C.getpid()))
    local f = io.open(tmp, "wb")
    if not f then return false, "open " .. tmp end
    f:write(data)
    f:flush()
    f:close()
    local ok, err = os.rename(tmp, path)
    if not ok then os.remove(tmp); return false, err end
    return true
end

function M.append(path, line)
    local f = io.open(path, "ab")
    if not f then return false end
    f:write(line)
    f:write("\n")
    f:close()
    return true
end

function M.log(event, data)
    local dir = M.home() .. "/.myagent"
    M.mkdirp(dir)
    local line = string.format("%d\t%s\t%s", os.time(), tostring(event), tostring(data or ""))
    return M.append(dir .. "/events.log", line)
end

function M.cmdline(pid)
    local s = M.read("/proc/" .. tostring(pid) .. "/cmdline")
    if not s then return nil end
    return (s:gsub("%z", " "))
end

function M.pid_alive(pid)
    return pid and tonumber(pid) and tonumber(pid) > 1 and C.kill(pid, 0) == 0
end

function M.pid_matches(pid, needle)
    if not M.pid_alive(pid) then return false end
    if os.getenv("MYAGENT_SKIP_PID_MATCH") == "1" then return true end
    local cl = M.cmdline(pid)
    return cl ~= nil and cl:find(needle, 1, true) ~= nil
end

function M.list_dir(path)
    local out = {}
    local d = C.opendir(path)
    if d == nil then return out end
    while true do
        local e = C.readdir(d)
        if e == nil then break end
        local name = ffi.string(e.d_name)
        if name ~= "." and name ~= ".." then out[#out + 1] = name end
    end
    C.closedir(d)
    return out
end

local function make_argv(argv)
    local keep = {}
    local cargv = ffi.new("char *[?]", #argv + 1)
    for i, s in ipairs(argv) do
        local buf = ffi.new("char[?]", #s + 1, s)
        keep[#keep + 1] = buf
        cargv[i - 1] = ffi.cast("char *", buf)
    end
    cargv[#argv] = nil
    return cargv, keep
end

function M.exec_argv(argv, opts)
    opts = opts or {}
    local timeout = opts.timeout or 30
    local fds = ffi.new("int[2]")
    if C.pipe(fds) ~= 0 then return nil, "pipe failed", -1 end
    local cargv, keep = make_argv(argv) -- keep alive
    local pid = C.fork()
    if pid == 0 then
        C.close(fds[0])
        C.dup2(fds[1], 1)
        C.dup2(fds[1], 2)
        C.close(fds[1])
        C.execvp(argv[1], cargv)
        C._exit(127)
    end
    C.close(fds[1])
    local pollfd = ffi.new("struct pollfd[1]")
    pollfd[0].fd = fds[0]
    pollfd[0].events = 1 -- POLLIN
    local cap, n = 4096, 0
    local buf = ffi.new("char[?]", cap)
    local deadline = os.time() + timeout
    while true do
        local remain = (deadline - os.time()) * 1000
        if remain <= 0 then break end
        local r = C.poll(pollfd, 1, remain)
        if r <= 0 then break end
        local got = C.read(fds[0], buf + n, cap - n - 1)
        if got <= 0 then break end
        n = n + tonumber(got)
        if n + 512 >= cap then
            cap = cap * 2
            local nb = ffi.new("char[?]", cap)
            ffi.copy(nb, buf, n)
            buf = nb
        end
    end
    C.close(fds[0])
    local st = ffi.new("int[1]")
    C.waitpid(pid, st, 0)
    local status = tonumber(st[0])
    local rc = 128
    if status >= 0 then
        if bit.band(status, 0x7f) == 0 then rc = bit.band(bit.rshift(status, 8), 0xff)
        else rc = 128 + bit.band(status, 0x7f) end
    end
    local out = n > 0 and ffi.string(buf, n) or ""
    return out, nil, rc
end

function M.spawn_argv(argv, opts)
    opts = opts or {}
    local cargv, keep = make_argv(argv)
    local pid = C.fork()
    if pid == 0 then
        C.setsid()
        if opts.log then
            local fd = C.open(opts.log, 1 + 64 + 1024, 420) -- O_WRONLY|O_CREAT|O_APPEND
            if fd >= 0 then C.dup2(fd, 1); C.dup2(fd, 2); C.close(fd) end
        end
        if opts.chdir then
            -- 使用 execvp 前不切目录；需要时由调用方传绝对路径
        end
        C.execvp(argv[1], cargv)
        C._exit(127)
    end
    keep[1] = nil
    return pid
end

function M.exec_stream(argv)
    local fds = ffi.new("int[2]")
    if C.pipe(fds) ~= 0 then return nil, nil, "pipe failed" end
    local cargv, keep = make_argv(argv)
    local pid = C.fork()
    if pid == 0 then
        C.close(fds[0])
        C.dup2(fds[1], 1)
        C.close(fds[1])
        C.execvp(argv[1], cargv)
        C._exit(127)
    end
    C.close(fds[1])
    keep[1] = nil
    return fds[0], pid
end

function M.exec_stream_spawn(argv)
    local fds = ffi.new("int[2]")
    if C.pipe(fds) ~= 0 then return nil, nil, "pipe failed" end
    local cargv, keep = make_argv(argv)
    local fa = ffi.new("posix_spawn_file_actions_t")
    C.posix_spawn_file_actions_init(fa)
    C.posix_spawn_file_actions_addclose(fa, fds[0])
    C.posix_spawn_file_actions_adddup2(fa, fds[1], 1)
    C.posix_spawn_file_actions_addclose(fa, fds[1])
    local pid = ffi.new("pid_t[1]")
    local rc = C.posix_spawnp(pid, argv[1], fa, nil, cargv, C.environ)
    C.posix_spawn_file_actions_destroy(fa)
    C.close(fds[1])
    if rc ~= 0 then C.close(fds[0]); return nil, nil, "spawn failed " .. tostring(rc) end
    keep[1] = nil
    return fds[0], tonumber(pid[0])
end

function M.read_fd(fd, n)
    local buf = ffi.new("char[?]", n)
    local r = C.read(fd, buf, n)
    if r <= 0 then return nil end
    return ffi.string(buf, tonumber(r))
end

function M.close_fd(fd)
    if fd and fd >= 0 then C.close(fd) end
end

function M.kill(pid, sig)
    if pid and tonumber(pid) and tonumber(pid) > 1 then C.kill(pid, sig or 15) end
end

function M.sleep(sec)
    C.usleep(math.floor(sec * 1000000))
end

return M

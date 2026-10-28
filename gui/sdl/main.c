// gui/sdl/main.c — my-agent 语音控制台（SDL2 + SDL2_ttf）
// 常驻采集 USB 麦克风 → 静音切句 → 远程 ASR → 唤醒词门控 → send.sh 转发大脑
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <SDL2/SDL_image.h>
#include <alsa/asoundlib.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <math.h>
#include <ctype.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "lua_embed.h"
#ifdef HAVE_KWS
#include <sherpa-onnx/c-api/c-api.h>
#endif

#define LW 480
#define PW 450
#define W (LW + PW)
#define H 900
#ifndef MYAGENT_ROOT
#define MYAGENT_ROOT "/home/quqiufeng/my-agent"
#endif
#define ROOT MYAGENT_ROOT
#define FONT "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
#define ASR_BIN ROOT "/tools/asr.sh"
#define SEND_BIN ROOT "/send.sh"
#define TUI_BIN ROOT "/tools/dev_tui.sh"
#define TTS_BIN ROOT "/tools/tts.sh"
#define ACK_WAV "/tmp/myagent_ack.wav"
#define ACK_TXT "/tmp/myagent_ack.txt"

static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cv = PTHREAD_COND_INITIALIZER;
static pthread_mutex_t qmu = PTHREAD_MUTEX_INITIALIZER;
static char status[256] = "待唤醒";
static char transcript[16384] = "";
static char pending_wav[8][128];
static int pending_n = 0;
static int paused = 0;
static double active_until = 0;
static volatile double kws_ack_at = 0;
static volatile int kws_woke_pending = 0;
static volatile int kws_dev_pending = 0;
static char kws_woke_word[128] = "";
static int g_kws_ready = 0;
#ifdef HAVE_KWS
static const SherpaOnnxKeywordSpotter *g_kws = NULL;
static const SherpaOnnxOnlineStream *g_kws_stream = NULL;
#endif
static double suppress_until = 0;
static double dev_until = 0;
static int g_always_asr = 1;
static volatile int dev_drop_next_seg = 0;
static int ack_busy = 0;
static int ack_should_play = 0;
static char *run_capture(char *const argv[], int *rc_out);

static SDL_Texture *preview_tex = NULL;
static time_t preview_mtime = 0;

/* ---- embedded LuaJIT: window control and generic Lua runner ---- */
static lua_State *g_lua = NULL;

static void lua_register_embedded_xdo(lua_State *L) {
    if (luaL_loadbuffer(L, (const char *)xdo_lua, xdo_lua_len, "@xdo.lua") != 0) {
        const char *e = lua_tostring(L, -1);
        fprintf(stderr, "[lua] embed xdo: %s\n", e ? e : "error");
        lua_pop(L, 1);
        return;
    }
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");
    lua_pushvalue(L, -3);
    lua_setfield(L, -2, "xdo");
    lua_pop(L, 3);
}

static lua_State *lua_init(int embedded_xdo) {
    lua_State *L = luaL_newstate();
    if (!L) return NULL;
    luaL_openlibs(L);
    if (embedded_xdo) lua_register_embedded_xdo(L);
    return L;
}

static int run_embedded_winctl(const char *cmd, const char *arg2) {
    if (!g_lua && !(g_lua = lua_init(1))) {
        fprintf(stderr, "[lua] cannot create state\n");
        return -1;
    }
    lua_State *L = g_lua;
    lua_createtable(L, 3, 0);
    lua_pushstring(L, "winctl.lua"); lua_rawseti(L, -2, 0);
    lua_pushstring(L, cmd ? cmd : ""); lua_rawseti(L, -2, 1);
    if (arg2) { lua_pushstring(L, arg2); lua_rawseti(L, -2, 2); }
    lua_setglobal(L, "arg");
    if (luaL_loadbuffer(L, (const char *)winctl_lua, winctl_lua_len, "@winctl.lua") != 0
        || lua_pcall(L, 0, 0, 0) != 0) {
        const char *e = lua_tostring(L, -1);
        fprintf(stderr, "[lua] winctl %s: %s\n", cmd ? cmd : "", e ? e : "error");
        lua_pop(L, 1);
        return -1;
    }
    return 0;
}

static int run_lua_cli(int argc, char **argv) {
    if (argc < 1) {
        fprintf(stderr, "usage: %s --lua <script.lua | -e code> [args...]\n", "myagent-voice");
        return 2;
    }
    int is_expr = strcmp(argv[0], "-e") == 0;
    const char *src = is_expr ? (argc > 1 ? argv[1] : NULL) : argv[0];
    if (!src) {
        fprintf(stderr, "usage: %s --lua -e <code> [args...]\n", "myagent-voice");
        return 2;
    }
    int first = is_expr ? 2 : 1;
    lua_State *L = lua_init(0);
    if (!L) return 1;

    if (!is_expr) {
        char dir[4096];
        snprintf(dir, sizeof dir, "%s", argv[0]);
        char *slash = strrchr(dir, '/');
        if (slash) *slash = 0; else snprintf(dir, sizeof dir, ".");
        lua_getglobal(L, "package");
        lua_pushfstring(L, "%s/?.lua;", dir);
        lua_getfield(L, -2, "path");
        lua_concat(L, 2);
        lua_setfield(L, -2, "path");
        lua_pop(L, 1);
    }

    lua_createtable(L, argc - first + 1, 0);
    lua_pushstring(L, src); lua_rawseti(L, -2, 0);
    for (int i = first; i < argc; i++) {
        lua_pushstring(L, argv[i]);
        lua_rawseti(L, -2, i - first + 1);
    }
    lua_setglobal(L, "arg");

    int rc = is_expr ? luaL_loadbuffer(L, src, strlen(src), "=(command line)")
                     : luaL_loadfile(L, src);
    if (rc != 0 || lua_pcall(L, 0, 0, 0) != 0) {
        const char *e = lua_tostring(L, -1);
        fprintf(stderr, "[lua] %s\n", e ? e : "error");
        lua_close(L);
        return 1;
    }
    lua_close(L);
    return 0;
}

static void *preview_after_cmd(void *arg) {
    (void)arg;
    int delays[] = { 2, 6, 12 };
    int prev = 0;
    for (int i = 0; i < 3; i++) {
        struct timespec ts = { delays[i] - prev, 0 };
        nanosleep(&ts, NULL);
        prev = delays[i];
        int r = system(ROOT "/tools/appshot.sh >/dev/null 2>&1");
        (void)r;
    }
    return NULL;
}

static void *preview_once(void *arg) {
    (void)arg;
    struct timespec ts = { 1, 0 };
    nanosleep(&ts, NULL);
    int r = system(ROOT "/tools/appshot.sh >/dev/null 2>&1");
    (void)r;
    return NULL;
}

static void preview_quick(void) {
    pthread_t th;
    pthread_create(&th, NULL, preview_once, NULL);
    pthread_detach(th);
}

static void sync_scrcpy(int wx, int wy) {
    (void)wx; (void)wy;
    run_embedded_winctl("mirror-sync", NULL);
}

static void preview_refresh(void) {
    pthread_t th;
    pthread_create(&th, NULL, preview_after_cmd, NULL);
    pthread_detach(th);
}

static snd_pcm_t *cap_pcm = NULL;
static volatile int cap_stop = 0;
static int cap_started = 0;
static char cap_dev_name[64] = "plughw:Uni,0";
static Sint16 *pcm = NULL;
static size_t pcm_n = 0, pcm_cap = 0;
static char mic_name[128] = "Comica (plughw:Uni,0)";

static double now_s(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec + ts.tv_nsec / 1e9; }

static int wav_write(const char *path, const Sint16 *data, size_t n);

static int tts_playing(void) {
    return access("/tmp/myagent_tts.playing", F_OK) == 0;
}

// 小音箱常驻监视进程（tools/speaker_watch.sh）维护 /tmp/myagent_speaker.state：
// busy <ts> 表示小音箱正在出声，语音入口暂停监听；空闲后自动恢复。
static int speaker_busy(void) {
    FILE *f = fopen("/tmp/myagent_speaker.state", "r");
    if (!f) return 0;
    char st[16] = "";
    long ts = 0;
    int n = fscanf(f, "%15s %ld", st, &ts);
    fclose(f);
    if (n != 2 || strcmp(st, "busy") != 0) return 0;
    time_t now = time(NULL);
    return now >= ts && now - ts <= 3;
}

static void make_beep(void) {
    const int n = 16000 * 12 / 100;
    Sint16 *buf = malloc(sizeof(Sint16) * n);
    if (!buf) return;
    for (int i = 0; i < n; i++) {
        double env = 1.0;
        int edge = 160;
        if (i < edge) env = (double)i / edge;
        else if (i > n - edge) env = (double)(n - i) / edge;
        buf[i] = (Sint16)(7000 * env * sin(2 * M_PI * 880 * i / 16000));
    }
    wav_write("/tmp/myagent_beep.wav", buf, n);
    free(buf);
}

static const char *ack_text(void) {
    const char *v = getenv("VOICE_ACK");
    return (v && *v) ? v : "在的，老板。有什么需要。";
}

static void play_file(const char *p) {
    if (fork() == 0) { execl("/usr/bin/paplay", "paplay", p, (char *)NULL); _exit(1); }
}

static int ack_ready(const char *txt) {
    if (access(ACK_WAV, R_OK) != 0) return 0;
    FILE *f = fopen(ACK_TXT, "r");
    if (!f) return 0;
    char buf[256] = ""; size_t n = fread(buf, 1, sizeof buf - 1, f); fclose(f);
    buf[n] = 0;
    return strcmp(buf, txt) == 0;
}

static void *ack_synth(void *arg) {
    const char *txt = (const char *)arg;
    setenv("TTS_NOPLAY", "1", 1);
    setenv("TTS_LOCAL_OUT", ACK_WAV, 1);
    char *argv[] = { "/usr/bin/timeout", "60", TTS_BIN, (char *)txt, NULL };
    int rc = 0;
    char *out = run_capture(argv, &rc);
    free(out);
    int play = 0;
    pthread_mutex_lock(&mu); play = ack_should_play; ack_should_play = 0; pthread_mutex_unlock(&mu);
    if (rc == 0) {
        FILE *f = fopen(ACK_TXT, "w");
        if (f) { fputs(txt, f); fclose(f); }
        if (play) {
            pthread_mutex_lock(&mu); suppress_until = now_s() + 3.5; pthread_mutex_unlock(&mu);
            play_file(ACK_WAV);
        }
    }
    pthread_mutex_lock(&mu); ack_busy = 0; pthread_mutex_unlock(&mu);
    return NULL;
}

static void ack_speak(int play) {
    const char *txt = ack_text();
    pthread_mutex_lock(&mu);
    if (ack_ready(txt)) {
        if (play) {
            suppress_until = now_s() + 3.5;
            pthread_mutex_unlock(&mu);
            play_file(ACK_WAV);
        } else {
            pthread_mutex_unlock(&mu);
        }
        return;
    }
    if (play) { ack_should_play = 1; suppress_until = now_s() + 12.0; }
    if (ack_busy) { pthread_mutex_unlock(&mu); return; }
    ack_busy = 1;
    pthread_mutex_unlock(&mu);
    pthread_t th;
    pthread_create(&th, NULL, ack_synth, (void *)txt);
    pthread_detach(th);
}

static void set_status(const char *s) {
    pthread_mutex_lock(&mu); snprintf(status, sizeof status, "%s", s); pthread_mutex_unlock(&mu);
}
static void add_line(const char *s) {
    pthread_mutex_lock(&mu);
    size_t len = strlen(transcript);
    snprintf(transcript + len, sizeof(transcript) - len, "%s\n", s);
    pthread_mutex_unlock(&mu);
}


#ifdef HAVE_KWS
static int kws_init(void) {
    const char *dir = getenv("KWS_MODEL_DIR");
    if (!dir || !*dir)
        dir = "/opt/sherpa-onnx/models/sherpa-onnx-kws-zipformer-wenetspeech-3.3M-2024-01-01";
    char enc[4096], dec[4096], joi[4096], tok[4096], kw[4096];
    const char *e = getenv("KWS_ENCODER");
    const char *d = getenv("KWS_DECODER");
    const char *j = getenv("KWS_JOINER");
    const char *t = getenv("KWS_TOKENS");
    const char *k = getenv("KWS_KEYWORDS");
    if (!e || !*e) { snprintf(enc, sizeof enc, "%s/encoder-epoch-99-avg-1-chunk-16-left-64.int8.onnx", dir); e = enc; }
    if (!d || !*d) { snprintf(dec, sizeof dec, "%s/decoder-epoch-99-avg-1-chunk-16-left-64.int8.onnx", dir); d = dec; }
    if (!j || !*j) { snprintf(joi, sizeof joi, "%s/joiner-epoch-99-avg-1-chunk-16-left-64.int8.onnx", dir); j = joi; }
    if (!t || !*t) { snprintf(tok, sizeof tok, "%s/tokens.txt", dir); t = tok; }
    if (!k || !*k) { snprintf(kw, sizeof kw, "%s/gui/kws/keywords.txt", ROOT); k = kw; }
    if (access(e, R_OK) || access(d, R_OK) || access(j, R_OK) || access(t, R_OK) || access(k, R_OK)) {
        fprintf(stderr, "[kws] missing model/keywords (dir=%s, keywords=%s)\n", dir, k);
        return 0;
    }
    SherpaOnnxKeywordSpotterConfig cfg;
    memset(&cfg, 0, sizeof cfg);
    cfg.feat_config.sample_rate = 16000;
    cfg.feat_config.feature_dim = 80;
    cfg.model_config.transducer.encoder = e;
    cfg.model_config.transducer.decoder = d;
    cfg.model_config.transducer.joiner = j;
    cfg.model_config.tokens = t;
    cfg.model_config.num_threads = 1;
    cfg.model_config.provider = "cpu";
    cfg.model_config.model_type = "zipformer2";
    cfg.max_active_paths = 4;
    cfg.num_trailing_blanks = 1;
    const char *score = getenv("KWS_SCORE");
    const char *thr = getenv("KWS_THRESHOLD");
    cfg.keywords_score = score ? (float)atof(score) : 3.0f;
    cfg.keywords_threshold = thr ? (float)atof(thr) : 0.1f;
    cfg.keywords_file = k;
    g_kws = SherpaOnnxCreateKeywordSpotter(&cfg);
    if (!g_kws) { fprintf(stderr, "[kws] create failed\n"); return 0; }
    g_kws_stream = SherpaOnnxCreateKeywordStream(g_kws);
    if (!g_kws_stream) { SherpaOnnxDestroyKeywordSpotter(g_kws); g_kws = NULL; return 0; }
    fprintf(stderr, "[kws] ready: %s\n", k);
    return 1;
}

static void kws_shutdown(void) {
    if (g_kws_stream) { SherpaOnnxDestroyOnlineStream(g_kws_stream); g_kws_stream = NULL; }
    if (g_kws) { SherpaOnnxDestroyKeywordSpotter(g_kws); g_kws = NULL; }
}

static void kws_feed(const Sint16 *samples, size_t n) {
    if (!g_kws_ready || !g_kws_stream || n == 0) return;
    static float buf[1024];
    if (n > sizeof(buf) / sizeof(buf[0])) n = sizeof(buf) / sizeof(buf[0]);
    for (size_t i = 0; i < n; i++) buf[i] = (float)samples[i] / 32768.0f;
    SherpaOnnxOnlineStreamAcceptWaveform(g_kws_stream, 16000, buf, (int32_t)n);
    while (SherpaOnnxIsKeywordStreamReady(g_kws, g_kws_stream))
        SherpaOnnxDecodeKeywordStream(g_kws, g_kws_stream);
    const SherpaOnnxKeywordResult *r = SherpaOnnxGetKeywordResult(g_kws, g_kws_stream);
    if (r && r->keyword && r->keyword[0]) {
        SherpaOnnxResetKeywordStream(g_kws, g_kws_stream);
        double active_ms = 50000;
        const char *v = getenv("VOICE_ACTIVE_MS");
        if (v) active_ms = atof(v);
        active_until = now_s() + active_ms / 1000.0;
        kws_ack_at = now_s();
        snprintf(kws_woke_word, sizeof kws_woke_word, "%s", r->keyword);
        kws_woke_pending = 1;
        if (getenv("VOICE_DEBUG") || getenv("KWS_DEBUG"))
            fprintf(stderr, "[kws] detected: %s\n", r->keyword);
    }
    if (r) SherpaOnnxDestroyKeywordResult(r);
}
#else
static int kws_init(void) { return 0; }
static void kws_shutdown(void) {}
static void kws_feed(const Sint16 *samples, size_t n) { (void)samples; (void)n; }
#endif

static void *cap_thread(void *arg) {
    (void)arg;
    Sint16 buf[320];
    while (!cap_stop && cap_pcm) {
        int r = snd_pcm_readi(cap_pcm, buf, 320);
        if (r == -EPIPE) { snd_pcm_prepare(cap_pcm); continue; }
        if (r < 0) {
            static int logged = 0;
            if (!logged) { fprintf(stderr, "[gui] readi: %s\n", snd_strerror(r)); logged = 1; }
            usleep(5000); continue;
        }
        if (r == 0) continue;
        pthread_mutex_lock(&mu);
        if (pcm_n + (size_t)r > pcm_cap) {
            size_t nc = pcm_cap ? pcm_cap * 2 : 65536;
            while (nc < pcm_n + (size_t)r) nc *= 2;
            Sint16 *np = realloc(pcm, nc * sizeof(Sint16));
            if (np) { pcm = np; pcm_cap = nc; }
        }
        if (pcm_n + (size_t)r <= pcm_cap) {
            memcpy(pcm + pcm_n, buf, (size_t)r * sizeof(Sint16));
            pcm_n += (size_t)r;
        }
        pthread_mutex_unlock(&mu);
        if (!paused && !tts_playing() && !speaker_busy()) kws_feed(buf, (size_t)r);
        static int reads = 0;
        if (getenv("VOICE_DEBUG") && ++reads % 100 == 0)
            fprintf(stderr, "[gui] reads=%d pcm_n=%zu\n", reads, pcm_n);
    }
    return NULL;
}

static void open_capture(void) {
    if (cap_pcm) { cap_stop = 1; snd_pcm_close(cap_pcm); cap_pcm = NULL; }
    int rc = snd_pcm_open(&cap_pcm, cap_dev_name, SND_PCM_STREAM_CAPTURE, 0);
    if (rc < 0) { set_status(snd_strerror(rc)); return; }
    rc = snd_pcm_set_params(cap_pcm, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED,
                            1, 16000, 1, 50000);
    if (rc < 0) { fprintf(stderr, "[gui] set_params: %s\n", snd_strerror(rc)); snd_pcm_close(cap_pcm); cap_pcm = NULL; set_status("ALSA 参数失败"); return; }
    cap_stop = 0;
    pthread_t th;
    pthread_create(&th, NULL, cap_thread, NULL);
    pthread_detach(th);
    cap_started = 1;
    fprintf(stderr, "[gui] capture: %s S16_LE 16000 1ch\n", cap_dev_name);
}

static int wav_write(const char *path, const Sint16 *data, size_t n) {
    FILE *f = fopen(path, "wb");
    if (!f) return -1;
    Uint32 rate = 16000;
    Uint32 bytes = (Uint32)(n * 2);
    Uint16 ch = 1, bits = 16, align = 2;
    Uint32 br = rate * align;
    fwrite("RIFF", 1, 4, f); Uint32 riff = 36 + bytes; fwrite(&riff, 4, 1, f);
    fwrite("WAVEfmt ", 1, 8, f); Uint32 fmt = 16; fwrite(&fmt, 4, 1, f);
    Uint16 pcmf = 1; fwrite(&pcmf, 2, 1, f); fwrite(&ch, 2, 1, f);
    fwrite(&rate, 4, 1, f); fwrite(&br, 4, 1, f);
    fwrite(&align, 2, 1, f); fwrite(&bits, 2, 1, f);
    fwrite("data", 1, 4, f); fwrite(&bytes, 4, 1, f);
    fwrite(data, 2, n, f); fclose(f); return 0;
}

static char *run_capture(char *const argv[], int *rc_out) {
    int p[2];
    if (pipe(p) != 0) return NULL;
    pid_t pid = fork();
    if (pid == 0) {
        setpgid(0, 0);
        dup2(p[1], 1); dup2(p[1], 2); close(p[0]); close(p[1]);
        execv(argv[0], argv); _exit(127);
    }
    setpgid(pid, pid);
    close(p[1]);
    size_t cap = 4096, n = 0; char *buf = malloc(cap);
    struct pollfd pfd = { p[0], POLLIN, 0 };
    time_t deadline = time(NULL) + 35;
    while (1) {
        int remain = (int)(deadline - time(NULL)) * 1000;
        if (remain <= 0) break;
        int pr = poll(&pfd, 1, remain);
        if (pr <= 0) break;
        ssize_t r = read(p[0], buf + n, cap - n - 1);
        if (r <= 0) break;
        n += (size_t)r;
        if (n + 1 >= cap) { cap *= 2; buf = realloc(buf, cap); }
    }
    close(p[0]);
    kill(-pid, SIGKILL);
    int st = 0; waitpid(pid, &st, 0); buf[n] = 0;
    if (rc_out) *rc_out = WIFEXITED(st) ? WEXITSTATUS(st) : -1;
    return buf;
}

static int ci_prefix(const char *s, const char *pre) {
    for (; *pre; pre++, s++) {
        if (!*s || tolower((unsigned char)*s) != tolower((unsigned char)*pre)) return 0;
    }
    return 1;
}

static const char *dev_after(const char *p) {
    static const char *V[] = {"开发者模式", "开发者", "开发模式", "程序员", "开发",
                              "调试模式", "调试", "dev模式", "deve", "dave", "dve",
                              "dev", "deb", "def", "戴夫", "迪夫", "得夫"};
    for (size_t i = 0; i < sizeof(V)/sizeof(V[0]); i++) {
        size_t l = strlen(V[i]);
        int hit = 1;
        for (size_t k = 0; k < l; k++) {
            unsigned char a = (unsigned char)p[k], b = (unsigned char)V[i][k];
            if (!a || (a < 128 && b < 128 ? tolower(a) != tolower(b) : a != b)) { hit = 0; break; }
        }
        if (hit) return p + l;
    }
    return NULL;
}

static void normalize(const char *in, char *out, size_t osz) {
    size_t j = 0;
    for (size_t i = 0; in[i] && j + 1 < osz; i++) {
        unsigned char c = in[i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') continue;
        if (c == ',' || c == '.' || c == '!' || c == '?' || c == ';' || c == ':') continue;
        if (c == 0xe3 && (unsigned char)in[i+1] == 0x80) { i += 2; continue; } // 全角标点
        out[j++] = in[i];
    }
    out[j] = 0;
}

static int strip_wake(const char *text, char *rest, size_t rsz) {
    const char *wake = getenv("VOICE_WAKE");
    if (!wake) wake = "你好星期五,星期五";
    char norm[1024]; normalize(text, norm, sizeof norm);
    char list[512]; snprintf(list, sizeof list, "%s", wake);
    char *save = NULL;
    for (char *tok = strtok_r(list, ",", &save); tok; tok = strtok_r(NULL, ",", &save)) {
        char w[128]; normalize(tok, w, sizeof w);
        char *pos = strstr(norm, w);
        if (pos) {
            snprintf(rest, rsz, "%s", pos + strlen(w));
            return 1;
        }
    }
    rest[0] = 0; return 0;
}

static void *worker(void *arg) {
    (void)arg;
    for (;;) {
        char path[128] = "";
        pthread_mutex_lock(&qmu);
        while (pending_n == 0) pthread_cond_wait(&cv, &qmu);
        snprintf(path, sizeof path, "%s", pending_wav[0]);
        for (int i = 1; i < pending_n; i++) snprintf(pending_wav[i-1], sizeof pending_wav[i-1], "%s", pending_wav[i]);
        pending_n--;
        pthread_mutex_unlock(&qmu);

        set_status("识别中 …");
        if (getenv("VOICE_DEBUG")) fprintf(stderr, "[gui] w: asr-start %s\n", path);
        if (getenv("VOICE_DEBUG")) { char cp[256]; snprintf(cp, sizeof cp, "cp -f '%s' /tmp/myagent_last.wav", path); int _r = system(cp); (void)_r; }
        char *argv[] = { "/usr/bin/timeout", "30", ASR_BIN, path, NULL };
        int rc = 0; char *out = run_capture(argv, &rc);
        char text[1024] = "";
        if (out) {
            char *save = NULL, *line = strtok_r(out, "\n", &save), *last = NULL;
            while (line) {
                // 跳过诊断行（远程回退会打印 "[voice] 未识别到内容" 等），避免当成指令转发
                if (*line && strncmp(line, "[asr]", 5) != 0 && strncmp(line, "[voice]", 7) != 0)
                    last = line;
                line = strtok_r(NULL, "\n", &save);
            }
            if (last) snprintf(text, sizeof text, "%s", last);
            free(out);
        }
        unlink(path);
        if (getenv("VOICE_DEBUG")) fprintf(stderr, "[gui] w: asr-done rc=%d text=%s\n", rc, text);
        char norm[1024]; normalize(text, norm, sizeof norm);
        if (getenv("VOICE_DEBUG")) fprintf(stderr, "[gui] asr=%s\n", text);
        // asr.sh 有时识别出文字但退出码非 0，有文字就继续处理
        if (!*norm) { set_status(active_until > now_s() ? "已唤醒 · 在听" : "待唤醒"); continue; }

        char rest[1024];
        int woke = strip_wake(text, rest, sizeof rest);
        int kws_recent = (kws_ack_at > 0 && now_s() - kws_ack_at < 8.0);

        // 开发模式（简化）：说「程序员」进入 3 分钟窗口；窗口内的话原样进 TUI
        {
            static double dev_ms = 0;
            if (dev_ms <= 0) { const char *v = getenv("VOICE_DEV_ACTIVE_MS"); dev_ms = v ? atof(v) : 180000; }
            static const char *DEVL[] = {"开发者模式", "开发模式", "开发者"};
            static const char *LEAD[] = {"请", "帮我", "我要", "我想", "现在", "马上", "开始",
                                         "进入", "打开", "开启", "启动", "切换", "切到", "调到", "唤醒"};
            char cand[1024];
            snprintf(cand, sizeof cand, "%s", woke ? rest : norm);
            const char *p = cand;
            for (;;) {
                int ch = 0;
                for (size_t i = 0; i < sizeof(LEAD)/sizeof(LEAD[0]); i++) {
                    size_t l = strlen(LEAD[i]);
                    if (strncmp(p, LEAD[i], l) == 0) { p += l; ch = 1; break; }
                }
                if (!ch) break;
            }
            const char *after = dev_after(p);
            int dev_out = 0;
            if (after) {
                const char *q = after;
                while (*q == ' ') q++;
                if (ci_prefix(q, "out") || ci_prefix(q, "出去") || strstr(p, "退出")) dev_out = 1;
            }
            if (!dev_out && strstr(p, "退出") &&
                (strstr(p, "程序员") || strstr(p, "调试") || strstr(p, "开发者") ||
                 strstr(p, "开发") || strstr(p, "戴夫"))) {
                dev_out = 1;
                after = p + strlen(p);
            }
            if (dev_out) {
                dev_until = 0;
                add_line("● 退出开发模式");
                char *xargv[] = { "/usr/bin/timeout", "12", TUI_BIN, "stop", NULL };
                int xrc = 0; char *xout = run_capture(xargv, &xrc); free(xout);
                set_status("待唤醒");
                continue;
            }
            if (!after) {
                for (size_t i = 0; i < sizeof(DEVL)/sizeof(DEVL[0]); i++) {
                    size_t l = strlen(DEVL[i]);
                    if (strncmp(p, DEVL[i], l) == 0) { after = p + l; break; }
                }
            }
            if (after) {
                dev_until = now_s() + dev_ms / 1000.0;
                if (*after) {
                    char line[1100]; snprintf(line, sizeof line, "开发: %s", after);
                    add_line(line);
                    set_status("开发模式 → TUI");
                    if (getenv("VOICE_DEBUG")) fprintf(stderr, "[gui] w: tui-start %s\n", after);
                    char *targv[] = { "/usr/bin/timeout", "20", TUI_BIN, "type", (char *)after, NULL };
                    int trc = 0; char *tout = run_capture(targv, &trc); free(tout);
                    if (getenv("VOICE_DEBUG")) fprintf(stderr, "[gui] w: tui-done rc=%d\n", trc);
                    set_status(trc == 0 ? "已输入 TUI" : "TUI 输入失败");
                    preview_refresh();
                } else {
                    char *sargv[] = { "/usr/bin/timeout", "20", TUI_BIN, "start", NULL };
                    int src = 0; char *sout = run_capture(sargv, &src); free(sout);
                    set_status(src == 0 ? "开发模式 · 请说指令" : "dev TUI 启动失败");
                }
                continue;
            }
            if (now_s() < dev_until) {
                dev_until = now_s() + dev_ms / 1000.0;
                char line[1100]; snprintf(line, sizeof line, "开发: %s", cand);
                add_line(line);
                set_status("开发模式 → TUI");
                char *targv[] = { "/usr/bin/timeout", "20", TUI_BIN, "type", cand, NULL };
                int trc = 0; char *tout = run_capture(targv, &trc); free(tout);
                set_status(trc == 0 ? "已输入 TUI" : "TUI 输入失败");
                preview_refresh();
                continue;
            }
        }
        static double active_ms = 0;
        if (active_ms <= 0) { const char *v = getenv("VOICE_ACTIVE_MS"); active_ms = v ? atof(v) : 50000; }
        if (woke) {
            active_until = now_s() + active_ms / 1000.0;
            if (!kws_recent) { add_line("● 唤醒"); ack_speak(1); }
            if (!rest[0]) { set_status("已唤醒 · 在听"); continue; }
            char line[1100]; snprintf(line, sizeof line, "我: %s", rest);
            add_line(line);
            char *sargv[] = { "/usr/bin/timeout", "30", SEND_BIN, rest, NULL };
            int src = -1;
            for (int i = 1; i <= 3; i++) {
                char *sout = run_capture(sargv, &src); free(sout);
                if (src == 0) break;
                set_status("大脑忙，重试 …"); sleep(3);
            }
            set_status(src == 0 ? "已唤醒 · 已发送" : "发送失败");
            continue;
        }

        if (active_until > now_s() || dev_until > now_s()) {
            if (active_until > now_s()) active_until = now_s() + active_ms / 1000.0;
            char line[1100]; snprintf(line, sizeof line, "我: %s", text);
            add_line(line);
            set_status("识别: 已发送");
            char *sargv[] = { "/usr/bin/timeout", "30", SEND_BIN, text, NULL };
            int src = -1;
            for (int i = 1; i <= 3; i++) {
                char *sout = run_capture(sargv, &src); free(sout);
                if (src == 0) break;
                set_status("大脑忙，重试 …"); sleep(3);
            }
            set_status(src == 0 ? "已发送" : "发送失败");
        } else {
            char line[1100]; snprintf(line, sizeof line, "（未唤醒）%s", text);
            add_line(line);
            set_status("待唤醒");
        }
    }
    return NULL;
}

static void enqueue_segment(const Sint16 *data, size_t n) {
    static int seq = 0;
    char path[128];
    snprintf(path, sizeof path, "/tmp/myagent_seg_%d_%d.wav", (int)getpid(), seq++);
    if (wav_write(path, data, n) != 0) return;
    pthread_mutex_lock(&qmu);
    if (pending_n < 8) { snprintf(pending_wav[pending_n], sizeof pending_wav[0], "%s", path); pending_n++; pthread_cond_signal(&cv); }
    pthread_mutex_unlock(&qmu);
}

static void cycle_mic(void) {
    if (strcmp(cap_dev_name, "plughw:Uni,0") == 0) {
        snprintf(cap_dev_name, sizeof cap_dev_name, "default");
        snprintf(mic_name, sizeof mic_name, "系统默认输入");
    } else {
        snprintf(cap_dev_name, sizeof cap_dev_name, "plughw:Uni,0");
        snprintf(mic_name, sizeof mic_name, "Comica (plughw:Uni,0)");
    }
    open_capture();
}

static void text(SDL_Renderer *r, TTF_Font *f, const char *s, int x, int y, SDL_Color c) {
    if (!s || !*s) return;
    SDL_Surface *surf = TTF_RenderUTF8_Blended(f, s, c);
    if (!surf) return;
    SDL_Texture *tex = SDL_CreateTextureFromSurface(r, surf);
    SDL_Rect dst = { x, y, surf->w, surf->h };
    SDL_RenderCopy(r, tex, NULL, &dst);
    SDL_DestroyTexture(tex); SDL_FreeSurface(surf);
}

int main(int argc, char **argv) {
    if (argc >= 2 && strcmp(argv[1], "--winctl") == 0)
        return run_embedded_winctl(argc >= 3 ? argv[2] : "", argc >= 4 ? argv[3] : NULL) == 0 ? 0 : 1;
    if (argc >= 2 && strcmp(argv[1], "--lua") == 0)
        return run_lua_cli(argc - 2, argv + 2);
    if (!getenv("VOICE_SPEAK_REPLY") || strcmp(getenv("VOICE_SPEAK_REPLY"), "0") != 0)
        setenv("SPEAK_REPLY", "1", 1);
    if (SDL_Init(SDL_INIT_VIDEO) != 0) { fprintf(stderr, "SDL_Init: %s\n", SDL_GetError()); return 1; }
    if (TTF_Init() != 0) { fprintf(stderr, "TTF_Init: %s\n", TTF_GetError()); return 1; }
    IMG_Init(IMG_INIT_PNG);
    unlink("/tmp/myagent_mirror.id");
    SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "2");
    if (chdir(ROOT) != 0) {}
    SDL_Window *win = SDL_CreateWindow("ai助手", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, W, H, SDL_WINDOW_SHOWN);
    {
        SDL_RWops *rw = SDL_RWFromConstMem(icon_png, icon_png_len);
        if (rw) {
            SDL_Surface *ic = IMG_Load_RW(rw, 1);
            if (ic) { SDL_SetWindowIcon(win, ic); SDL_FreeSurface(ic); }
        }
    }
    SDL_Renderer *ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!ren) ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_SOFTWARE);
    TTF_Font *font = TTF_OpenFontIndex(FONT, 20, 0);
    TTF_Font *small = TTF_OpenFontIndex(FONT, 15, 0);
    TTF_Font *big = TTF_OpenFontIndex(FONT, 30, 0);
    if (!font || !small || !big) return 1;

    g_kws_ready = kws_init();
    if (getenv("VOICE_DEBUG") || getenv("KWS_DEBUG"))
        fprintf(stderr, "[kws] state=%s\n", g_kws_ready ? "on" : "off");
    {
        const char *v = getenv("VOICE_ALWAYS_ASR");
        if (v) g_always_asr = atoi(v) != 0;
    }
    open_capture();
    make_beep();
    // 大脑没起就先拉起来（start.sh 会开显式终端）
    if (system("curl --max-time 1 -sf http://127.0.0.1:4097/global/health >/dev/null 2>&1") != 0) {
        set_status("大脑启动中 …");
        if (fork() == 0) { execl(ROOT "/start.sh", "start.sh", NULL); _exit(1); }
    }
    pthread_t th; pthread_create(&th, NULL, worker, NULL); pthread_detach(th);
    ack_speak(0);

    int running = 1, recording = 0, quiet = 0, proc_pos = 0;
    int dragging = 0, drag_dx = 0, drag_dy = 0;
    int drag_hidden = 0; Uint32 last_move_tick = 0;
    double speech_rms = 0; char input[512] = "";
    SDL_Event e;
    SDL_Rect micbtn = { LW - 110, 96, 90, 30 };
    SDL_Rect pausebtn = { 40, H - 44, 130, 32 };
    SDL_Rect bvoldown = { 40, H - 196, 196, 36 };
    SDL_Rect bvolup = { 244, H - 196, 196, 36 };
    SDL_Rect bprev = { 40, H - 150, 120, 36 };
    SDL_Rect bplay = { 172, H - 150, 136, 36 };
    SDL_Rect bnext = { 320, H - 150, 120, 36 };
    size_t seg_start = 0;

    while (running) {
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT) running = 0;
            else if (e.type == SDL_WINDOWEVENT) {
                if (e.window.event == SDL_WINDOWEVENT_MOVED) {
                    run_embedded_winctl("mirror-hide", NULL);
                    drag_hidden = 1;
                    last_move_tick = SDL_GetTicks();
                } else if (e.window.event == SDL_WINDOWEVENT_MINIMIZED || e.window.event == SDL_WINDOWEVENT_HIDDEN) {
                    run_embedded_winctl("mirror-hide", NULL);
                } else if (e.window.event == SDL_WINDOWEVENT_RESTORED || e.window.event == SDL_WINDOWEVENT_SHOWN) {
                    int wx = 0, wy = 0; SDL_GetWindowPosition(win, &wx, &wy);
                    run_embedded_winctl("mirror-show", NULL);
                    sync_scrcpy(wx, wy);
                }
            }
            else if (e.type == SDL_KEYDOWN) {
                if (e.key.keysym.sym == SDLK_ESCAPE) running = 0;
                else if (e.key.keysym.sym == SDLK_BACKSPACE) { size_t l = strlen(input); if (l) input[l-1] = 0; }
                else if (e.key.keysym.sym == SDLK_RETURN && *input) {
                    char line[600]; snprintf(line, sizeof line, "我: %s", input); add_line(line);
                    set_status("发送中 …");
                    char *sargv[] = { "/usr/bin/timeout", "30", SEND_BIN, input, NULL };
                    int rc = -1; for (int i = 1; i <= 3; i++) { char *o = run_capture(sargv, &rc); free(o); if (!rc) break; sleep(3); }
                    set_status(rc == 0 ? "已发送" : "发送失败");
                    preview_refresh();
                    input[0] = 0;
                }
            } else if (e.type == SDL_TEXTINPUT) {
                size_t l = strlen(input), a = strlen(e.text.text);
                if (l + a < sizeof(input) - 1) strcat(input, e.text.text);
            } else if (e.type == SDL_MOUSEBUTTONDOWN && e.button.button == SDL_BUTTON_LEFT) {
                int x = e.button.x, y = e.button.y;
                if (y < 92 && x < LW) {
                    int gx = 0, gy = 0, wx = 0, wy = 0;
                    SDL_GetGlobalMouseState(&gx, &gy);
                    SDL_GetWindowPosition(win, &wx, &wy);
                    drag_dx = gx - wx; drag_dy = gy - wy;
                    dragging = 1;
                } else if (x >= micbtn.x && x <= micbtn.x + micbtn.w && y >= micbtn.y && y <= micbtn.y + micbtn.h) cycle_mic();
                else if (x >= pausebtn.x && x <= pausebtn.x + pausebtn.w && y >= pausebtn.y && y <= pausebtn.y + pausebtn.h) {
                    paused = !paused; set_status(paused ? "已暂停" : (speaker_busy() ? "播放中 · 暂停监听" : "待唤醒"));
                } else if (x >= bvoldown.x && x <= bvoldown.x + bvoldown.w && y >= bvoldown.y && y <= bvoldown.y + bvoldown.h) {
                    if (fork() == 0) { setenv("VOLUME_NO_TV", "1", 1); execl(ROOT "/tools/volume.sh", "volume.sh", "down", (char *)NULL); _exit(1); }
                    set_status("音量 -");
                } else if (x >= bvolup.x && x <= bvolup.x + bvolup.w && y >= bvolup.y && y <= bvolup.y + bvolup.h) {
                    if (fork() == 0) { setenv("VOLUME_NO_TV", "1", 1); execl(ROOT "/tools/volume.sh", "volume.sh", "up", (char *)NULL); _exit(1); }
                    set_status("音量 +");
                } else if (x >= bprev.x && x <= bprev.x + bprev.w && y >= bprev.y && y <= bprev.y + bprev.h) {
                    if (fork() == 0) { execl(ROOT "/tools/phone_media.sh", "phone_media.sh", "prev", (char *)NULL); _exit(1); }
                    set_status("上一首"); preview_quick();
                } else if (x >= bplay.x && x <= bplay.x + bplay.w && y >= bplay.y && y <= bplay.y + bplay.h) {
                    if (fork() == 0) { execl(ROOT "/tools/phone_media.sh", "phone_media.sh", "playpause", (char *)NULL); _exit(1); }
                    set_status("播放/暂停"); preview_quick();
                } else if (x >= bnext.x && x <= bnext.x + bnext.w && y >= bnext.y && y <= bnext.y + bnext.h) {
                    if (fork() == 0) { execl(ROOT "/tools/phone_media.sh", "phone_media.sh", "next", (char *)NULL); _exit(1); }
                    set_status("下一首"); preview_quick();
                }
            } else if (e.type == SDL_MOUSEBUTTONUP && e.button.button == SDL_BUTTON_LEFT) {
                dragging = 0;
            } else if (e.type == SDL_MOUSEMOTION && dragging && (e.motion.state & SDL_BUTTON_LMASK)) {
                int gx = 0, gy = 0;
                SDL_GetGlobalMouseState(&gx, &gy);
                SDL_SetWindowPosition(win, gx - drag_dx, gy - drag_dy);
            }
        }

        if (kws_woke_pending) {
            kws_woke_pending = 0;
            char line[220];
            snprintf(line, sizeof line, "● 唤醒（本地）：%s", kws_woke_word);
            add_line(line);
            set_status("已唤醒 · 在听");
            // 开发者/退出开发者本身就是命令，KWS 命中即执行，不等 ASR
            if ((strstr(kws_woke_word, "退出") &&
                 (strstr(kws_woke_word, "程序员") || strstr(kws_woke_word, "开发") ||
                  strstr(kws_woke_word, "调试"))) ||
                strstr(kws_woke_word, "dev-out") || strstr(kws_woke_word, "dev out"))
                kws_dev_pending = -1;
            else if (strstr(kws_woke_word, "程序员") || strstr(kws_woke_word, "开发模式") ||
                     strstr(kws_woke_word, "开发") || strstr(kws_woke_word, "调试") ||
                     strstr(kws_woke_word, "dev") || strstr(kws_woke_word, "戴夫"))
                kws_dev_pending = 1;
            // 唤醒词和指令常连在一起说：保留正在录的音频；没在录就回退 0.5s 预录
            if (!recording) {
                size_t pre = 8000;
                seg_start = proc_pos > pre ? proc_pos - pre : 0;
                play_file("/tmp/myagent_beep.wav");
                suppress_until = now_s() + 0.15;
            }
        }
        if (kws_dev_pending) {
            int entering = kws_dev_pending > 0;
            kws_dev_pending = 0;
            double dev_ms = 180000;
            const char *dv = getenv("VOICE_DEV_ACTIVE_MS");
            if (dv) dev_ms = atof(dv);
            if (!entering) {
                dev_until = 0;
                add_line("● 退出开发模式");
                char *xargv[] = { "/usr/bin/timeout", "12", TUI_BIN, "stop", NULL };
                int xrc = 0; char *xout = run_capture(xargv, &xrc); free(xout);
                set_status("待唤醒");
            } else {
                dev_until = now_s() + dev_ms / 1000.0;
                dev_drop_next_seg = 1;
                add_line("● 开发模式（本地）→ TUI");
                char *sargv[] = { "/usr/bin/timeout", "20", TUI_BIN, "start", NULL };
                int src = 0; char *sout = run_capture(sargv, &src); free(sout);
                set_status(src == 0 ? "开发模式 · 请说指令" : "dev TUI 启动失败");
            }
        }
        static int ui_awake = 0;
        if (active_until > now_s() || dev_until > now_s()) ui_awake = 1;
        else if (ui_awake) { ui_awake = 0; set_status("待唤醒"); }

        static int spk_was = -1;
        int spk = speaker_busy();
        if (spk != spk_was) {
            spk_was = spk;
            if (!paused) set_status(spk ? "播放中 · 暂停监听"
                                        : (active_until > now_s() ? "已唤醒 · 在听" : "待唤醒"));
        }

        if (cap_started) {
            pthread_mutex_lock(&mu);
            size_t total = pcm_n;
            if (total > (size_t)proc_pos) {
                const Sint16 *d = pcm + proc_pos;
                size_t cnt = total - proc_pos;
                const int CH = 320; // 20ms @16k
                for (size_t i = 0; i + CH <= cnt; i += CH) {
                    double sum = 0;
                    for (int k = 0; k < CH; k++) { double v = d[i+k]; sum += v*v; }
                    double rms = sqrt(sum / CH);
                    speech_rms = speech_rms * 0.8 + rms * 0.2;
                    static double thresh = -1; if (thresh < 0) { const char *t = getenv("VOICE_RMS"); thresh = t ? atof(t) : 1000; }
                    int silent = now_s() < suppress_until || tts_playing() || speaker_busy();
                    int voiced = silent ? 0 : (rms > thresh);
                    if (paused || silent) { recording = 0; seg_start = proc_pos + i + CH; continue; }
                    if (voiced) {
                        if (!recording) { recording = 1; seg_start = proc_pos + i; }
                        quiet = 0;
                    } else if (recording) {
                        quiet += CH;
                        if (getenv("VOICE_DEBUG") && quiet % 3200 == 0)
                            fprintf(stderr, "[gui] quiet=%d rec=%d\n", quiet, recording);
                        if (quiet >= 19200) {
                            size_t a = seg_start, b = proc_pos + i + CH;
                            if (getenv("VOICE_DEBUG")) fprintf(stderr, "[gui] flush len=%zu\n", b - a);
                            if (b > a && b - a > 12800) {
                                if (dev_drop_next_seg) dev_drop_next_seg = 0;
                                else if (!g_kws_ready || active_until > now_s() || dev_until > now_s() || g_always_asr)
                                    enqueue_segment(pcm + a, b - a);
                                else if (getenv("KWS_DUMP")) {
                                    static int dump_n = 0;
                                    char dp[80];
                                    snprintf(dp, sizeof dp, "/tmp/myagent_kws_dump_%d.wav", ++dump_n);
                                    wav_write(dp, pcm + a, b - a);
                                    fprintf(stderr, "[kws] dump %s len=%zu\n", dp, b - a);
                                }
                            }
                            recording = 0; quiet = 0; seg_start = b;
                        }
                    }
                }
                if (recording && total - seg_start >= (size_t)(8 * 16000)) {
                    if (dev_drop_next_seg) dev_drop_next_seg = 0;
                    else if (!g_kws_ready || active_until > now_s() || dev_until > now_s() || g_always_asr)
                        enqueue_segment(pcm + seg_start, total - seg_start);
                    seg_start = total;
                }
                proc_pos += (cnt / CH) * CH;
                // 丢弃已处理前缀，避免缓冲无限增长
                if (!recording && proc_pos > 160000) {
                    size_t keep = pcm_n - proc_pos;
                    memmove(pcm, pcm + proc_pos, keep * sizeof(Sint16));
                    pcm_n = keep;
                    seg_start = seg_start > proc_pos ? seg_start - proc_pos : 0;
                    proc_pos = 0;
                }
            }
            pthread_mutex_unlock(&mu);
        }

        if (drag_hidden && SDL_GetTicks() - last_move_tick > 300) {
            drag_hidden = 0;
            sync_scrcpy(0, 0);
            run_embedded_winctl("mirror-show", NULL);
        }
        static Uint32 last_move = 0;
        static int last_wx = -99999, last_wy = -99999;
        Uint32 tick = SDL_GetTicks();
        if (tick - last_move > 200) {
            last_move = tick;
            int wx = 0, wy = 0;
            SDL_GetWindowPosition(win, &wx, &wy);
            if (wx != last_wx || wy != last_wy) {
                last_wx = wx; last_wy = wy;
                sync_scrcpy(wx, wy);
            }
        }
        static double dbg_t = 0;
        if (getenv("VOICE_DEBUG") && now_s() - dbg_t > 1.0) {
            dbg_t = now_s();
            fprintf(stderr, "[gui] rms=%.0f rec=%d pending=%d status=%s\n", speech_rms, recording, pending_n, status);
        }
        SDL_SetRenderDrawColor(ren, 24, 26, 30, 255); SDL_RenderClear(ren);
        SDL_Color white = { 230,232,238,255 }, gray = { 150,155,165,255 }, blue = { 120,170,255,255 }, green = { 120,220,150,255 };
        SDL_Color purple = { 190,150,255,255 }, orange = { 255,180,110,255 };
        text(ren, big, "ai助手", 40, 30, white);
        {
            char mbuf[64];
            const char *mode; SDL_Color mc;
            double now = now_s();
            if (paused) { mode = "暂停监听"; mc = orange; }
            else if (speaker_busy()) { mode = "播放中 · 暂停监听"; mc = orange; }
            else if (dev_until > now) {
                snprintf(mbuf, sizeof mbuf, "开发模式 %ds", (int)(dev_until - now + 0.999));
                mode = mbuf; mc = purple;
            } else if (active_until > now) {
                snprintf(mbuf, sizeof mbuf, "已唤醒 %ds", (int)(active_until - now + 0.999));
                mode = mbuf; mc = green;
            } else { mode = "待唤醒"; mc = gray; }
            int tw = 0, th = 0;
            TTF_SizeUTF8(small, mode, &tw, &th);
            SDL_Rect badge = { LW - tw - 34, 32, tw + 20, th + 10 };
            SDL_SetRenderDrawColor(ren, 42, 46, 56, 255);
            SDL_RenderFillRect(ren, &badge);
            text(ren, small, mode, badge.x + 10, badge.y + 5, mc);
        }
        text(ren, small, g_kws_ready
             ? "唤醒：你好星期五（50s）；开发：程序员（退出程序员）"
             : "唤醒：你好星期五（本地 KWS 未启用）", 40, 72, gray);
        char buf[600];
        snprintf(buf, sizeof buf, "麦克风: %s", mic_name);
        text(ren, small, buf, 40, 100, gray);
        SDL_SetRenderDrawColor(ren, 48, 52, 60, 255); SDL_RenderFillRect(ren, &micbtn);
        text(ren, small, "换麦", micbtn.x + 22, micbtn.y + 5, white);

        SDL_Rect lvl = { 40, 150, LW - 160, 18 };
        SDL_SetRenderDrawColor(ren, 40, 44, 52, 255); SDL_RenderFillRect(ren, &lvl);
        int lw = (int)(speech_rms / 2000.0 * lvl.w); if (lw > lvl.w) lw = lvl.w; if (lw < 0) lw = 0;
        SDL_Rect lv2 = { lvl.x, lvl.y, lw, lvl.h };
        SDL_SetRenderDrawColor(ren, recording ? 200 : 70, recording ? 90 : 150, 110, 255); SDL_RenderFillRect(ren, &lv2);
        snprintf(buf, sizeof buf, "%s", recording ? "● 在听" : (paused ? "暂停" : "待唤醒"));
        text(ren, small, buf, LW - 110, 148, recording ? green : gray);

        pthread_mutex_lock(&mu); snprintf(buf, sizeof buf, "%s", status); pthread_mutex_unlock(&mu);
        text(ren, font, buf, 40, 190, blue);

        pthread_mutex_lock(&mu); char copy[sizeof(transcript)]; snprintf(copy, sizeof copy, "%s", transcript); pthread_mutex_unlock(&mu);
        char *lines[128]; int nl = 0; char *save = NULL, *ln = strtok_r(copy, "\n", &save);
        while (ln && nl < 128) { lines[nl++] = ln; ln = strtok_r(NULL, "\n", &save); }
        int start = nl > 14 ? nl - 14 : 0;
        for (int i = start; i < nl; i++) text(ren, small, lines[i], 40, 230 + (i - start) * 20, white);

        SDL_SetRenderDrawColor(ren, 58, 92, 140, 255);
        SDL_RenderFillRect(ren, &bvoldown);
        text(ren, small, "音量 -", bvoldown.x + 72, bvoldown.y + 6, white);
        SDL_SetRenderDrawColor(ren, 54, 128, 100, 255);
        SDL_RenderFillRect(ren, &bvolup);
        text(ren, small, "音量 +", bvolup.x + 72, bvolup.y + 6, white);
        SDL_SetRenderDrawColor(ren, 70, 76, 96, 255);
        SDL_RenderFillRect(ren, &bprev);
        SDL_SetRenderDrawColor(ren, 104, 82, 148, 255);
        SDL_RenderFillRect(ren, &bplay);
        SDL_SetRenderDrawColor(ren, 70, 76, 96, 255);
        SDL_RenderFillRect(ren, &bnext);
        text(ren, small, "上一首", bprev.x + 34, bprev.y + 6, white);
        text(ren, small, "暂停/播放", bplay.x + 26, bplay.y + 6, white);
        text(ren, small, "下一首", bnext.x + 34, bnext.y + 6, white);

        SDL_Rect ibox = { 40, H - 88, LW - 80, 34 };
        SDL_SetRenderDrawColor(ren, 40, 44, 52, 255); SDL_RenderFillRect(ren, &ibox);
        snprintf(buf, sizeof buf, "%s|", input);
        text(ren, small, buf, 48, H - 82, white);
        SDL_SetRenderDrawColor(ren, 48, 52, 60, 255); SDL_RenderFillRect(ren, &pausebtn);
        text(ren, small, paused ? "继续监听" : "暂停监听", pausebtn.x + 20, pausebtn.y + 5, green);

        // 右侧：当前应用截图预览
        SDL_Rect panel = { LW, 0, W - LW, H };
        SDL_SetRenderDrawColor(ren, 16, 18, 22, 255);
        SDL_RenderFillRect(ren, &panel);
        SDL_SetRenderDrawColor(ren, 40, 44, 52, 255);
        SDL_RenderDrawLine(ren, LW, 0, LW, H);
        text(ren, small, "当前应用", LW + 16, 12, gray);
        struct stat pst;
        if (stat("/tmp/myagent_preview.png", &pst) == 0 && pst.st_mtime != preview_mtime) {
            SDL_Surface *sf = IMG_Load("/tmp/myagent_preview.png");
            if (sf) {
                if (preview_tex) SDL_DestroyTexture(preview_tex);
                preview_tex = SDL_CreateTextureFromSurface(ren, sf);
                if (preview_tex) SDL_SetTextureScaleMode(preview_tex, SDL_ScaleModeLinear);
                SDL_FreeSurface(sf);
                preview_mtime = pst.st_mtime;
            }
        }
        if (preview_tex) {
            int tw = 0, th = 0;
            SDL_QueryTexture(preview_tex, NULL, NULL, &tw, &th);
            float sc;
            SDL_Rect dst;
            sc = fmin((float)(PW - 16) / tw, (float)(H - 60) / th);
            dst.w = (int)(tw * sc); dst.h = (int)(th * sc);
            dst.x = LW + ((PW - 16) - dst.w) / 2;
            dst.y = 40 + ((H - 60) - dst.h) / 2;
            SDL_RenderSetClipRect(ren, &panel);
            SDL_RenderCopy(ren, preview_tex, NULL, &dst);
            SDL_RenderSetClipRect(ren, NULL);
        }
        SDL_RenderPresent(ren);
        SDL_Delay(16);
    }
    if (cap_pcm) { cap_stop = 1; snd_pcm_close(cap_pcm); cap_pcm = NULL; }
    usleep(200000);
    kws_shutdown();
    TTF_CloseFont(font); TTF_CloseFont(small); TTF_CloseFont(big);
    SDL_DestroyRenderer(ren); SDL_DestroyWindow(win); TTF_Quit(); SDL_Quit();
    pthread_mutex_lock(&mu); free(pcm); pthread_mutex_unlock(&mu);
    return 0;
}

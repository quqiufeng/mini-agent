// gui/sdl/main.c — my-agent 语音控制台（SDL2 + SDL2_ttf）
// 常驻采集 USB 麦克风 → 静音切句 → 远程 ASR → 唤醒词门控 → send.sh 转发大脑
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <alsa/asoundlib.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <sys/wait.h>
#include <fcntl.h>

#define W 480
#define H 640
#define ROOT "/home/quqiufeng/my-agent"
#define FONT "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
#define ASR_BIN ROOT "/tools/asr.sh"
#define SEND_BIN ROOT "/send.sh"
#define TUI_BIN ROOT "/tools/tui_type.sh"
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
static double suppress_until = 0;
static int ack_busy = 0;
static int ack_should_play = 0;
static char *run_capture(char *const argv[], int *rc_out);

static snd_pcm_t *cap_pcm = NULL;
static volatile int cap_stop = 0;
static int cap_started = 0;
static char cap_dev_name[64] = "plughw:Uni,0";
static Sint16 *pcm = NULL;
static size_t pcm_n = 0, pcm_cap = 0;
static char mic_name[128] = "Comica (plughw:Uni,0)";

static double now_s(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec + ts.tv_nsec / 1e9; }

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
    char *argv[] = { TTS_BIN, (char *)txt, NULL };
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
        dup2(p[1], 1); dup2(p[1], 2); close(p[0]); close(p[1]);
        execv(argv[0], argv); _exit(127);
    }
    close(p[1]);
    size_t cap = 4096, n = 0; char *buf = malloc(cap); ssize_t r;
    while ((r = read(p[0], buf + n, cap - n - 1)) > 0) {
        n += r;
        if (n + 1 >= cap) { cap *= 2; buf = realloc(buf, cap); }
    }
    close(p[0]);
    int st = 0; waitpid(pid, &st, 0); buf[n] = 0;
    if (rc_out) *rc_out = WIFEXITED(st) ? WEXITSTATUS(st) : -1;
    return buf;
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
        if (getenv("VOICE_DEBUG")) { char cp[256]; snprintf(cp, sizeof cp, "cp -f '%s' /tmp/myagent_last.wav", path); int _r = system(cp); (void)_r; }
        char *argv[] = { ASR_BIN, path, NULL };
        int rc = 0; char *out = run_capture(argv, &rc);
        char text[1024] = "";
        if (out) {
            char *save = NULL, *line = strtok_r(out, "\n", &save), *last = NULL;
            while (line) { if (*line) last = line; line = strtok_r(NULL, "\n", &save); }
            if (last) snprintf(text, sizeof text, "%s", last);
            free(out);
        }
        unlink(path);
        char norm[1024]; normalize(text, norm, sizeof norm);
        if (getenv("VOICE_DEBUG")) fprintf(stderr, "[gui] asr=%s\n", text);
        if (rc != 0 || !*norm) { set_status(active_until > now_s() ? "已唤醒 · 在听" : "待唤醒"); continue; }

        char rest[1024];
        int woke = strip_wake(text, rest, sizeof rest);

        // 开发者模式：文本以「开发者模式」开头 → 删掉该词，余下文本直接键入大脑 TUI
        {
            const char *DEV = "开发者模式";
            size_t dl = strlen(DEV);
            char devbuf[1024] = "";
            if (strncmp(norm, DEV, dl) == 0) snprintf(devbuf, sizeof devbuf, "%s", norm + dl);
            else if (woke && strncmp(rest, DEV, dl) == 0) snprintf(devbuf, sizeof devbuf, "%s", rest + dl);
            if (devbuf[0]) {
                char line[1100]; snprintf(line, sizeof line, "开发者: %s", devbuf);
                add_line(line);
                set_status("开发者模式 → TUI");
                char *targv[] = { TUI_BIN, devbuf, NULL };
                int trc = 0; char *tout = run_capture(targv, &trc); free(tout);
                set_status(trc == 0 ? "已输入 TUI" : "TUI 输入失败");
                continue;
            }
        }
        static double active_ms = 0;
        if (active_ms <= 0) { const char *v = getenv("VOICE_ACTIVE_MS"); active_ms = v ? atof(v) : 10000; }
        if (woke) {
            active_until = now_s() + active_ms / 1000.0;
            add_line("● 唤醒");
            ack_speak(1);
            if (!rest[0]) { set_status("已唤醒 · 在听"); continue; }
            char line[1100]; snprintf(line, sizeof line, "我: %s", rest);
            add_line(line);
            char *sargv[] = { SEND_BIN, rest, NULL };
            int src = -1;
            for (int i = 1; i <= 3; i++) {
                char *sout = run_capture(sargv, &src); free(sout);
                if (src == 0) break;
                set_status("大脑忙，重试 …"); sleep(3);
            }
            set_status(src == 0 ? "已唤醒 · 已发送" : "发送失败");
            continue;
        }

        if (active_until > now_s()) {
            char line[1100]; snprintf(line, sizeof line, "我: %s", text);
            add_line(line);
            set_status("识别: 已发送");
            char *sargv[] = { SEND_BIN, text, NULL };
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

int main(void) {
    if (SDL_Init(SDL_INIT_VIDEO) != 0) { fprintf(stderr, "SDL_Init: %s\n", SDL_GetError()); return 1; }
    if (TTF_Init() != 0) { fprintf(stderr, "TTF_Init: %s\n", TTF_GetError()); return 1; }
    if (chdir(ROOT) != 0) {}
    SDL_Window *win = SDL_CreateWindow("My Agent · 语音", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, W, H, SDL_WINDOW_SHOWN);
    SDL_Renderer *ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!ren) ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_SOFTWARE);
    TTF_Font *font = TTF_OpenFontIndex(FONT, 20, 0);
    TTF_Font *small = TTF_OpenFontIndex(FONT, 15, 0);
    TTF_Font *big = TTF_OpenFontIndex(FONT, 30, 0);
    if (!font || !small || !big) return 1;

    open_capture();
    // 大脑没起就先拉起来（start.sh 会开显式终端）
    if (system("curl --max-time 1 -sf http://127.0.0.1:4097/global/health >/dev/null 2>&1") != 0) {
        set_status("大脑启动中 …");
        if (fork() == 0) { execl(ROOT "/start.sh", "start.sh", NULL); _exit(1); }
    }
    pthread_t th; pthread_create(&th, NULL, worker, NULL); pthread_detach(th);
    ack_speak(0);

    int running = 1, recording = 0, quiet = 0, proc_pos = 0;
    double speech_rms = 0; char input[512] = "";
    SDL_Event e;
    SDL_Rect micbtn = { W - 110, 96, 90, 30 };
    SDL_Rect pausebtn = { 40, H - 44, 130, 32 };
    size_t seg_start = 0;

    while (running) {
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT) running = 0;
            else if (e.type == SDL_KEYDOWN) {
                if (e.key.keysym.sym == SDLK_ESCAPE) running = 0;
                else if (e.key.keysym.sym == SDLK_BACKSPACE) { size_t l = strlen(input); if (l) input[l-1] = 0; }
                else if (e.key.keysym.sym == SDLK_RETURN && *input) {
                    char line[600]; snprintf(line, sizeof line, "我: %s", input); add_line(line);
                    set_status("发送中 …");
                    char *sargv[] = { SEND_BIN, input, NULL };
                    int rc = -1; for (int i = 1; i <= 3; i++) { char *o = run_capture(sargv, &rc); free(o); if (!rc) break; sleep(3); }
                    set_status(rc == 0 ? "已发送" : "发送失败");
                    input[0] = 0;
                }
            } else if (e.type == SDL_TEXTINPUT) {
                size_t l = strlen(input), a = strlen(e.text.text);
                if (l + a < sizeof(input) - 1) strcat(input, e.text.text);
            } else if (e.type == SDL_MOUSEBUTTONDOWN && e.button.button == SDL_BUTTON_LEFT) {
                int x = e.button.x, y = e.button.y;
                if (x >= micbtn.x && x <= micbtn.x + micbtn.w && y >= micbtn.y && y <= micbtn.y + micbtn.h) cycle_mic();
                else if (x >= pausebtn.x && x <= pausebtn.x + pausebtn.w && y >= pausebtn.y && y <= pausebtn.y + pausebtn.h) {
                    paused = !paused; set_status(paused ? "已暂停" : "待唤醒");
                }
            }
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
                    int voiced = (now_s() < suppress_until) ? 0 : (rms > thresh);
                    if (paused) { recording = 0; seg_start = proc_pos + i + CH; continue; }
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
                            if (b > a && b - a > 12800) enqueue_segment(pcm + a, b - a);
                            recording = 0; quiet = 0; seg_start = b;
                        }
                    }
                }
                if (recording && total - seg_start >= (size_t)(8 * 16000)) {
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

        static double dbg_t = 0;
        if (getenv("VOICE_DEBUG") && now_s() - dbg_t > 1.0) {
            dbg_t = now_s();
            fprintf(stderr, "[gui] rms=%.0f rec=%d pending=%d status=%s\n", speech_rms, recording, pending_n, status);
        }
        SDL_SetRenderDrawColor(ren, 24, 26, 30, 255); SDL_RenderClear(ren);
        SDL_Color white = { 230,232,238,255 }, gray = { 150,155,165,255 }, blue = { 120,170,255,255 }, green = { 120,220,150,255 };
        text(ren, big, "My Agent", 40, 30, white);
        text(ren, small, "唤醒词：你好星期五 / 星期五（10 秒内直接说指令）", 40, 72, gray);
        char buf[600];
        snprintf(buf, sizeof buf, "麦克风: %s", mic_name);
        text(ren, small, buf, 40, 100, gray);
        SDL_SetRenderDrawColor(ren, 48, 52, 60, 255); SDL_RenderFillRect(ren, &micbtn);
        text(ren, small, "换麦", micbtn.x + 22, micbtn.y + 5, white);

        SDL_Rect lvl = { 40, 150, W - 160, 18 };
        SDL_SetRenderDrawColor(ren, 40, 44, 52, 255); SDL_RenderFillRect(ren, &lvl);
        int lw = (int)(speech_rms / 2000.0 * lvl.w); if (lw > lvl.w) lw = lvl.w; if (lw < 0) lw = 0;
        SDL_Rect lv2 = { lvl.x, lvl.y, lw, lvl.h };
        SDL_SetRenderDrawColor(ren, recording ? 200 : 70, recording ? 90 : 150, 110, 255); SDL_RenderFillRect(ren, &lv2);
        snprintf(buf, sizeof buf, "%s", recording ? "● 在听" : (paused ? "暂停" : "待唤醒"));
        text(ren, small, buf, W - 110, 148, recording ? green : gray);

        pthread_mutex_lock(&mu); snprintf(buf, sizeof buf, "%s", status); pthread_mutex_unlock(&mu);
        text(ren, font, buf, 40, 190, blue);

        pthread_mutex_lock(&mu); char copy[sizeof(transcript)]; snprintf(copy, sizeof copy, "%s", transcript); pthread_mutex_unlock(&mu);
        char *lines[128]; int nl = 0; char *save = NULL, *ln = strtok_r(copy, "\n", &save);
        while (ln && nl < 128) { lines[nl++] = ln; ln = strtok_r(NULL, "\n", &save); }
        int start = nl > 14 ? nl - 14 : 0;
        for (int i = start; i < nl; i++) text(ren, small, lines[i], 40, 230 + (i - start) * 20, white);

        SDL_Rect ibox = { 40, H - 88, W - 80, 34 };
        SDL_SetRenderDrawColor(ren, 40, 44, 52, 255); SDL_RenderFillRect(ren, &ibox);
        snprintf(buf, sizeof buf, "%s|", input);
        text(ren, small, buf, 48, H - 82, white);
        SDL_SetRenderDrawColor(ren, 48, 52, 60, 255); SDL_RenderFillRect(ren, &pausebtn);
        text(ren, small, paused ? "继续监听" : "暂停监听", pausebtn.x + 20, pausebtn.y + 5, green);

        SDL_RenderPresent(ren);
        SDL_Delay(16);
    }
    if (cap_pcm) { cap_stop = 1; snd_pcm_close(cap_pcm); cap_pcm = NULL; }
    TTF_CloseFont(font); TTF_CloseFont(small); TTF_CloseFont(big);
    SDL_DestroyRenderer(ren); SDL_DestroyWindow(win); TTF_Quit(); SDL_Quit();
    pthread_mutex_lock(&mu); free(pcm); pthread_mutex_unlock(&mu);
    return 0;
}

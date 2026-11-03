// spectrum.c — parec 流 → FFT 频段 JSON Lines（无 shell、无 Python）
#include <fftw3.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <time.h>

#define RATE 48000
#define CHUNK 2048
#define NOUT (CHUNK / 2 + 1)

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static pid_t start_parec(const char *src, int *out_fd) {
    int p[2];
    if (pipe(p) != 0) return -1;
    pid_t pid = fork();
    if (pid == 0) {
        close(p[0]);
        dup2(p[1], 1);
        close(p[1]);
        char dev[512];
        snprintf(dev, sizeof dev, "--device=%s", src);
        char *argv[] = { "parec", dev, "--format=s16le", "--rate=48000",
                         "--channels=1", "--client-name=myagent-spectrum", "--latency-msec=100", NULL };
        execvp("parec", argv);
        _exit(127);
    }
    close(p[1]);
    *out_fd = p[0];
    return pid;
}

static int read_full(int fd, void *buf, size_t n) {
    size_t got = 0;
    while (got < n) {
        ssize_t r = read(fd, (char *)buf + got, n - got);
        if (r <= 0) return -1;
        got += (size_t)r;
    }
    return 0;
}

int main(int argc, char **argv) {
    const char *src = argc > 1 ? argv[1] : "@DEFAULT_SOURCE@";
    int nbands = argc > 2 ? atoi(argv[2]) : 32;
    int fps = argc > 3 ? atoi(argv[3]) : 30;
    if (nbands < 1) nbands = 1;
    if (nbands > 128) nbands = 128;
    if (fps < 1) fps = 1;
    if (fps > 60) fps = 60;

    int fd = -1;
    pid_t pp = start_parec(src, &fd);
    if (pp < 0 || fd < 0) { fprintf(stderr, "[spectrum] 启动 parec 失败\n"); return 1; }
    usleep(200000);

    float *inp = fftwf_malloc(sizeof(float) * CHUNK);
    float *out = fftwf_malloc(sizeof(float) * NOUT * 2);
    float *win = fftwf_malloc(sizeof(float) * CHUNK);
    if (!inp || !out || !win) return 1;
    fftwf_plan plan = fftwf_plan_dft_r2c_1d(CHUNK, inp, (fftwf_complex *)out, FFTW_ESTIMATE);
    if (!plan) return 1;
    for (int i = 0; i < CHUNK; i++)
        win[i] = 0.5f - 0.5f * cosf(2.0f * (float)M_PI * i / (CHUNK - 1));

    double edges[129], freqs[NOUT];
    for (int i = 0; i < NOUT; i++) freqs[i] = i * (double)RATE / CHUNK;
    for (int i = 0; i <= nbands; i++) edges[i] = 40.0 * pow(16000.0 / 40.0, (double)i / nbands);

    int16_t buf[CHUNK];
    double interval = 1.0 / fps;
    while (read_full(fd, buf, sizeof buf) == 0) {
        double sumsq = 0, peak = 0;
        for (int i = 0; i < CHUNK; i++) {
            double x = buf[i] / 32768.0;
            sumsq += x * x;
            double ax = fabs(x);
            if (ax > peak) peak = ax;
            inp[i] = (float)(x * win[i]);
        }
        fftwf_execute(plan);
        printf("{\"ts\":%.3f,\"rms\":%.4f,\"peak\":%.4f,\"bands\":[",
               now_s(), sqrt(sumsq / CHUNK), peak);
        for (int b = 1; b <= nbands; b++) {
            double v = 0; int n = 0;
            for (int i = 0; i < NOUT; i++) {
                if (freqs[i] >= edges[b - 1] && freqs[i] < edges[b]) {
                    double re = out[2 * i], im = out[2 * i + 1];
                    v += sqrt(re * re + im * im); n++;
                }
            }
            if (n) v /= n;
            double db = 20 * log10(v + 1e-9);
            double norm = (db + 80) / 80;
            if (norm < 0) norm = 0; else if (norm > 1) norm = 1;
            printf("%s%.4f", b > 1 ? "," : "", norm);
        }
        printf("]}\n");
        fflush(stdout);
        usleep((useconds_t)(interval * 1e6));
    }
    fftwf_destroy_plan(plan);
    fftwf_free(inp); fftwf_free(out); fftwf_free(win);
    close(fd);
    kill(pp, SIGTERM);
    waitpid(pp, NULL, WNOHANG);
    return 0;
}

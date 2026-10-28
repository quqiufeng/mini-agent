// audio_level.c — 从 stdin 读 s16le 单声道 PCM，每 0.25s 输出一行 "rms peak"
#include <stdio.h>
#include <stdint.h>
#include <math.h>
int main(void) {
    int16_t buf[4000];
    size_t n;
    while ((n = fread(buf, sizeof(int16_t), 4000, stdin)) > 0) {
        double sum = 0; int peak = 0;
        for (size_t i = 0; i < n; i++) {
            int v = buf[i] < 0 ? -buf[i] : buf[i];
            if (v > peak) peak = v;
            sum += (double)buf[i] * buf[i];
        }
        int rms = (int)sqrt(sum / (n ? n : 1));
        printf("%d %d\n", rms, peak);
        fflush(stdout);
    }
    return 0;
}

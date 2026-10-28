// camera_block.cpp — 摄像头被遮挡 → 暂停音乐（本机 OpenCV）
// 编译: g++ -O2 -std=c++17 -pthread camera_block.cpp -o camera_block $(pkg-config --cflags --libs opencv4)
#include <opencv2/opencv.hpp>
#include <thread>
#include <mutex>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstdarg>
#include <cstring>
#include <cmath>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <time.h>

static const char *MEDIA_BIN = "/home/quqiufeng/my-agent/tools/devctl.sh";
static const char *STATE_BIN = "/home/quqiufeng/my-agent/tools/state.sh";

static double now_s() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void logf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fflush(stderr);
}

static std::mutex g_mu;
static cv::Mat g_frame;
static double g_frame_ts = 0;
static std::atomic<bool> g_stop{false};

static void reader_loop(cv::VideoCapture *cap) {
    while (!g_stop) {
        cv::Mat f;
        *cap >> f;
        if (!f.empty()) {
            std::lock_guard<std::mutex> lk(g_mu);
            g_frame = f;
            g_frame_ts = now_s();
        }
    }
}

static bool open_cam(cv::VideoCapture &cap, const char *url) {
    setenv("OPENCV_FFMPEG_CAPTURE_OPTIONS",
           "rtsp_transport;tcp|fflags;nobuffer|flags;low_delay", 0);
    for (int i = 0; i < 3; i++) {
        cap.open(url, cv::CAP_FFMPEG);
        if (cap.isOpened()) {
            cap.set(cv::CAP_PROP_BUFFERSIZE, 1);
            return true;
        }
        logf("[camera_block] open failed (%d)\n", i + 1);
        sleep(1);
    }
    return false;
}

int main(int argc, char **argv) {
    if (argc < 3 || strcmp(argv[1], "--watch") != 0) {
        logf("用法: %s --watch <media_pid>\n", argv[0]);
        return 2;
    }
    long media_pid = atol(argv[2]);
    if (media_pid <= 0) return 2;

    const char *url = getenv("TPLINK_RTSP");
    if (!url || !*url) {
        logf("[camera_block] TPLINK_RTSP 未设置\n");
        return 2;
    }

    cv::VideoCapture cap;
    if (!open_cam(cap, url)) return 1;
    logf("[camera_block] camera opened\n");

    std::thread reader(reader_loop, &cap);
    reader.detach();

    double last_ts = 0;
    cv::Mat frame;
    for (int i = 0; i < 50 && frame.empty(); i++) {
        usleep(100000);
        std::lock_guard<std::mutex> lk(g_mu);
        if (g_frame_ts > 0) { frame = g_frame.clone(); last_ts = g_frame_ts; }
    }
    if (frame.empty()) {
        logf("[camera_block] no frame\n");
        return 1;
    }

    cv::Mat bg;
    double bg_mean = 0;
    {
        cv::Mat small, gray;
        cv::resize(frame, small, cv::Size(320, (int)(frame.rows * 320.0 / frame.cols)));
        cv::cvtColor(small, gray, cv::COLOR_BGR2GRAY);
        bg = small.clone();
        bg_mean = cv::mean(gray)[0];
        cv::imwrite("/tmp/myagent_camera_bg.jpg", bg);
    }

    int covered_count = 0;
    double covered_since = 0;
    double cooldown_until = 0;
    int last_cov = -1;
    while (true) {
        if (kill((pid_t)media_pid, 0) != 0) {
            logf("[camera_block] playback ended, exit wall=%ld\n", (long)time(NULL));
            break;
        }
        cv::Mat f;
        {
            std::lock_guard<std::mutex> lk(g_mu);
            if (g_frame_ts > last_ts) { f = g_frame.clone(); last_ts = g_frame_ts; }
        }
        if (f.empty()) { usleep(100000); continue; }

        cv::Mat small, gray;
        cv::resize(f, small, cv::Size(320, (int)(f.rows * 320.0 / f.cols)));
        cv::cvtColor(small, gray, cv::COLOR_BGR2GRAY);
        double mean = cv::mean(gray)[0];

        // 只用亮度：遮挡后画面明显变暗
        if (mean > bg_mean * 1.3) {
            bg = small.clone();
            bg_mean = mean;
            cv::imwrite("/tmp/myagent_camera_bg.jpg", bg);
        }
        double ref = bg_mean > 150 ? 150.0 : bg_mean;
        bool covered = (mean < 50) || (mean < ref * 0.55);
        if ((int)covered != last_cov) {
            char scmd[256];
            snprintf(scmd, sizeof scmd, "%s set camera %s >/dev/null 2>&1",
                     STATE_BIN, covered ? "blocked" : "clear");
            int _r = std::system(scmd); (void)_r;
            last_cov = covered ? 1 : 0;
        }
        double t = now_s();
        if (t < cooldown_until) {
            usleep(200000);
            continue;
        }
        if (covered) {
            if (covered_count == 0) covered_since = t;
            covered_count++;
            logf("[camera_block] covered mean=%.0f bg=%.0f n=%d wall=%ld\n",
                 mean, bg_mean, covered_count, (long)time(NULL));
            if (covered_count >= 2 && t - covered_since >= 0.2) {
                char stcmd[512], cmd[512];
                snprintf(stcmd, sizeof stcmd, "%s status 2>/dev/null", MEDIA_BIN);
                bool playing = false;
                FILE *pp = popen(stcmd, "r");
                if (pp) {
                    char buf[256];
                    if (fgets(buf, sizeof buf, pp) && strstr(buf, "播放中")) playing = true;
                    pclose(pp);
                }
                if (playing) {
                    snprintf(cmd, sizeof cmd, "%s pause >/dev/null 2>&1", MEDIA_BIN);
                    logf("[camera_block] blocked -> pause wall=%ld\n", (long)time(NULL));
                    int rc = std::system(cmd);
                    logf("[camera_block] pause rc=%d\n", rc);
                } else {
                    logf("[camera_block] blocked but already paused\n");
                }
                covered_count = 0;
                cooldown_until = t + 1.0;
            }
        } else {
            covered_count = 0;
        }
        usleep(200000);
    }
    logf("[camera_block] loop exit wall=%ld\n", (long)time(NULL));
    { char scmd[256]; snprintf(scmd, sizeof scmd, "%s set camera clear >/dev/null 2>&1", STATE_BIN); int _r = std::system(scmd); (void)_r; }
    g_stop = true;
    return 0;
}

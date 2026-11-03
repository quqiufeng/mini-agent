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
#include <sys/wait.h>
#include <fcntl.h>
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


static int run_wait(const char *prog, const char *const argv[]) {
    pid_t p = fork();
    if (p == 0) {
        int fd = open("/dev/null", O_WRONLY);
        if (fd >= 0) { dup2(fd, 1); dup2(fd, 2); close(fd); }
        execv(prog, const_cast<char *const *>(argv));
        _exit(127);
    }
    if (p < 0) return -1;
    int st = 0;
    waitpid(p, &st, 0);
    return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

int main(int argc, char **argv) {
    bool resident = (argc >= 2 && strcmp(argv[1], "--resident") == 0);
    long media_pid = 0;
    if (!resident) {
        if (argc < 3 || strcmp(argv[1], "--watch") != 0) {
            logf("用法: %s --watch <media_pid> | --resident\n", argv[0]);
            return 2;
        }
        media_pid = atol(argv[2]);
        if (media_pid <= 0) return 2;
    }

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
    double last_progress = now_s();
    int last_cov = -1;
    while (true) {
        if (!resident && kill((pid_t)media_pid, 0) != 0) {
            logf("[camera_block] playback ended, exit wall=%ld\n", (long)time(NULL));
            break;
        }
        cv::Mat f;
        {
            std::lock_guard<std::mutex> lk(g_mu);
            if (g_frame_ts > last_ts) { f = g_frame.clone(); last_ts = g_frame_ts; last_progress = now_s(); }
        }
        if (f.empty()) {
            if (resident && now_s() - last_progress > 10.0) {
                logf("[camera_block] resident stalled, exit for restart\n");
                break;
            }
            usleep(100000);
            continue;
        }

        cv::Mat small, gray;
        cv::resize(f, small, cv::Size(320, (int)(f.rows * 320.0 / f.cols)));
        cv::cvtColor(small, gray, cv::COLOR_BGR2GRAY);
        double mean = cv::mean(gray)[0];
        cv::Rect roi(gray.cols * 0.1, gray.rows * 0.2, gray.cols * 0.8, gray.rows * 0.7);
        cv::Mat center = gray(roi), lap;
        cv::Laplacian(center, lap, CV_64F);
        cv::Scalar lm, ls;
        cv::meanStdDev(lap, lm, ls);
        double lapvar = ls[0] * ls[0];

        // 亮度明显下降，或中心区域几乎没有细节（镜头被挡/失焦）
        if (mean > bg_mean * 1.3) {
            bg = small.clone();
            bg_mean = mean;
            cv::imwrite("/tmp/myagent_camera_bg.jpg", bg);
        }
        double ref = bg_mean > 150 ? 150.0 : bg_mean;
        bool covered = (mean < 50) || (mean < ref * 0.55) || (lapvar < 5.0);
        if ((int)covered != last_cov) {
            const char *sav[] = { "state.sh", "set", "device.camera.cover", covered ? "blocked" : "clear", NULL };
            run_wait(STATE_BIN, sav);
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
            logf("[camera_block] covered mean=%.0f lapvar=%.1f bg=%.0f n=%d wall=%ld\n",
                 mean, lapvar, bg_mean, covered_count, (long)time(NULL));
            if (covered_count >= 2 && t - covered_since >= 0.2) {
                const char *pav[] = { "devctl.sh", "pause", NULL };
                logf("[camera_block] blocked -> pause wall=%ld\n", (long)time(NULL));
                int rc = run_wait(MEDIA_BIN, pav);
                logf("[camera_block] pause rc=%d\n", rc);
                covered_count = 0;
                cooldown_until = t + 5.0;
            }
        } else {
            covered_count = 0;
        }
        usleep(200000);
    }
    logf("[camera_block] loop exit wall=%ld\n", (long)time(NULL));
    { const char *sav[] = { "state.sh", "set", "device.camera.cover", "clear", NULL }; run_wait(STATE_BIN, sav); }
    g_stop = true;
    return 0;
}

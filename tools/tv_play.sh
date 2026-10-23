#!/usr/bin/env bash
# tools/tv_play.sh — 让电视 VLC 直接播放 NAS 视频（电视直连 NAS，本机只做遥控）
# @desc 电视直连 NAS 播放：本机只拼直链 + adb 唤起 VLC，不转码不中继
# @usage tv_play.sh <关键词>            # 在 NAS 媒体库搜索并播放（多个取最大）
#        tv_play.sh <NAS相对路径>       # 直接播放，如 "寒站1994/xxx.mkv"
#        tv_play.sh stop                # 停止播放（返回电视桌面）
exec python3 - "$@" <<'PY'
import os, sys, time, subprocess, urllib.parse, xml.etree.ElementTree as ET
import requests

TV_SERIAL = os.environ.get("TV_SERIAL", "192.168.1.110:5555")
VLC = "org.videolan.vlc/.StartActivity"
VIDEO_EXT = {".mkv", ".mp4", ".avi", ".ts", ".m2ts", ".mov", ".wmv", ".flv", ".webm", ".rmvb", ".iso"}
SKIP_DIR = {".bt", ".lyricdownload", ".subtitledownload", "Pictures", "DCIM", "微博图", "book", "手机备份"}


def env():
    e = {}
    with open(os.path.expanduser("~/.env")) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                e[k.strip()] = v.strip().strip('"').strip("'")
    return e


def adb(*args, check=False):
    return subprocess.run(["adb", "-s", TV_SERIAL] + list(args), text=True, capture_output=True, check=check)


def collect(href, auth, origin):
    if href.startswith("/"):
        href = origin + href
    with requests.Session() as s:
        s.auth = auth
        r = s.request("PROPFIND", href, headers={"Depth": "1"}, timeout=30)
    r.raise_for_status()
    root = ET.fromstring(r.content)
    out = []
    for resp in root:
        if not resp.tag.endswith("response"):
            continue
        h = ln = None
        coll = False
        for el in resp.iter():
            tag = el.tag.rsplit("}", 1)[-1]
            if tag == "href" and h is None:
                h = el.text
            elif tag == "getcontentlength" and el.text:
                ln = int(el.text)
            elif tag == "collection":
                coll = True
        if h:
            out.append((h, coll or h.endswith("/"), ln or 0))
    return out


def search(base, keyword, auth):
    from concurrent.futures import ThreadPoolExecutor
    kw = keyword.lower()
    origin = "/".join(base.split("/")[:3])
    frontier = [base + "/"]
    seen = set(frontier)
    deadline = time.time() + 25
    total = 0
    pool = ThreadPoolExecutor(max_workers=8)
    while frontier and time.time() < deadline:
        found = []
        nxt = []
        results = list(pool.map(lambda d: safe_collect(d, auth, origin), frontier))
        total += len(frontier)
        for entries in results:
            for href, coll, ln in entries or ():
                name = urllib.parse.unquote(href.rstrip("/").rsplit("/", 1)[-1])
                if coll:
                    if name in SKIP_DIR or (name.startswith(".") and name != "."):
                        continue
                    d = href.rstrip("/") + "/"
                    if d not in seen:
                        seen.add(d)
                        nxt.append(d)
                else:
                    ext = os.path.splitext(name)[1].lower()
                    if ext in VIDEO_EXT and kw in name.lower():
                        found.append((ln, href))
        sys.stderr.write("\r搜索中… %d 目录, 命中 %d " % (total, len(found)))
        sys.stderr.flush()
        if found:
            sys.stderr.write("\n")
            pool.shutdown(wait=False)
            return found
        frontier = nxt
    pool.shutdown(wait=False)
    sys.stderr.write("\n")
    return []


def safe_collect(href, auth, origin):
    try:
        return collect(href, auth, origin)
    except Exception:
        return None


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        sys.stderr.write(__doc__ or "用法: tv_play.sh <关键词|NAS相对路径|stop>\n")
        return 2
    arg = sys.argv[1].strip()
    if arg == "stop":
        adb("shell", "input", "keyevent", "4")
        print("已发送返回键")
        return 0
    find_only = arg == "--find"
    if find_only:
        if len(sys.argv) < 3:
            print("用法: tv_play.sh --find <关键词>", file=sys.stderr)
            return 2
        arg = sys.argv[2].strip()

    e = env()
    base = e["WEBDAV_URL"].rstrip("/")
    auth = (e["WEBDAV_USER"], e["WEBDAV_PASS"])
    share = e.get("WEBDAV_SHARE", "sata11-18072858035")
    root = base + "/" + urllib.parse.quote(share)

    if arg.startswith("http://") or arg.startswith("https://"):
        url = arg
    else:
        if "/" in arg or os.path.splitext(arg)[1].lower() in VIDEO_EXT:
            rel = arg.strip("/")
        else:
            found = search(root, arg, auth)
            if not found:
                print("没找到包含「%s」的视频" % arg, file=sys.stderr)
                return 1
            found.sort(reverse=True)
            rel = urllib.parse.unquote(found[0][1]).split("/" + share + "/", 1)[-1].lstrip("/")
            if len(found) > 1:
                print("命中 %d 个，选最大：%s" % (len(found), rel.split("/")[-1]), file=sys.stderr)
        if find_only:
            for ln, href in found[:10]:
                print("%8.1f MB  %s" % (ln / 1048576, urllib.parse.unquote(href)))
            return 0
        enc = "/".join(urllib.parse.quote(p) for p in rel.split("/"))
        cred = urllib.parse.quote(e["WEBDAV_USER"], safe="") + ":" + urllib.parse.quote(e["WEBDAV_PASS"], safe="")
        scheme, host = base.split("://", 1)
        url = scheme + "://" + cred + "@" + host + "/" + urllib.parse.quote(share) + "/" + enc

    adb("connect", TV_SERIAL)
    adb("shell", "input", "keyevent", "224")
    time.sleep(0.5)
    r = adb("shell", "am", "start", "-a", "android.intent.action.VIEW",
            "-d", url, "-t", "video/x-matroska", "-n", VLC)
    disp = url
    pw = e["WEBDAV_PASS"]
    disp = disp.replace(urllib.parse.quote(pw, safe=""), "***").replace(pw, "***")
    if r.returncode != 0 or "Error" in r.stdout + r.stderr:
        print("adb 启动失败：\n" + r.stdout + r.stderr, file=sys.stderr)
        return 1
    print("已在电视播放：" + disp)
    return 0


sys.exit(main())
PY

#!/usr/bin/env bash
# tools/tencent.sh — 腾讯视频（云视听极光）按关键词搜索并播放
# @desc 电视腾讯视频：拼音首字母 T9 搜索（逐字母截图核对）；--expect 用 OCR 校验详情页
# @usage tencent.sh <中文关键词|拼音>              # 搜索并选第一个候选（最佳匹配）
#        tencent.sh <关键词> --play              # 搜索并播放
#        tencent.sh <关键词> --expect "<标题>"   # OCR 选匹配候选并校验
#        tencent.sh <关键词> --full              # 用全拼而不是首字母
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TV_SERIAL=${TV_SERIAL:-192.168.1.110:5555}
ADB=(adb -s "$TV_SERIAL")

# 1920x1080 下 T9 键盘坐标
COLS=(330 409 488 568 648 729)
ROWS=(384 463 543 623 703 783)
MAP="ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890"

usage() { sed -n '2,7p' "$0" | sed 's/^# //'; exit 2; }

[ $# -ge 1 ] || usage
KW="$1"; shift
PLAY=0; FULL=0; EXPECT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --play) PLAY=1 ;;
        --full) FULL=1 ;;
        --expect)
            shift
            [ $# -ge 1 ] || { echo "--expect 需要标题" >&2; exit 2; }
            EXPECT="$1" ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
    shift
done

# 多音字词表（优先于 uconv 的默认读音）
POLY=(
    "长征:chang zheng" "长江:chang jiang" "长城:chang cheng" "长安:chang an"
    "长远:chang yuan" "长空:chang kong" "长期:chang qi" "长发:chang fa"
    "长大:zhang da" "校长:xiao zhang" "成长:cheng zhang" "增长:zeng zhang"
    "家长:jia zhang" "部长:bu zhang" "市长:shi zhang" "队长:dui zhang"
    "厂长:chang zhang" "重庆:chong qing" "重要:zhong yao"
    "银行:yin hang" "音乐:yin yue" "快乐:kuai le" "还是:hai shi" "首都:shou du"
    "都是:dou shi" "了解:liao jie" "睡觉:shui jiao" "觉得:jue de"
    "只有:zhi you" "一只:yi zhi" "数学:shu xue" "少年:shao nian"
    "多少:duo shao" "天空:tian kong" "空白:kong bai"
)

to_text() {
    local src="$1" pair
    for pair in "${POLY[@]}"; do
        src=${src//"${pair%%:*}"/ ${pair#*:}}
    done
    printf '%s' "$src" | uconv -x Han-Latin 2>/dev/null |
        python3 -c 'import sys,unicodedata
s=unicodedata.normalize("NFD",sys.stdin.read())
words=["".join(c for c in w if c.isalnum() and ord(c)<128).lower() for w in s.split()]
words=[w for w in words if w]
mode=sys.argv[1]
print("".join(words) if mode=="full" else "".join(w[0] for w in words))' "$2"
}

if printf '%s' "$KW" | grep -q '[^ -~]'; then
    [ "$FULL" = 1 ] && TEXT=$(to_text "$KW" full) || TEXT=$(to_text "$KW" init)
else
    TEXT=$(printf '%s' "$KW" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9')
fi
[ -n "$TEXT" ] || { echo "无法转换关键词: $KW" >&2; exit 1; }

seq=""
for ((i = 0; i < ${#TEXT}; i++)); do
    ch=$(printf '%s' "${TEXT:i:1}" | tr 'a-z' 'A-Z')
    idx=$(printf '%s' "$MAP" | grep -bo "$ch" | head -1 | cut -d: -f1)
    [ -n "$idx" ] || continue
    x=${COLS[$((idx % 6))]}
    y=${ROWS[$((idx / 6))]}
    seq+="input tap $x $y; sleep 0.6; "
done

"${ADB[@]}" connect "$TV_SERIAL" >/dev/null 2>&1
"${ADB[@]}" shell input keyevent 224
"${ADB[@]}" shell am force-stop com.ktcp.video
"${ADB[@]}" shell am start -n com.ktcp.video/.activity.MainActivity >/dev/null

# 冷启动/开屏广告：等首页出现（截图够大且 OCR 能看到「搜索」或「首页」）
ready=0
for _ in $(seq 1 12); do
    sleep 2
    "${ADB[@]}" exec-out screencap -p > /tmp/tencent_ready.png
    size=$(stat -c%s /tmp/tencent_ready.png 2>/dev/null || echo 0)
    [ "$size" -gt 400000 ] || continue
    if "$DIR/ocr.sh" /tmp/tencent_ready.png 2>/dev/null | grep -qE '搜索|首页|猜你想搜'; then
        ready=1
        break
    fi
done
[ "$ready" = 1 ] || { echo "app 未就绪（超时）" >&2; exit 4; }

shot() { "${ADB[@]}" exec-out screencap -p > /tmp/tencent_search.png; }

field_text() {
    "$DIR/ocr.sh" "$1" 2>/dev/null | python3 -c '
import json,sys,re
try: boxes=json.load(sys.stdin)
except Exception: print(""); sys.exit()
parts=[b["text"] for b in boxes if 160<=b["y"]<=215 and 335<=b["x"]<=720]
print(re.sub(r"[^A-Za-z0-9]","","".join(parts)).upper())
'
}

read_field() {
    shot
    FIELD=$(field_text /tmp/tencent_search.png)
    if [ -z "$FIELD" ]; then
        sleep 1; shot
        FIELD=$(field_text /tmp/tencent_search.png)
    fi
}

tap() { "${ADB[@]}" shell "input tap $1 $2"; sleep 0.8; }

# 1) 进入搜索页，清空输入框
tap 121 136; sleep 1
"${ADB[@]}" shell "input tap 366 275; sleep 0.5; input tap 366 275"; sleep 0.8
shot; read_field
if [ -n "$FIELD" ]; then
    echo "清空失败（$FIELD），重试" >&2
    "${ADB[@]}" shell "input tap 366 275; sleep 0.5; input tap 366 275"; sleep 0.8
    shot; read_field
fi
[ -z "$FIELD" ] || { echo "无法清空输入框（$FIELD）" >&2; exit 4; }

# 2) 逐字母输入，每敲一次都截图核对
for ((i = 0; i < ${#TEXT}; i++)); do
    ch=$(printf '%s' "${TEXT:i:1}" | tr 'a-z' 'A-Z')
    want=${TEXT:0:i+1}; want=${want^^}
    idx=$(printf '%s' "$MAP" | grep -bo "$ch" | head -1 | cut -d: -f1)
    x=${COLS[$((idx % 6))]}; y=${ROWS[$((idx / 6))]}
    ok=0
    for _ in 1 2 3 4 5 6; do
        read_field
        [ "$FIELD" = "$want" ] && { ok=1; break; }
        if [ ${#FIELD} -gt ${#want} ]; then
            tap 531 275
        else
            tap $x $y
        fi
    done
    read_field
    [ "$ok" = 1 ] && [ "$FIELD" = "$want" ] || {
        echo "输入「$want」失败，当前「$FIELD」（截图 /tmp/tencent_search.png）" >&2
        exit 4
    }
done
echo "输入完成: $FIELD"

# 3) 焦点回「清空」→ 右移 3 次到候选 → OK
tap 366 275
"${ADB[@]}" shell "input keyevent 22; input keyevent 22; input keyevent 22"; sleep 0.6
shot
"${ADB[@]}" shell "input keyevent 23"; sleep 3
"${ADB[@]}" exec-out screencap -p > /tmp/tencent_result.png
echo "结果截图: /tmp/tencent_result.png"

if [ -n "$EXPECT" ]; then
    RES=$("$DIR/ocr.sh" /tmp/tencent_result.png | python3 -c '
import json,sys,re
expect=re.sub(r"\s+","",sys.argv[1])
try: boxes=json.load(sys.stdin)
except Exception: print("OCR_FAIL\t"); sys.exit()
text=re.sub(r"\s+","","".join(b["text"] for b in boxes))
print(("OK" if expect in text else "MISMATCH")+"\t"+text[:120])
' "$EXPECT")
    case "$RES" in
        OK*) echo "OCR 校验: 匹配" ;;
        *)   echo "OCR 校验: 未匹配 ($RES)"; exit 3 ;;
    esac
fi

if [ "$PLAY" = 1 ]; then
    "${ADB[@]}" shell "input keyevent 23"
    sleep 3
    "${ADB[@]}" exec-out screencap -p > /tmp/tencent_play.png
    echo "播放截图: /tmp/tencent_play.png"
fi

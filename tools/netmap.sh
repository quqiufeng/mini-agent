#!/usr/bin/env bash
# tools/netmap.sh — 局域网设备与拓扑扫描（本机实现）
# @desc 扫描本机所在局域网：UDP 触发 ARP + 常见端口探测，识别主机名/MAC 厂商/服务，生成 NETWORK.local.md、devices.local.json、devices.local.env
# @usage tools/netmap.sh scan [CIDR]   # 默认扫描本机网段
#        tools/netmap.sh show          # 显示上次拓扑
#        tools/netmap.sh sources       # 输出设备 IP 的 shell 变量
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${NETMAP_OUT_DIR:-$(cd "$DIR/.." && pwd)}"
export NETMAP_OUT_DIR="$OUT_DIR"

exec python3 - "$@" <<'PY'
import concurrent.futures as cf
import ipaddress, json, os, re, socket, subprocess, sys, time

OUT_DIR = os.environ["NETMAP_OUT_DIR"]
PORTS = [22, 80, 443, 554, 5005, 5555, 8000, 8080, 9000, 9222]

PHONE_MAC = os.environ.get("PHONE_MAC", "76:d0:b4:67:89:a9").lower()
PHONE_LABEL = os.environ.get("PHONE_LABEL", "手机 Z18")

VENDORS = {
    "a0:36:79": "中国电信", "00:d8:61": "Micro-Star(MSI)", "24:97:ed": "极空间",
    "b8:27:eb": "Raspberry Pi", "dc:a6:32": "Raspberry Pi", "e4:5f:01": "Raspberry Pi",
    "f0:9f:c2": "Ubiquiti", "00:1d:7e": "Cisco-Linksys", "3c:84:6a": "TP-Link",
    "50:c7:bf": "TP-Link", "b0:be:76": "TP-Link", "00:0c:29": "VMware",
    "ac:84:c6": "TP-Link", "c4:e9:84": "TP-Link", "f4:f2:6d": "TP-Link",
    "2c:f0:5d": "Micro-Star(MSI)", "00:1b:21": "Intel", "3c:7c:3f": "Intel",
    "8c:16:45": "Intel", "a4:bb:6d": "Intel", "e4:54:e8": "Intel", "00:1e:64": "Intel",
    "d8:3a:dd": "Intel", "1c:69:7a": "Intel", "58:11:22": "H3C", "00:23:89": "H3C",
    "70:3a:cb": "H3C", "00:0f:e2": "Huawei", "48:46:fb": "Huawei", "e0:24:7f": "Huawei",
    "00:26:66": "Sony", "30:f9:ed": "Sony", "78:84:3c": "Sony", "fc:0f:e6": "Sony",
    "18:59:36": "Xiaomi", "64:09:80": "Xiaomi", "8c:be:be": "Xiaomi",
    "dc:2c:26": "Espressif", "24:0a:c4": "Espressif", "84:0d:8e": "Espressif",
    "00:1a:11": "Google", "f4:f5:d8": "Google", "00:17:88": "Philips Hue",
}

def sh(cmd, timeout=8):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except Exception:
        return ""

def lan():
    for line in sh(["ip", "-4", "-o", "addr", "show", "scope", "global"]).splitlines():
        m = re.search(r"^\d+:\s+(\S+)\s+inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)", line)
        if m and not m.group(2).startswith("198.18."):
            net = ipaddress.ip_network(f"{m.group(2)}/{m.group(3)}", strict=False)
            return m.group(1), net, m.group(2)
    sys.exit("找不到局域网地址")

def neigh(dev):
    out = {}
    for line in sh(["ip", "-4", "neigh", "show", "dev", dev]).splitlines():
        m = re.match(r"(\d+\.\d+\.\d+\.\d+)\s+.*lladdr\s+([0-9a-f:]+)\s+(\w+)", line)
        if m:
            out[m.group(1)] = {"mac": m.group(2), "state": m.group(3)}
    return out

def nudge(ip):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(0.05)
    try:
        s.sendto(b"\x00", (ip, 9))
    except OSError:
        pass
    s.close()

def probe(ip):
    found = []
    for p in PORTS:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(0.2)
        try:
            if s.connect_ex((ip, p)) == 0:
                found.append(p)
        finally:
            s.close()
    return found

def hostname(ip):
    try:
        r = subprocess.run(["getent", "hosts", ip], capture_output=True, text=True, timeout=1.2)
        parts = r.stdout.split()
        if len(parts) >= 2 and not parts[1].startswith("ip-"):
            return parts[1]
        if len(parts) >= 2:
            return parts[1]
    except Exception:
        pass
    return ""

def vendor(mac):
    return VENDORS.get(mac[:8].lower(), "")

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "scan"
    if mode == "show":
        p = os.path.join(OUT_DIR, "NETWORK.local.md")
        print(open(p).read() if os.path.exists(p) else "还没有结果，先运行 netmap.sh scan")
        return
    if mode == "sources":
        p = os.path.join(OUT_DIR, "devices.local.env")
        print(open(p).read() if os.path.exists(p) else "还没有结果，先运行 netmap.sh scan")
        return
    cidr = sys.argv[2] if len(sys.argv) > 2 else None
    dev, net, me = lan()
    if cidr:
        net = ipaddress.ip_network(cidr, strict=False)
    hosts = [str(h) for h in net.hosts()]
    print(f"扫描 {net} ({dev})，本机 {me} …")
    with cf.ThreadPoolExecutor(max_workers=128) as ex:
        list(ex.map(nudge, hosts))
    time.sleep(1.5)
    table = neigh(dev)
    alive = set(table) | {me}
    with cf.ThreadPoolExecutor(max_workers=32) as ex:
        ports = dict(zip(alive, ex.map(probe, alive)))
        names = dict(zip(alive, ex.map(hostname, alive)))
    devices = []
    for ip in sorted(alive, key=lambda s: tuple(map(int, s.split(".")))):
        info = table.get(ip, {})
        p = ports.get(ip, [])
        if ip != me and not p and not info:
            continue
        devices.append({
            "ip": ip, "mac": info.get("mac", ""), "vendor": vendor(info.get("mac", "")),
            "hostname": names.get(ip, ""), "ports": p,
            "self": ip == me,
        })
    known = {"192.168.1.1": "网关/光猫", "192.168.1.10": "主电脑(能力主机)",
             "192.168.1.53": "极空间 NAS", "192.168.1.68": "客厅小机箱(本机)",
             "192.168.1.59": "手机2 Redmi Note 14 5G（微信）",
             "192.168.1.110": "Sony 电视", "192.168.1.111": "TP-Link 摄像头",
             "192.168.1.52": "H3C AP"}
    for d in devices:
        d["role"] = known.get(d["ip"], "")
        if not d["role"]:
            if d["mac"].lower() == PHONE_MAC: d["role"] = PHONE_LABEL
            elif 5005 in d["ports"]: d["role"] = "NAS/WebDAV"
            elif 554 in d["ports"]: d["role"] = "摄像头/RTSP"
            elif 5555 in d["ports"]: d["role"] = "Android/TV(adb)"
            elif 9222 in d["ports"]: d["role"] = "Chrome 调试"
            elif 22 in d["ports"]: d["role"] = "SSH 主机"
            elif d["mac"].startswith("dc:a6:32") or d["mac"].startswith("b8:27:eb"):
                d["role"] = "树莓派"
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    lines = [f"# 局域网拓扑（本机扫描）", "", f"> 生成：{ts}；网段：{net}；本机：{me}（{dev}）", "", "```text",
             f"{known.get('192.168.1.1','网关')} {('192.168.1.1')}"]
    for d in devices:
        if d["ip"] == "192.168.1.1":
            continue
        label = d["role"] or d["hostname"] or d["vendor"] or "未识别设备"
        detail = d["ip"]
        if d["hostname"] and d["hostname"] != label: detail += f" {d['hostname']}"
        if d["vendor"] and d["vendor"] != label: detail += f" [{d['vendor']}]"
        if d["mac"]: detail += f" mac={d['mac']}"
        if d["ports"]: detail += " ports=" + ",".join(map(str, d["ports"]))
        lines.append(f"  ├─ {label}  {detail}")
    lines += ["```", ""]
    md = "\n".join(lines)
    open(os.path.join(OUT_DIR, "NETWORK.local.md"), "w").write(md)
    open(os.path.join(OUT_DIR, "devices.local.json"), "w").write(
        json.dumps({"generated": ts, "network": str(net), "self": me, "devices": devices},
                   ensure_ascii=False, indent=2))
    env = [f'NETMAP_SELF="{me}"', f'NETMAP_NET="{net}"']
    alias = {"192.168.1.1": "GATEWAY", "192.168.1.10": "MAINPC",
             "192.168.1.53": "NAS", "192.168.1.68": "MINIPC",
             "192.168.1.59": "PHONE2",
             "192.168.1.110": "TV", "192.168.1.111": "CAMERA",
             "192.168.1.52": "AP"}
    alias_role = {PHONE_LABEL: "PHONE"}
    for d in devices:
        key = alias.get(d["ip"]) or alias_role.get(d["role"])
        if not key:
            key = re.sub(r"[^A-Z0-9]+", "_", (d["hostname"] or d["role"] or "").upper()).strip("_")
        if not key:
            key = "DEV_" + d["ip"].split(".")[-1]
        env.append(f'NETMAP_{key}_IP="{d["ip"]}"')
    open(os.path.join(OUT_DIR, "devices.local.env"), "w").write("\n".join(env) + "\n")
    print(md)
    print(f"已写入 {OUT_DIR}/NETWORK.local.md, devices.local.json, devices.local.env")

if __name__ == "__main__":
    main()
PY

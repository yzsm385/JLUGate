#!/bin/zsh
# 校园网「连得上、但海外站点不通」的一键排查。
#
# 为什么单独做这个脚本：症状是「信号满格、能连上、不报错、不弹门户、就是没网」，
# 但实测国内站点正常、部分海外站点也正常——这说明不是"断网"，而是某一层
# （DNS / 代理 / 校园网出口）把特定流量吞了。光看现象分不清是哪一层，
# 必须把每一层单独测一遍。
#
# 只读：不改任何系统设置、不发认证包、不写仓库文件。
#
# 用法：./scripts/diagnose-overseas.sh
#      （macOS 默认 shell 就是 zsh，直接跑即可）

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROBE="$ROOT/dist/jlugate-probe"
OUT="${TMPDIR:-/tmp}/jlugate-overseas-$(date +%Y%m%d-%H%M%S).txt"

say() { printf '\n===== %s =====\n' "$1" }

# 打印一个域名的探测结果：状态码 + 耗时
# 000 表示没通（超时 / DNS 失败 / 连接被重置）
probe_host() {
    local host=$1
    shift
    local out
    out=$(curl -s -o /dev/null -w '%{http_code} %{time_total}s' --max-time 12 "$@" "https://$host" 2>/dev/null)
    printf '  %-22s %s\n' "$host" "${out:-超时}"
}

run_all() {
    echo "JLU Gate 海外访问排查   $(date '+%Y-%m-%d %H:%M:%S')"
    echo "输出同时写入：$OUT"

    say "1. 当前连的是哪个网"
    /usr/sbin/networksetup -getairportnetwork en0 2>/dev/null || echo "(读取失败)"
    echo "--- 接口地址 ---"
    ifconfig 2>/dev/null | grep -E '^en[0-9]|^utun[0-9]|inet ' | grep -v '127.0.0.1'

    say "2. 默认路由（看代理有没有接管）"
    netstat -rn 2>/dev/null | grep '^default' | head -6

    say "3. DNS（198.18.x.x 表示被代理劫持成 fake-ip）"
    scutil --dns 2>/dev/null | grep 'nameserver' | head -6

    say "4. 代理模式"
    if [ -x "$PROBE" ]; then
        "$PROBE" --net-detail 2>/dev/null | sed -n '/== 代理模式 ==/,/== DNS ==/p' | head -12
    else
        echo "(没找到 $PROBE，跳过)"
    fi

    say "5. 海外站点：走系统默认出口（会经过代理）"
    local host
    for host in google.com brave.com duckduckgo.com bing.com; do
        probe_host "$host"
    done

    say "6. 海外站点：忽略代理环境变量（注意：这绕不过 TUN）"
    # --noproxy 只忽略 http_proxy/https_proxy 环境变量，绕不过 TUN 虚拟网卡抢走的默认路由。
    # 所以下面这组结果**不能**当作"直连测试"：只要有 utun 抢着默认路由，它照样进隧道。
    if netstat -rn 2>/dev/null | grep '^default' | grep -q 'utun'; then
        echo "⚠️  检测到 utun 正持有默认路由 —— 下面这组仍然会经过代理，不是真直连。"
        echo "    要测真直连，请完全退出代理软件（小火箭 / Clash）后重跑本脚本。"
    else
        echo "（没有 utun 抢默认路由，下面这组就是真直连）"
    fi
    for host in google.com brave.com duckduckgo.com bing.com; do
        probe_host "$host" --noproxy '*'
    done

    say "7. 国内站点对照（排除「整个网都坏了」）"
    for host in baidu.com www.mihoyo.com; do
        probe_host "$host"
    done

    say "8. 校内站点（确认校园网认证有没有生效）"
    for host in iedu.jlu.edu.cn mails.jlu.edu.cn; do
        probe_host "$host"
    done

    say "9. DNS 解析对照（看是否所有域名都被塞进 198.18 网段）"
    local ip
    for host in google.com brave.com baidu.com iedu.jlu.edu.cn; do
        ip=$(dig +short +time=3 +tries=1 "$host" 2>/dev/null | tail -1)
        printf '  %-22s %s\n' "$host" "${ip:-解析失败}"
    done

    say "10. 结论提示"
    cat <<'EOF'
状态码怎么看：
  200 / 301 / 302  → 通（跳转也算通，说明能握上手）
  000              → 没通（超时 / DNS 失败 / 连接被重置）

对照方法：
  · 第 5 组全通                 → 代理和校园网都没问题，可能是特定站点被限速 / 风控
  · 第 5 组部分 000             → 链路不稳或部分域名被拦，看是哪几个挂
  · 第 5 组全 000、第 7 组通    → 海外被针对，国内正常（换节点 / 协议 / 端口）
  · 第 5、7 组全 000            → 整条链路不通，先解决认证（第 8 组也会是 000）
  · 第 8 组挂但第 7 组通        → 校园网认证没生效（没登录 / 掉线 / 被挤）
  · 第 9 组全是 198.18.x.x      → DNS 被代理劫持成 fake-ip（正常现象，不代表故障）

关键提醒：只要第 6 组开头出现「utun 正持有默认路由」，第 6 组就**不能**当直连用。
真要对比"代理 vs 直连"，必须完全退出代理软件后重跑本脚本。
EOF

    echo ""
    echo "排查完成。把上面的输出整段发回来即可。"
}

# 用 tee 而不是 `exec > >(tee ...)`：进程替换在脚本退出时可能来不及把最后几行
# 刷进文件，而"最后几行"恰好是结论。
run_all 2>&1 | tee "$OUT"

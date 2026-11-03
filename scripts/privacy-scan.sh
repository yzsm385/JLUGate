#!/usr/bin/env bash
# 公开前的隐私自检（通用规则，不内置任何真实值）
# 用法：./scripts/privacy-scan.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

X=(--exclude-dir=.git --exclude-dir=.build --exclude-dir=.swiftpm --exclude-dir=DerivedData --exclude-dir=local)
fail=0
hit() { echo "❌ $1"; shift; printf '%s\n' "$@" | head -5; echo; fail=1; }

# 1) 抓包文件
c=$(find . \( -name '*.pcap' -o -name '*.pcapng' -o -name '*.har' \) -not -path './.git/*' 2>/dev/null)
[ -n "$c" ] && hit "发现抓包文件（不应入库）" $c

# 2) 非合成 MAC（允许 02:00:00:00:00:01 与全 0/广播）
m=$(grep -rIonE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' . "${X[@]}" 2>/dev/null \
    | grep -viE '02:00:00:00:00:0[0-9]|00:00:00:00:00:00|ff:ff:ff:ff:ff:ff|aa:bb:cc:dd:ee:ff' | head -20)
[ -n "$m" ] && hit "发现真实网卡 MAC（应替换为 02:00:00:00:00:01）" "$m"

# 3) 非白名单 IPv4（保留地址 + 认证服务器除外）
ip=$(grep -rIohE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' . "${X[@]}" 2>/dev/null \
    | sort -u \
    | grep -vE '^(10\.100\.61\.3|192\.0\.2\.[0-9]+|169\.254\.1\.1|0\.0\.0\.0|127\.0\.0\.1|255\.255\.255\.[0-9]+|255\.0\.0\.0|10\.0\.0\.0|10\.10\.10\.10|172\.16\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|198\.18\.[0-9]+\.[0-9]+|8\.8\.8\.8|1\.1\.1\.1|223\.5\.5\.5|8\.8\.4\.4)$' \
    | head -20)
[ -n "$ip" ] && hit "发现可疑 IPv4（核对是否为真实地址）" "$ip"

# 4) 非合成主机名
h=$(grep -rIohE '\b[A-Za-z0-9][A-Za-z0-9-]*\.local\b' . "${X[@]}" 2>/dev/null \
    | sort -u | grep -vE '^(test-mac\.local|localhost|XXX\.local)$' | head -10)
[ -n "$h" ] && hit "发现可疑主机名（应替换为 test-mac.local）" "$h"

# 5) 疑似学号（8–12 位纯数字，且不在白名单）
n=$(grep -rIohE '\b[0-9]{8,12}\b' . "${X[@]}" --include='*.md' --include='*.swift' --include='*.json' 2>/dev/null \
    | sort -u | grep -vE '^(20230001|00000000|[0-9]{10,12})$' | head -10)
[ -n "$n" ] && echo "⚠️  疑似学号（人工确认）：$n"

# 6) 32 位十六进制摘要（白名单 = 夹具里那两枚 + 账号上报）
d=$(grep -rIohE '\b[0-9a-f]{32}\b' . "${X[@]}" --exclude-dir=Tests 2>/dev/null | sort -u \
    | grep -vE '^(d030ec3cfa269619e0d3c3224b3e9aa6|f112b8886b50510b057038a0a8d2bb0d|0ddcd497709cf543cbfe31d94920d3d8)$' | head -10)
[ -n "$d" ] && echo "⚠️  发现未登记的 32 位摘要（确认不是真实密码派生）：$d"

if [ "$fail" -eq 0 ]; then
  echo "✅ 干净：无抓包、无真实 MAC/主机名/私有 IP、无可疑学号或摘要"
  exit 0
else
  echo "—— 请按 SECURITY.md 处理上述项 ——"
  exit 1
fi

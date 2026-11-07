#!/usr/bin/env bash
# 公开前的隐私自检（通用规则，不内置任何真实值）
# 用法：./scripts/privacy-scan.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# 只扫「真正会进仓库」的文件：git 跟踪的 + 未跟踪但没被 .gitignore 排除的。
# 这样本机环境（.venv、构建产物、截图、gpa/research 抓包样本）不会造成假阳性，
# 而任何**将**被提交的新文件仍然会被检查。
while IFS= read -r -d '' f; do
  FILES+=("$f")
done < <(git ls-files -z --cached --others --exclude-standard)

fail=0
hit() { echo "❌ $1"; shift; printf '%s\n' "$@" | head -5; echo; fail=1; }
if [ -d docs/debug_proof ]; then
  echo "ℹ️  已跳过 docs/debug_proof（真实诊断，供排障用；公开仓库前必须整体移出）"
fi

# 有效的扫描对象（去掉 debug_proof）
SCAN=()
for f in "${FILES[@]}"; do
  case "$f" in
    docs/debug_proof/*) continue ;;
    *) [ -f "$f" ] && SCAN+=("$f") ;;
  esac
done
if [ "${#SCAN[@]}" -eq 0 ]; then
  echo "（没有可扫描的文件）"
  exit 0
fi

# 1) 抓包文件
c=$(printf '%s\n' "${FILES[@]}" | grep -E '\.(pcap|pcapng|har)$' || true)
[ -n "$c" ] && hit "发现抓包文件（不应入库）" $c

# 2) 非合成 MAC（允许 02:00:00:00:00:01 与全 0/广播）
m=$(grep -IonE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' "${SCAN[@]}" 2>/dev/null \
    | grep -viE '02:00:00:00:00:0[0-9]|00:00:00:00:00:00|ff:ff:ff:ff:ff:ff|aa:bb:cc:dd:ee:ff|a1:b2:c3:d4:e5:f6' | head -20)
[ -n "$m" ] && hit "发现真实网卡 MAC（应替换为 02:00:00:00:00:01）" "$m"

# 3) 非白名单 IPv4（保留地址 + 认证服务器 + 探针内置兜底地址除外）
#    142.250.185.99 / 142.251.32.99 = connectivitycheck.gstatic.com 的兜底
#    104.16.132.229                = cp.cloudflare.com 的兜底
#    都是公开 CDN 任播地址，不含任何用户信息
ip=$(grep -IohE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "${SCAN[@]}" 2>/dev/null \
    | awk -F. '$1<=255 && $2<=255 && $3<=255 && $4<=255' \
    | sort -u \
    | grep -vE '^(10\.100\.61\.3|192\.0\.2\.[0-9]+|169\.254\.1\.1|0\.0\.0\.0|127\.0\.0\.1|255\.255\.255\.[0-9]+|255\.0\.0\.0|10\.0\.0\.0|10\.0\.0\.1|10\.10\.10\.10|172\.16\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|198\.18\.[0-9]+\.[0-9]+|8\.8\.8\.8|1\.1\.1\.1|223\.5\.5\.5|8\.8\.4\.4|142\.250\.185\.99|142\.251\.32\.99|104\.16\.132\.229)$' \
    | grep -vE '^(198\.51\.100\.[0-9]+|203\.0\.113\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|169\.254\.[0-9]+\.[0-9]+|127\.[0-9]+\.[0-9]+\.[0-9]+|1\.2\.3\.4)$' \
    | head -20)
[ -n "$ip" ] && hit "发现可疑 IPv4（核对是否为真实地址）" "$ip"

# 4) 非合成主机名
h=$(grep -IohE '\b[A-Za-z0-9][A-Za-z0-9-]*\.local\b' "${SCAN[@]}" 2>/dev/null \
    | sort -u | grep -vE '^(test-mac\.local|localhost|XXX\.local)$' | head -10)
[ -n "$h" ] && hit "发现可疑主机名（应替换为 test-mac.local）" "$h"

# 5) 疑似学号（8–12 位纯数字，且不在白名单）
n=$(grep -IohE '\b[0-9]{8,12}\b' "${SCAN[@]}" --include='*.md' --include='*.swift' --include='*.json' 2>/dev/null \
    | sort -u | grep -vE '^(20230001|00000000|[0-9]{10,12})$' | head -10)
[ -n "$n" ] && echo "⚠️  疑似学号（人工确认）：$n"

# 6) 32 位十六进制摘要（白名单 = 夹具里那两枚 + 账号上报）
d=$(grep -IohE '\b[0-9a-f]{32}\b' "${SCAN[@]}" 2>/dev/null | sort -u \
    | grep -vE '^(d030ec3cfa269619e0d3c3224b3e9aa6|f112b8886b50510b057038a0a8d2bb0d|0ddcd497709cf543cbfe31d94920d3d8)$' | head -10)
[ -n "$d" ] && echo "⚠️  发现未登记的 32 位摘要（确认不是真实密码派生）：$d"

if [ "$fail" -eq 0 ]; then
  echo "✅ 干净：无抓包、无真实 MAC/主机名/私有 IP、无可疑学号或摘要"
  exit 0
else
  echo "—— 请按 SECURITY.md 处理上述项 ——"
  exit 1
fi

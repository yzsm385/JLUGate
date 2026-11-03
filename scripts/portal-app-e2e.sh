#!/usr/bin/env bash
# 端到端自检：真实 App 二进制 + 本地模拟门户，跑通「探测 → 登录窗 → 204 → online」。
#
# 默认用脚本化浏览器（无人值守）；加 --window 则用真实 WKWebView（会弹窗，需要手点）。
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="scripted"
[ "${1:-}" = "--window" ] && MODE="window"

PORT=18080
LOG="$HOME/Library/Logs/JLUGate/agent.log"

cleanup() {
    pkill -f "JLU Gate.app/Contents/MacOS/JLUGate" 2>/dev/null || true
    pkill -f "portal_server.py --port $PORT" 2>/dev/null || true
}
trap cleanup EXIT

cleanup
sleep 0.5

echo "==> mock portal on :$PORT"
python3 Tools/mock-portal/portal_server.py --port "$PORT" >/tmp/jlugate-portal-e2e.log 2>&1 &
sleep 1

echo "==> build app bundle ($MODE)"
if [ "$MODE" = "scripted" ]; then
    ./scripts/make-app-bundle.sh --dev-portal >/dev/null
else
    ./scripts/make-app-bundle.sh --dev-portal >/dev/null
    # 去掉 scripted，让 App 用真实 WKWebView
    /usr/bin/sed -i '' '/"browser": "scripted"/d' "dist/JLU Gate.app/Contents/Resources/dev-config.json"
    codesign --force --sign - "dist/JLU Gate.app" >/dev/null 2>&1
fi

# 只看本次运行新产生的日志（旧的成功记录不能算数）
BASE=$( (wc -l < "$LOG" 2>/dev/null || echo 0) | tr -d ' ' )
new_log() { tail -n "+$((BASE + 1))" "$LOG" 2>/dev/null || true; }

echo "==> launch"
open -n "dist/JLU Gate.app"
for _ in $(seq 1 20); do
    sleep 1
    if new_log | grep -q "AuthState.online"; then
        echo "OK  portal -> online"
        new_log | grep -E "portal|online" | tail -3 || true
        exit 0
    fi
    if new_log | grep -q "portal window loaded" && [ "$MODE" = "window" ]; then
        echo "OK  WKWebView 已加载登录页（这一模式需要人工在窗口里登录）"
        exit 0
    fi
done

echo "FAIL 20s 内没到 online；最近日志："
new_log | tail -15
exit 1

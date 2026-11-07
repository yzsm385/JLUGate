#!/usr/bin/env bash
# 旧版适配打包（macOS 14+，无 Liquid Glass）。
# 和 make-app-bundle.sh 平行：构建 AppCompatCompileCheck，装成 dist/JLU Gate (Compat).app。
#
# 用法：./scripts/make-app-bundle-compat.sh [--debug]
# 产物：dist/JLU Gate (Compat).app（可直接 open，也可拖进 /Applications 试用）
#
# 和新版（dist/JLU Gate.app）的区别：
#   · LSMinimumSystemVersion = 14.0（新版是 26.0）
#   · 不引用任何 macOS 26 API（Liquid Glass），老系统不会因 unrecognized selector 崩
#   · bundle id 相同（dev.jlugate.app），启动守卫会顶掉同 id 的旧进程；两份不要同时装
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
DEV=0
for arg in "$@"; do
    case "$arg" in
        --debug) CONFIG="debug" ;;
        --dev)   DEV=1 ;;
        --dev-portal) DEV=2 ;;
        --dev-autostart) DEV=3 ;;
        --dev-net-detail) DEV=4 ;;
        --dev-settings) DEV=5 ;;
        --dev-save-wired) DEV=6 ;;
        --dev-ui-probe) DEV=7 ;;
        --dev-panel) DEV=8 ;;
    esac
done

# 本沙箱环境需要把缓存指到仓库内；普通 Mac 上这些变量无害。
export TMPDIR="${TMPDIR:-$PWD/.build/tmp}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/modulecache}"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH"

echo "==> build ($CONFIG) [compat: macOS 14, no Liquid Glass]"
swift build -c "$CONFIG" --product AppCompatCompileCheck \
    --disable-sandbox --scratch-path .build --cache-path .build/cache

BIN="$(swift build -c "$CONFIG" --product AppCompatCompileCheck \
    --disable-sandbox --scratch-path .build --cache-path .build/cache --show-bin-path)"

# LaunchServices 判断“这个 App 能不能在这台 Mac 上启动”时读的是 Mach-O 的
# LC_BUILD_VERSION minos，不是 Info.plist 的 LSMinimumSystemVersion。
# 部署目标一旦被写回 26.0，这里产出的包在 macOS 14/15 上就会弹
# “这个版本不能与此版本的 macOS 配合使用”，所以打包前硬性校验。
echo "==> verify minos（二进制必须按 macOS 14 编译）"
MINOS="$(vtool -show-build "$BIN/AppCompatCompileCheck" | awk '/minos/ {print $2; exit}')"
if [ "$MINOS" != "14.0" ]; then
    echo "ERROR: 二进制 minos=$MINOS，旧版适配包必须是 14.0。" >&2
    echo "       检查 Package.swift 的 platforms，别把部署目标写回 26.0。" >&2
    exit 1
fi

APP="dist/JLU Gate (Compat).app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> assemble .app"
cp "$BIN/AppCompatCompileCheck" "$APP/Contents/MacOS/JLUGate"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>JLU Gate</string>
    <key>CFBundleDisplayName</key>     <string>JLU Gate</string>
    <key>CFBundleIdentifier</key>      <string>dev.jlugate.app</string>
    <key>CFBundleExecutable</key>      <string>JLUGate</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.4.10</string>
    <key>CFBundleVersion</key>         <string>BUILD_STAMP</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 yzsm385, MIT License</string>
</dict>
</plist>
PLIST

if [ "$DEV" = "1" ]; then
    echo "==> dev harness config (mock gateway 127.0.0.1:61441)"
    cat > "$APP/Contents/Resources/dev-config.json" <<'DEVJSON'
{
  "server": "127.0.0.1",
  "port": 61441,
  "autostart": true
}
DEVJSON
fi

if [ "$DEV" = "3" ]; then
    echo "==> dev harness: autostart only (real network)"
    echo '{ "autostart": true }' > "$APP/Contents/Resources/dev-config.json"
fi

if [ "$DEV" = "4" ]; then
    echo "==> dev harness: open network detail on launch"
    echo '{ "openNetDetail": true }' > "$APP/Contents/Resources/dev-config.json"
fi

if [ "$DEV" = "8" ]; then
    echo "==> dev harness: open panel on launch"
    echo "{ \"openPanel\": true, \"startPanel\": \"${PANEL:-main}\", \"runInspect\": ${RUNINSPECT:-false}, \"wizardNetwork\": ${WIZNET:-false} }" \
        > "$APP/Contents/Resources/dev-config.json"
fi

if [ "$DEV" = "7" ]; then
    echo "==> dev harness: UI probe"
    echo '{ "uiProbe": true }' > "$APP/Contents/Resources/dev-config.json"
fi

if [ "$DEV" = "6" ]; then
    echo "==> dev harness: simulate wired save"
    echo '{ "saveWired": true }' > "$APP/Contents/Resources/dev-config.json"
fi

if [ "$DEV" = "5" ]; then
    echo "==> dev harness: open settings on launch"
    echo '{ "openSettings": true }' > "$APP/Contents/Resources/dev-config.json"
fi

if [ "$DEV" = "2" ]; then
    echo "==> dev harness config (mock portal http://127.0.0.1:18080)"
    cat > "$APP/Contents/Resources/dev-config.json" <<'DEVJSON'
{
  "portal": "http://127.0.0.1:18080",
  "browser": "scripted",
  "autostart": true
}
DEVJSON
fi

# 先写 CFBundleVersion，再签名。
# 反过来（签名后改 Info.plist）会让签名立刻失效，Gatekeeper 报"已损坏"。
BUILD_STAMP="$(date -u +%Y%m%d%H%M)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_STAMP" "$APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_STAMP" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> ad-hoc sign"
codesign --force --sign - "$APP"

echo "==> verify（签名必须有效，否则 Gatekeeper 会报"已损坏"）"
codesign --verify --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature" || true
echo "OK -> $APP (build $BUILD_STAMP, macOS 14+)"

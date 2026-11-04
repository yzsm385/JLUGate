#!/usr/bin/env bash
# 无开发者账号时的本地打包：把 SwiftPM 构建出来的可执行文件装成 .app，ad-hoc 签名。
#
# 用法：./scripts/make-app-bundle.sh [--debug]
# 产物：dist/JLU Gate.app（可直接 open，也可拖进 /Applications 试用）
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

echo "==> build ($CONFIG)"
swift build -c "$CONFIG" --product AppCompileCheck \
    --disable-sandbox --scratch-path .build --cache-path .build/cache

BIN="$(swift build -c "$CONFIG" --product AppCompileCheck \
    --disable-sandbox --scratch-path .build --cache-path .build/cache --show-bin-path)"

APP="dist/JLU Gate.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> assemble .app"
cp "$BIN/AppCompileCheck" "$APP/Contents/MacOS/JLUGate"

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
    <key>CFBundleShortVersionString</key><string>0.3.11</string>
    <key>CFBundleVersion</key>         <string>BUILD_STAMP</string>
    <key>LSMinimumSystemVersion</key>  <string>26.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSHumanReadableCopyright</key><string>MIT</string>
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
# 反过来（签名后改 Info.plist）会让签名立刻失效，Gatekeeper 报"已损坏"——
# 0.3.11 及之前所有包都有这个 bug。
BUILD_STAMP="$(date -u +%Y%m%d%H%M)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_STAMP" "$APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_STAMP" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> ad-hoc sign"
codesign --force --sign - "$APP"

echo "==> verify（签名必须有效，否则 Gatekeeper 会报"已损坏"）"
codesign --verify --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature" || true
echo "OK -> $APP (build $BUILD_STAMP)"

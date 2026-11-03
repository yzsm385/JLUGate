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
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
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

echo "==> ad-hoc sign"
codesign --force --sign - "$APP"

echo "==> verify"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Signature" || true
plutil -lint "$APP/Contents/Info.plist" >/dev/null
echo "OK -> $APP"

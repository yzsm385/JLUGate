#!/usr/bin/env bash
# 旧版适配（macOS 14，无 Liquid Glass）的便携分发包：
#   dist/JLU Gate 1.0.0 (Compat).zip
#      JLU Gate.app          应用本体（ad-hoc 签名，可直接运行）
#      卸载 JLU Gate.command   一键卸载：删 App + 配置 + 日志 + 钥匙串条目
#      使用说明.txt
#
# 和新版（make-portable-package.sh）的区别：只打 ZIP（旧版不做 DMG），
# README 写明这是旧版适配包、系统要求 macOS 14。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.1.5"
APP="dist/JLU Gate (Compat).app"

echo "==> 构建 .app [compat: macOS 14, no Liquid Glass]"
./scripts/make-app-bundle-compat.sh >/dev/null

STAGE_ROOT="$(mktemp -d)/JLU Gate ${VERSION} (Compat)"
mkdir -p "$STAGE_ROOT"
STAGE="$STAGE_ROOT"
trap 'rm -rf "$(dirname "$STAGE_ROOT")"' EXIT

echo "==> 组装便携目录"
cp -R "$APP" "$STAGE/"

cat > "$STAGE/Install JLU Gate.command" <<'INSTALL'
#!/bin/bash
# 一键安装/覆盖：先结束正在运行的旧副本（包括卡死、在访达里删不掉的那种），
# 再替换到 /Applications，清掉隔离标记并启动。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/JLU Gate (Compat).app"
DEST="/Applications/JLU Gate (Compat).app"

if [ ! -d "$SRC" ]; then
  echo "找不到 $SRC"
  echo "请把本脚本和「JLU Gate (Compat).app」放在同一个文件夹里再双击。"
  exit 1
fi

echo "==> 结束正在运行的 JLU Gate（卡死也能杀掉）"
pkill -f "Contents/MacOS/JLUGate" 2>/dev/null || true
sleep 1
pkill -9 -f "Contents/MacOS/JLUGate" 2>/dev/null || true
for _ in $(seq 1 20); do
  pgrep -f "Contents/MacOS/JLUGate" >/dev/null 2>&1 || break
  sleep 0.5
done

echo "==> 替换 $DEST"
rm -rf "$DEST" 2>/dev/null || true
if [ -e "$DEST" ]; then
  echo "旧版本删不掉（进程可能卡在内核里）。请重启 Mac 后再双击本脚本。"
  exit 1
fi
if ! ditto "$SRC" "$DEST"; then
  echo "复制失败。请确认当前用户有 /Applications 的写权限。"
  exit 1
fi
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
codesign --verify --strict "$DEST" >/dev/null 2>&1 || echo "注意：签名校验没过（ad-hoc 包一般也还能跑）"

echo "==> 启动"
open "$DEST"
echo
echo "完成。右上角菜单栏会出现盾牌图标，并自动弹一次面板；"
echo "如果还是没有，把上面的输出和 ~/Library/Logs/JLUGate/agent.log 发给我。"
INSTALL
chmod +x "$STAGE/Install JLU Gate.command"

cat > "$STAGE/诊断 JLU Gate.command" <<'DIAG'
#!/bin/bash
# 双击它：把系统版本、二进制信息、直接运行 App 的报错（dyld/崩溃）一次性
# 收集到桌面 jlu-diag.txt。把那个文件发我，就能确定为什么打不开。
set -u
OUT="$HOME/Desktop/jlu-diag.txt"
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/JLU Gate (Compat).app"
[ -d "$APP" ] || APP="$HERE/JLU Gate (Compat).app"
BIN="$APP/Contents/MacOS/JLUGate"
{
  echo "==== sw_vers ===="
  sw_vers
  echo "==== uname ===="
  uname -a
  echo "==== arch ===="
  echo "本机: $(arch)"
  echo "==== App 是否存在 ===="
  ls -ld "$APP" 2>&1 || echo "（/Applications 里没有，用解压目录里的那份路径）"
  echo "==== Info.plist ===="
  plutil -p "$APP/Contents/Info.plist" 2>&1 | head -20
  if [ -x "$BIN" ]; then
    echo "==== vtool ===="
    vtool -show-build "$BIN" 2>&1 | head -20
    echo "==== otool -L（强链接的库）===="
    otool -L "$BIN" 2>&1 | head -30
    echo "==== 直接运行二进制（5 秒后采样）===="
    "$BIN" &
    PID=$!
    sleep 5
    if kill -0 "$PID" 2>/dev/null; then
      echo "进程仍在运行 pid=$PID（没有秒退；看右上角菜单栏有没有盾牌图标）"
      kill -9 "$PID" 2>/dev/null || true
    else
      echo "进程 5 秒内已退出（启动即崩/被拦）。上面可能有 dyld 的报错。"
    fi
  else
    echo "二进制不存在或不可执行: $BIN"
  fi
  echo "==== agent.log 最后 30 行 ===="
  tail -30 "$HOME/Library/Logs/JLUGate/agent.log" 2>&1
  echo "==== 最近的 JLUGate 崩溃报告 ===="
  ls -lt "$HOME/Library/Logs/DiagnosticReports/" 2>/dev/null | grep -i jlu | head -3
  cat "$HOME/Library/Logs/DiagnosticReports/JLUGate"*.ips 2>/dev/null | head -60
  echo "==== quarantine ===="
  xattr -l "$APP" 2>&1 | head
} > "$OUT" 2>&1
echo "已生成：$OUT"
echo "把这个文件发我即可。"
open -R "$OUT"
DIAG
chmod +x "$STAGE/诊断 JLU Gate.command"

cat > "$STAGE/Uninstall JLU Gate.command" <<'UNINSTALL'
#!/bin/bash
# 把 JLU Gate 从这台机器上彻底清掉：应用、配置、日志、钥匙串条目。
set -u
echo "即将卸载 JLU Gate，并删除以下内容："
echo "  · 应用本身（如果你把它拖进了 /Applications，也会一并删除）"
echo "  · ~/Library/Application Support/JLUGate  （配置 / 凭据 / 门户缓存）"
echo "  · ~/Library/Logs/JLUGate                 （日志）"
echo "  · 钥匙串里 service 为 dev.jlugate.app 的密码条目"
echo
read -r -p "确认继续？[y/N] " answer
[[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "已取消。"; exit 1; }

osascript -e 'tell application id "dev.jlugate.app" to quit' >/dev/null 2>&1 || true
pkill -f "Contents/MacOS/JLUGate" 2>/dev/null || true
sleep 1
pkill -9 -f "Contents/MacOS/JLUGate" 2>/dev/null || true
sleep 1

APP_PATH_OF_THIS_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
rm -rf "/Applications/JLU Gate.app" 2>/dev/null || true
rm -rf "/Applications/JLU Gate (Compat).app" 2>/dev/null || true

rm -rf "$HOME/Library/Application Support/JLUGate"
rm -rf "$HOME/Library/Logs/JLUGate"

# 钥匙串条目（可能有多条，循环删）
while security delete-internet-password -s dev.jlugate.app >/dev/null 2>&1; do :; done || true

rm -rf "$APP_PATH_OF_THIS_SCRIPT"

echo
echo "已卸载。"
echo "如果之前在「系统设置 → 通用 → 登录项」里登记过开机自启，那一项会在下次系统检查时自动消失；"
echo "也可以现在手动移除。"
UNINSTALL
chmod +x "$STAGE/Uninstall JLU Gate.command"

cat > "$STAGE/README.txt" <<'README'
JLU Gate 1.0.0（旧版适配，macOS 14+）

这是给老版本 macOS 的适配包：不用 Liquid Glass，普通材质界面。
如果你的系统是 macOS 26 及以上，建议改用新版包（界面有 Liquid Glass）。
两个包同名同 bundle id，不要同时装。

一、系统要求
  macOS 14 (Sonoma) 及以上。更低版本不保证能跑。

二、安装（推荐）
  双击同目录下的「Install JLU Gate.command」：它会先结束正在运行的旧版本
  （包括卡死、在访达里删不掉的那种），再替换到 /Applications 并启动。

  也可以手动拖：把「JLU Gate (Compat).app」拖进 /Applications。
  首次打开若提示"无法验证开发者"，右键 → 打开；或到
  「系统设置 → 隐私与安全性」里点「仍要打开」。

三、第一次使用
  1. 菜单栏出现盾牌图标 → 点开 → 「设置」或「重新设置…」；
  2. 账号 = 学校邮箱 @mails.jlu.edu.cn 前面那一段（学生如 zhangcyy2122，教师如 zhangshanwu），
     密码 = 邮箱密码；
  3. 接入方式：有线 / JLU.PC / JLU.WIFI / 自动；
  4. 若有线或 JLU.PC：点「用系统当前读数填入」——只有系统这块网卡是手动配置时才会填，
     这样不会把 DHCP 分到的错地址抄进去。

四、它只在这几处留东西（卸载脚本会全部删掉）
  ~/Library/Application Support/JLUGate/   配置、凭据、门户页面缓存
  ~/Library/Logs/JLUGate/                  日志（2MB 滚动）
  钥匙串 service = dev.jlugate.app         正式签名版的密码（本便携版为 ad-hoc 签名，密码存本地文件）

五、卸载
  双击同目录下的「卸载 JLU Gate.command」。它会删 App、配置、日志与钥匙串条目。

六、常见问题
  · 连 JLU.PC 弹的 login.jlu.edu.cn 欢迎页是系统弹的捕获门户页，不是本程序；
    App 内有「校园网门户」可以随时查看那一页，不会自动弹窗。
  · 提示 MAC 与登记不符：学校按 MAC 认设备，去 https://ip.jlu.edu.cn/pay 改登记。
  · 端口 61440 被占用：先退出官方 DrClientNS；仍有占用说明它的后台组件在跑。
README

# 给一个 /Applications 软链，用户可以直接把 App 拖进去
ln -sfn /Applications "$STAGE_ROOT/Applications" 2>/dev/null || true

echo "==> 打包 ZIP"
ZIP="dist/JLU Gate ${VERSION} (Compat).zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$STAGE_ROOT" "$ZIP"
echo "OK -> $ZIP"
ls -lh "$ZIP"

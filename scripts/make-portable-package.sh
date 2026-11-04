#!/usr/bin/env bash
# 打一个"便携、删干净"的分发包：
#   dist/JLU Gate 0.1.0.dmg
#      JLU Gate.app          应用本体（ad-hoc 签名，可直接运行）
#      卸载 JLU Gate.command   一键卸载：删 App + 配置 + 日志 + 钥匙串条目
#      使用说明.txt
# 应用只在这三个位置写东西，卸载脚本会把它们全部清掉，不留残渣：
#   ~/Library/Application Support/JLUGate/     配置、凭据（开发版）、门户缓存
#   ~/Library/Logs/JLUGate/                    日志（2MB 滚动一份）
#   钥匙串 service = dev.jlugate.app           正式签名版的密码（开发版不写钥匙串）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.0.0"
APP="dist/JLU Gate.app"
DMG="dist/JLU Gate ${VERSION}.dmg"

echo "==> 构建 .app"
./scripts/make-app-bundle.sh >/dev/null

STAGE_ROOT="$(mktemp -d)/JLU Gate ${VERSION}"
mkdir -p "$STAGE_ROOT"
STAGE="$STAGE_ROOT"
trap 'rm -rf "$(dirname "$STAGE_ROOT")"' EXIT

echo "==> 组装便携目录"
cp -R "$APP" "$STAGE/"

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
pkill -f "JLU Gate.app/Contents/MacOS/JLUGate" 2>/dev/null || true
sleep 1

APP_PATH_OF_THIS_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
rm -rf "/Applications/JLU Gate.app" 2>/dev/null || true

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
JLU Gate 0.1.0（便携版）

一、安装
  把「JLU Gate.app」拖进 /Applications 即可。首次打开若提示"无法验证开发者"，
  右键 → 打开；或到「系统设置 → 隐私与安全性」里点「仍要打开」。

二、第一次使用
  1. 菜单栏出现盾牌图标 → 点开 → 「设置」或「重新设置…」；
  2. 账号 = 学校邮箱 @mails.jlu.edu.cn 前面那一段（学生如 zhangcyy2122，教师如 zhangshanwu），
     密码 = 邮箱密码；
  3. 接入方式：有线 / JLU.PC / JLU.WIFI / 自动；
  4. 若有线或 JLU.PC：点「用系统当前读数填入」——**只有系统这块网卡是手动配置时**才会填，
     这样不会把 DHCP 分到的错地址抄进去。

三、它只在这几处留东西（卸载脚本会全部删掉）
  ~/Library/Application Support/JLUGate/   配置、凭据、门户页面缓存
  ~/Library/Logs/JLUGate/                  日志（2MB 滚动）
  钥匙串 service = dev.jlugate.app         正式签名版的密码（本便携版为 ad-hoc 签名，密码存本地文件）

四、卸载
  双击同目录下的「卸载 JLU Gate.command」。它会删 App、配置、日志与钥匙串条目。

五、常见问题
  · 连 JLU.PC 弹的 login.jlu.edu.cn 欢迎页是**系统**弹的捕获门户页，不是本程序；
    App 内有「校园网门户」可以随时查看那一页，不会自动弹窗。
  · 提示 MAC 与登记不符：学校按 MAC 认设备，去 https://ip.jlu.edu.cn/pay 改登记。
  · 端口 61440 被占用：先退出官方 DrClientNS；仍有占用说明它的后台组件在跑。
README

# DMG 里给一个 /Applications 软链，用户可以直接把 App 拖进去
ln -sfn /Applications "$STAGE_ROOT/Applications" 2>/dev/null || true

echo "==> 打包（ZIP 用于一键更新；DMG 用于首次安装）"
rm -f "$DMG"
ZIP="dist/JLU Gate ${VERSION}.zip"
rm -f "$ZIP"

# ZIP 始终产出：应用内"下载并安装"用它
ditto -c -k --sequesterRsrc --keepParent "$STAGE_ROOT" "$ZIP"
echo "OK -> $ZIP"

made=0
if [ "${JLUGATE_SKIP_DMG:-0}" != "1" ]; then
    if hdiutil create -volname "JLU Gate ${VERSION}" -srcfolder "$STAGE_ROOT" -ov -format UDZO "$DMG" >/dev/null 2>&1 \
       && hdiutil verify "$DMG" >/dev/null 2>&1; then
        echo "OK -> $DMG"
        ls -lh "$DMG"
        made=1
    else
        echo "  ⚠️ 当前环境做不出 DMG，改用 ZIP。"
        rm -f "$DMG"
    fi
fi

if [ "$made" = "0" ]; then
    echo "  ⚠️ 没有生成 DMG（当前环境不支持）；ZIP 已生成，可用于一键更新。"
fi

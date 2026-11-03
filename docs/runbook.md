# 真机操作手册（环境 B）

> 环境 A（施工机）只做编译、单测、`127.0.0.1` 模拟网关/模拟门户。
> 这份手册假设你坐在**那台有校园网的有线 Mac** 前，且它正被官方客户端占着。
> 配套：[progress.md](progress.md)（实现状态）、[CHECKLIST.md](CHECKLIST.md)（协议）。

---

## 0. 打包（便携版）

```bash
make package     # → dist/JLU Gate 0.1.0.zip（或 .dmg）
```

包内三样东西：`JLU Gate.app`、`Uninstall JLU Gate.command`、`README.txt`。
卸载脚本会把 App、`~/Library/Application Support/JLUGate`、`~/Library/Logs/JLUGate`
和钥匙串里 `dev.jlugate.app` 的条目**一起删掉**，不留残留。

## 0.1 准备

```bash
# 在环境 A 上打包 universal 二进制，拷到环境 B
make release-probe
#   → .build/apple/Products/Release/jlugate-probe
lipo -info .build/apple/Products/Release/jlugate-probe
```

环境 B 只需要这一个二进制 + 一个终端窗口，**不需要装 Xcode**。

---

## 1. 先做只读诊断（3 秒，不影响上网）

```bash
./jlugate-probe --interfaces
./jlugate-probe --route-check
```

要确认四件事：

| 看什么 | 期望 | 不对的话 |
|---|---|---|
| 有线口的 MAC | 与学校平台登记的一致 | 换卡/换口后要重新登记 |
| `ConfigMethod` | `Manual` | 是 DHCP 就必须先改手动，否则认证必失败 |
| 路由出口 | 物理口（`en7` 之类） | 是 `utunN` → 代理接管了校园网段 |
| 默认网关 | 你档案里那个 | 不一致说明网络参数抄错了 |

再补三条原始命令（结果贴回时更有说服力）：

```bash
sudo lsof -nP -iUDP:61440     # 谁占着认证端口
arp -an | grep 10.100.61.3    # 网关 ARP 在不在
scutil --dns | grep nameserver | head -5
```

---

## 2. 判链路（会发 1 个 challenge，但**不认证**）

```bash
./jlugate-probe --detect
```

输出会是三者之一：

- `Dr.Com challenge：有回执 ✅` → 该走有线/JLU.PC；
- `204 探针：被拦截（HTTP 302 → …）` → 该走 `JLU.WIFI` 网页认证；
- `结论：当前网络不是校园网` → 别继续，先查网线/代理。

> 这个命令只发**一个** 20 字节 challenge，3 秒超时，不重试，也不会顶掉任何在线设备。

---

## 3. 真正登录

```bash
./jlugate-probe --login \
  --account <学号> --password <密码> \
  --mac <登记MAC> --seconds 60
```

判读：

| 终端输出 | 含义 | 下一步 |
|---|---|---|
| `状态 → online` 且 `在线 Ns` 递增 | 成功 | 让它跑 10 分钟，确认不掉线 |
| `失败：ldap auth error` | 服务器原话：密码错 | 核对密码；**不要**当成"客户端坏了" |
| `失败：账号在别处登录` | 另一台设备在线 | 关掉那台，或等 30 秒后重试 |
| `失败：…MAC…` | MAC 被别的设备占用 | 检查是否多人共用廉价网卡 |
| `失败：接口 xxx 没有 IPv4` | 网卡在但没地址 | 系统设置里配静态地址 |
| `失败：接口 xxx 仍在使用 DHCP` | 接入方式是自动 | 改成手动并填学校给的值 |
| `失败：检测到代理接管了校园网段` | TUN 抢了 10/8 | 代理规则里把 10.0.0.0/8 设直连 |
| `失败：端口 61440 被官方客户端占用` | 官方 daemon 在跑 | 见 §5 |

---

## 4. 同时抓一次包（最关键的回传物）

```bash
# 终端 A
sudo tcpdump -i en7 -n -s 0 -X "udp port 61440" -w ~/Desktop/jlugate.pcap

# 终端 B（同一时间）
./jlugate-probe --login --account <学号> --password <密码> --seconds 60
```

回传：`jlugate.pcap` + 终端 B 的完整输出。

> 包里含账号与摘要（等价于密码），按敏感数据处理：走私人渠道，别贴公开 issue。

---

## 5. 端口被官方客户端占着

```bash
sudo lsof -nP -iUDP:61440
# 若是 drcomauth / DrClientNS：
#   ① 菜单栏退出 DrClientNS
#   ② 仍然占用 → GUI 退出不会停它的后台组件：
sudo launchctl bootout system/com.doctorcom.DrClientHelper
```

注意：停掉后台组件后，官方客户端的自动登录也不可用了；要恢复就重装官方客户端。

---

## 6. 网页认证（JLU.WIFI）

### 6.1 命令行先验证判定

```bash
./jlugate-probe --detect
# 期望：204 探针：被拦截（HTTP 302/200 → http://…）→ 应走 JLU.WIFI 网页认证
```

若显示"已在线（无需认证）"，说明此时**没有被门户拦截**（可能已登录过，或者根本没连上 JLU.WIFI）。

### 6.2 App 里走一遍完整流程

```bash
make app-bundle
open "dist/JLU Gate.app"
```

菜单栏图标 →「登录」→ 自动判定链路 → 弹出 `WKWebView` 登录窗：

| 观察点 | 期望 |
|---|---|
| 登录窗是否出现 | 只会在"需要用户输入"时出现，不抢焦点以外的行为 |
| 窗口里能不能正常登录 | 就是浏览器，用户自己输账号密码（**不做任何预填**，D-001） |
| 登录后 | 窗口自动关闭、菜单栏图标转实心、显示"在线"和在线时长 |
| 断网 30s 再恢复 | 自动回到在线，不需要点任何按钮 |

### 6.2.1 账号怎么填（JLU 邮箱前缀）

账号就是学校邮箱 `@mails.jlu.edu.cn` **前面那一段**，密码是邮箱密码：

| 身份 | 格式 | 例子 |
|---|---|---|
| 学生 | 姓全拼 + 名各字首字母 + 4 位数字（专业代码 2 位 + 入学年份 2 位） | `zhangcyy2122` = 计算机专业 22 年入学 |
| 教师 | 姓名全拼 | `zhangshanwu` |

同名教师的账号学校会加后缀，**以邮箱实际地址为准**。粘整个邮箱进向导也行，程序会自动去掉域名。

### 6.2.2 JLU.WIFI 只允许 3 台设备同时在线

新设备/新 IP 加入会把**最早加入**的那台踢掉。所以"突然掉线"多半不是密码错，而是被挤了：

- 客户端发现掉线后**立刻**（不等 5 分钟冷却）准备重进，并在菜单里说明原因；
- 点「重新抢回在线」会把你排到队尾，并**踢掉当前队列里第二台设备**（如果是你自己的另一台电脑/手机，它就会掉线）；
- 所以这条提示一定先看清楚再点。

### 6.3 Cookie 复用

登录成功后**不要退出 App**，直接关掉 Wi-Fi 再打开：`PortalEngine` 会先静默试一次
（复用 Cookie），通了就不弹窗；只有静默失败才再弹一次（5 分钟内不重复打扰）。

### 6.3.1 网络详情 / Ping / 测速（不用终端也能看）

菜单 →「网络详情…」打开的窗口里有：

| 区块 | 内容 |
|---|---|
| VPN / TUN | 列出 utun 接口与地址；默认出口、认证流量出口是不是被虚拟网卡接管 |
| 网口 | 每个口的名字/ifindex/IPv4/掩码/MAC/链路本地，标注「无线 / USB / 默认出口 / 认证流量」；并逐条说明**这是谁的、干什么用的**（Wi-Fi / USB 网卡 / 雷雳网卡 / AirDrop 直连 / 回环 / Apple 内部 / 代理隧道），能用来认证的口排在前面 |
| 路由与 DNS | 默认路由、系统 DNS；出现 `198.18.x.x` 会警告"DNS 被代理劫持" |
| Ping | 网关与公网各测 4 次 TCP 握手延迟，并对比"经默认出口（含 VPN）"的额外延迟 |
| 测速 | 分别用「网口直连」和「当前默认出口（含 VPN）」下载 10s，给出 Mbps 与 MB/s |
| 这些字段是什么意思 | MAC / IPv4 / 掩码 / 网关 / DNS / 链路本地 / 路由 / TUN / 测速 / Ping 的白话解释 |

命令行等价物（排查时更好贴给别人）：

```bash
./jlugate-probe --net-detail   # 网口/路由/DNS/VPN + 字段解释
./jlugate-probe --ping         # 直连 vs 默认出口的延迟对比
./jlugate-probe --speed        # 直连 vs VPN 的下载速度对比
```

### 6.3.2 判断小火箭当前是什么模式（认证能不能成功的关键）

「网络详情」最上面用一行结论告诉你现在属于哪种模式（**完全靠路由实测**，不读小火箭配置、不截图）：

| 实测 | 结论 | 对小火箭的意思 |
|---|---|---|
| 默认路由和 10.100.61.3 都走 utun | **全局代理** | 校园网段也被代理吞了 → 认证必失败 |
| 默认路由走 utun，10.100.61.3 走 en​* | **规则 / 配置模式（校园网已直连）** | 小火箭「配置」且 10/8 命中 DIRECT → 认证能成功 |
| 都走物理网卡 | **直连** | 小火箭关着或选了「直连」 |
| 有 utun 但默认路由没被接管 | **TUN 已开启但未生效** | 规则没命中 / 代理没真正起来 |

卡片里还能选「你在小火箭里选的是：配置 / 代理 / 直连 / 场景」，程序会告诉你**你选的**和**实测的**是否一致，
不一致就说明规则没生效——这比让小火箭"看起来开着"更可靠。

命令行：`./jlugate-probe --net-detail` 里 `== 代理模式 ==` 一节同样给出结论与建议。

### 6.4 没有校园网时怎么验证 App 真的能跑

`make app-bundle` 产出的 `dist/JLU Gate.app` 可以直接运行。想在没有校园网的机器上
把「App → 协调器 → 引擎 → 保活 → 状态/遥测」整条链路跑通，用随包附带的 dev 自检：

```bash
python3 Tools/mock-gateway/mock_gateway.py --port 61441 --duration 30 --assert \
    --account 20230001 --password test-pass-2024 &
./scripts/make-app-bundle.sh --dev      # 往 App 里塞 dev-config.json（server=127.0.0.1:61441）
open -n "dist/JLU Gate.app"
tail -f ~/Library/Logs/JLUGate/agent.log # 应看到 …→online + traffic
```

`--dev` 构建**不碰钥匙串**、不走物理网卡（用 lo0 + BSD 通道），只用于自检；
正式包不会读取 `dev-config.json`。

网页认证同样可以无人值守跑通（脚本化浏览器 + 本地模拟门户）：

```bash
make portal-e2e           # 期望：OK portal -> online
make portal-e2e-window    # 会弹真实 WKWebView 登录窗，需要人工点一次
```

实测日志（`~/Library/Logs/JLUGate/agent.log`）：

```
event state(discovering) → authenticating → online
portal window loaded: http://127.0.0.1:18080/portal   # 真实 WKWebView 分支
```

### 6.4.1 已经在用、但还没配过账号（被动观测）

如果你本来就在浏览器里登录过、网络是通的，App **不会**一上来逼你输账号密码：

- 启动先做一次 204 探针；
- 通 → 菜单直接显示**已连接**，副标题"当前已在线上（未配置账号）"，
  操作按钮变成「填写账号密码（断线后自动重连）」，可填可不填（填了断线才能自动恢复）；
- 不通 / 被门户拦 → 才弹一次向导请你填账号（只弹一次，之后按记住的来）。

实现：`PassiveMonitor`（Core，4 条单测）+ `AppModel.startPassiveWatch()`，每 30s 复查一次。

### 6.4.2 真机结论：JLU 按 MAC 认设备，有线和 JLU.PC 不能跨机器混用（2026-11-03 实测）

实测现象：

- 连上 `JLU.PC` 后，系统弹出 `login.jlu.edu.cn` 的"欢迎使用吉林大学校园网"页面（**系统门户页**，不是本程序弹的，关掉就行）；
- 客户端用 Wi-Fi 网卡去认证，被服务器拒绝：**MAC 与登记值不符**；
- 学校登记的是那台 USB 网卡的 MAC，而本机 Wi-Fi 网卡 MAC 是固化的、改不了。

由此得到三条硬规则（已写进 `JLUAccessPolicy`，UI 会照着解释）：

| 规则 | 说明 |
|---|---|
| 账号绑定的是 MAC | 要换设备/换网卡，必须先去 <https://ip.jlu.edu.cn/pay> 改登记 |
| 有线 = 网线/USB 网卡 MAC；JLU.PC = Wi-Fi 网卡 MAC | 两块不同的卡，**不能互相顶替** |
| MAC 固化不可改 | 不是软件能绕过的；"改 MAC" 在本机行不通 |

所以：**同一个账号想在 JLU.PC 上用，就得把登记 MAC 换成那台机器的 Wi-Fi MAC；换完原来有线那台就失效。**
程序会提前用"登记 MAC vs 当前网卡 MAC"做校验，不一致时直接报 `macMismatch` 并给出自助平台入口，不会发注定失败的认证包。

### 6.5 首次设置之后就不再打扰

向导固定三步：**账号密码（三网共用，只填一次）→ 接入方式 →（仅当选了有线/JLU.PC 且没填过时）网络参数**。

- 账号密码存在账号名下，有线 / JLU.PC / JLU.WIFI 共用同一份；
- 账号就是邮箱前缀（学生 `zhangcyy2122`、教师 `zhangshanwu`，密码是邮箱密码）；
- 只要"成功连过"一次，之后启动会**静默自动连接**，不再弹向导；
- 选了有线或 JLU.PC 但地址还没填 → 向导会给指引；填过并记住后不再追问；
- 想改：菜单「重新设置…」；想彻底重来：设置页「重置本机配置…」；
- 不想要自动连：设置 → 关掉「启动时自动连接」。

### 6.5.1 设置窗口打不开（已修）

早期版本用 SwiftUI 的 `SettingsLink` 打开设置；`LSUIElement`（菜单栏常驻、无 Dock 图标）的应用
在部分系统版本上点它**没有任何反应**。现在改成自己创建 `NSWindow` 承载 `SettingsView`
（`AppModel.presentSettings()`），并且会主动把窗口置前。

如果仍然看不到窗口：菜单 →「设置」→ 窗口标题应为 **JLU Gate 设置**；窗口是普通可拖动窗口，
可能被菜单面板挡住——按 `⌘W` 关掉菜单面板再找一下。

### 6.6 为什么重新构建后会弹"允许访问钥匙串"

ad-hoc 签名每次构建的签名都不一样，而 Keychain 条目的 ACL 是绑定签名的，
所以新构建读旧条目时 macOS 会重新征求许可。**这不是程序在扫别的东西**：

- 凭据只在向导/设置页保存时写入，**重连不会重写**；
- dev 自检模式完全跳过钥匙串；
- 正式签名（Developer ID）稳定之后就不会再问。

点「允许」（或「始终允许」）即可；不想留条目可以在「钥匙串访问」里删掉
`dev.jlugate.app`。

### 6.7 失败时回传什么

```bash
# 菜单 →「复制诊断」/「导出」→ 生成的文件
# 另外补一条：
./jlugate-probe --detect
```

登录窗若报错，把窗口里的**原文**一起回传（服务器/门户自己给的文案，不要翻译）。

---

## 7. 休眠 / 唤醒验收

```bash
pmset sleepnow      # 或直接合盖
# 唤醒后（不碰键盘鼠标）等待 ≤5s
./jlugate-probe --login --account <学号> --password <密码> --seconds 30
```

期望：自动重新识别网卡 → 重新 challenge → 回到 `online`。这一条是产品最核心的痛点，务必验。

---

## 8. 回传清单

| 文件 | 内容 |
|---|---|
| `jlugate.pcap` | UDP 61440 全量载荷 |
| `login.log` | `--login` 的终端输出（含时间戳） |
| `diag.txt` | App 菜单里"导出"生成的诊断文本（含接口/路由/MAC/配置脱敏） |
| `route.txt` | `netstat -rn -f inet \| grep -E '^(10|default)'` |

拿到这三样，编码器与状态机的全部"未解项"基本都能定案。

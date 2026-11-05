# JLU Gate

吉林大学校园网的 macOS 菜单栏小工具。

在吉大用 Mac 上网，有点像进了一栋有三个门、却只发一张卡的大楼：宿舍网线走 Dr.Com，JLU.PC 也走 Dr.Com，JLU.WIFI 又得开浏览器点网页认证——三个入口，账号密码却是同一套。每次换网络都得重新刷一遍卡；真断网了，对着一句冷冰冰的"未连接"干瞪眼，分不清是学校的事、DNS 的事，还是自己开的代理在捣乱。

JLU Gate 想把这三个门并成一个闸口。账号密码填一次，三种接入共用；该走哪条路它自己认，掉了线替你悄悄重连。顺手把教务、OA、邮箱、WebVPN 这些散落各处的入口也拢到一处，点一下就开；再配一套网络体检，断网时一层一层替你查到底卡在哪、出口那扇门后面干不干净。

> 只在校园网环境里有意义；主包跑在 macOS 26 及以上（Liquid Glass 界面），老系统（macOS 14/15）用 Compat 包。

## 下载与安装

1. 去 [Releases](https://github.com/yzsm385/JLUGate/releases) 下最新版的 **ZIP**：
   - **macOS 26 及以上** → 下主包 `JLU Gate x.x.x.zip`（Liquid Glass 界面）；
   - **macOS 14 / 15** → 下 `JLU Gate x.x.x (Compat).zip`（普通材质，功能一样，不会崩）。
   - 两个包同名同 bundle id，**别同时装**——启动守卫会把同 id 的旧进程顶掉。
2. 解压后，把里面的 **JLU Gate.app** 拖进「应用程序」。
3. 第一次打开，系统会拦一下，提示"无法验证开发者"或"没认证"——因为这个程序没有 Apple 开发者签名。别慌，按下面走：
   - 打开「系统设置 → 隐私与安全性」，一直拉到最底下；
   - 会看到一行"已阻止使用 JLU Gate"，旁边有个「仍要打开」按钮，点它；
   - 输你的开机密码确认；
   - 再回去打开 App，这次就能进了。

> 这个"没认证"不是程序有问题，纯粹是我没买 Apple 开发者账号（¥688/年）；放行一次之后，往后打开都不会再问。

装好之后想更新就省事了：在 App 里「设置 → 更新 → 检查更新」，有新版它会自己下载、退出、替换、再打开，不用手动覆盖 ZIP。

## 它解决了什么

下面这些是写这个程序时真实撞上、想顺手抹平的坎：

- **三个门却只发一张卡。** 卡填一次，三处通用；存进钥匙串，往后不用再掏。
- **JLU.WIFI 只认 3 台设备，被新来的挤下去时悄无声息。** 掉线时它会告诉你"多半是被挤了"，并说清重新登入会顶掉队尾那一台（没准正是你自己的另一台机器）。
- **学校认网卡，系统却爱给网卡换脸。** 它读的是出厂那张"原貌"去认证，三个值——当前、出厂、登记——并排摆出来，一眼对得上。
- **代理开了条岔路，认证包走着走着被拐走。** 实测"直连 vs 经代理"两条路差多远，拿数据替你拿主意该不该给校园网段改规则。
- **断了网，分不清该找谁。** 一站一站掀开看（DNS → TCP → TLS → HTTP），给出结论和下一步，而不是丢一句"网络错误"了事。
- **代理 IP 被重点盯上，却不知为何。** 多个来源交叉比对是住宅还是机房，DNS 出口和 IP 出口是不是同一个国家，都讲明白。

## 能做什么

按板块分一下，每块管一类事、解决一类别处没解的麻烦：

| 板块 | 这块在干什么 | 具体能力 |
|---|---|---|
| **三网接入** | 大楼那三个门，一把钥匙开三把锁；认得该走哪扇，掉了链子自己接上 | 自动认该走哪条路（发一个 challenge 判定，不是校园网就一个包都不发）；10 秒保活、掉线指数退避重连、休眠唤醒自动恢复、插拔网线自适应；按 MAC 自动认网卡或手动指定 |
| **参数与 MAC** | 学校凭网卡认人，系统偏又爱给网卡换"面具"——这块专门撕下面具、对上身份证 | 读出厂 MAC 去认证，界面上并排显示当前 / 出厂 / 登记三个值；静态参数能用系统读数一键填（**仅当网卡是手动配置时**，DHCP 一律不抄） |
| **吉大常用入口** | 校园里那些东一个西一个的牌子，收进同一个橱窗，伸手就能够到 | 14 个站点分五类摆好，每个标「仅校内 / 需 VPN / 公网」；能搜（标题 / 域名 / 用途）；点开用系统浏览器，支持登录的顺手复制账号；「复制密码」60 秒后自动清空剪贴板；「我的学院」填学号认学院，44 个学院可搜、一键开官网；「校园网门户 / 今日广告」给按钮直接开、不自动弹 |
| **网络体检** | 断网时不让你对着黑箱猜，一层层掀开看：是路断了、门关了，还是屋里没人在 | 能不能上网：google / brave / duckduckgo / bing / 百度 + 教务 / OA / 邮箱逐站归因；出口 IP 三源交叉（Cloudflare / ipify / ifconfig.me）带国旗；自实现 STUN 拿浏览器同款 WebRTC 公网地址；DNS 泄漏反查解析出口；人机验证可达性（reCAPTCHA / 国内镜像 / Turnstile / CF 挑战页）；IP 纯净度多源交叉判住宅 or 机房；带宽三档（直连 / 默认出口 / 本地代理，端口自动探测） |
| **代理与路由** | 你开的代理像条岔路，认证包可能走着走着就被拐走了；这块帮你量清楚两条路差多远 | 实测"认证通道延迟：直连 vs 经代理"；路由出口是不是被 TUN 接管、ConfigMethod 是不是 Manual，都直接给结论 |
| **界面与状态** | 不跟你拽术语，像旁边站了个懂行的人，指着那一行告诉你"现在这样、下一步该干嘛" | 菜单栏常驻不占 Dock；文案说人话少用术语；启动看门狗——崩过一次就进安全模式（不自动连、不读密码），保证能进来改配置 |
| **更新与卸载** | 来了就走、走了不留痕 | 设置里检查更新，有新版自己下载 → 退出 → 替换 → 重开，不用手动覆盖；卸载脚本删掉 App、配置、日志和钥匙串条目 |
| **安全上的克制** | 该它管的它管，不该它碰的一根手指都不伸 | JLU.WIFI 走系统浏览器，程序不碰明文密码、不做 DOM 操作或自动填充；预检只提示不拦截，放不放行由学校服务器定 |

## 参与贡献

这个工具是一个人照着自己在吉大撞过的坑写的，**覆盖面肯定不全**。下面这几块是最容易补、也最希望同学们帮忙的地方——不用会写 Swift，会认字、会上网就行。

### 我的学院没收进去 / 学号认不出学院

学院目录在 [Sources/JLUGateCore/CollegeDirectory.swift](Sources/JLUGateCore/CollegeDirectory.swift)，目前收了官网「院系设置」页列出的 **44 个学院**。如果你发现：

- 你的学院不在这份名单里（比如新成立的、或者独立学院/研究院/中心也想收进来）；
- 填了学号却认不出学院——吉大**没有公开的"学号前缀 → 学院"对照表**，现在的做法是"你选一次、本机记住同前缀"，所以**只有你一个人用的时候它学得会，换个人就又得重选**。

能怎么帮：
- 在 [Issues](https://github.com/yzsm385/JLUGate/issues) 开一条，写明「学院名 + 官网域名 +（如果知道的话）学号前缀」，我加进目录；
- 或者直接 PR 改 `CollegeDirectory.all`，照着现有格式加一行 `College(name:host:)` 就行。

### 想把某个常用网站收进合集

站点合集在 [Sources/JLUGateCore/JLUSiteDirectory.swift](Sources/JLUGateCore/JLUSiteDirectory.swift)，目前 **14 个**（教务 / OA / 邮箱 / WebVPN / 校园网自助 / 官网新闻）。如果你每次都得去收藏夹翻的入口不在里面——比如你学院的教务系统、某个办事流程页、某个实验室/课题组的站点、图书馆某个常用数据库入口：

- 开 Issue 说「网站名 + 域名 + 是仅校内 / 需 VPN / 公网 + 一句话用途」；
- 直接 PR 也行，照 `JLUSite` 的字段加一条，`category` 选已有的五类之一，`access` 选 `公网 / 仅校内 / 需 VPN` 三个之一。

### 其他想补的

- **体检站点**：[Sources/JLUGateNet/ReachabilityService.swift](Sources/JLUGateNet/ReachabilityService.swift) 里"能不能上网"探的站点是 google / brave / duckduckgo / bing / 百度 + 教务 / OA / 邮箱，想加别的探针也欢迎；
- **真机验证**：作者只有一台插校园网线的 Mac，别的机型 / 别的校区（朝阳 / 南湖 / 和平 / 南岭 / 新民 / 南部）的网络环境没试过，反馈真实环境的掉线日志和 `tcpdump` 抓包（**记得脱敏**）很有价值；
- **文案**：界面上哪句"人话"没说人话、哪段注解看不懂，直接开 Issue 说该怎么说。

> 不收任何真实凭据。Issue / PR 里**别贴明文密码、别贴原始抓包**；脱敏规则见 [SECURITY.md](SECURITY.md) 和 [docs/CHECKLIST.md](docs/CHECKLIST.md)。

## 给开发者的几条底线

这几条是开发时给自己立的规矩，也是这个项目能放心做下去的前提：

1. **开发机不做任何真实联网验证**。不认证、不抓校园网的包；唯一允许的"联网"是跟 `127.0.0.1` 上的模拟网关说话。
2. **报文只能照 [docs/CHECKLIST.md](docs/CHECKLIST.md) 里的偏移填**，不许自创字段。偏移和抓包对不上时，以抓包为准，差异记在 [docs/progress.md](docs/progress.md) §4。
3. **先怀疑环境，再怀疑凭据**。接口、MAC、DHCP、路由任何一项不对，都不发认证包。

## 快速开始

```bash
make test            # 193 条单元测试（编码器黄金向量 + 状态机 + 通道 + 探针/选路/网页认证/路由守卫）
make self-test       # 对 127.0.0.1 的模拟网关跑 challenge → 登录 → 保活 全流程
make portal-self-test# 对 127.0.0.1 的模拟门户跑 302 → 登录页 → POST → 204
make ci              # 上面三件 + 隐私扫描（和 GitHub Actions 跑的一致）
make dump-login      # 离线打印 342 字节登录包，人工核对偏移
```

下面这些都是只读诊断，不改任何系统状态，随时能跑：

```bash
swift run jlugate-probe --interfaces     # 网卡 / MAC / IPv4
swift run jlugate-probe --route-check    # 10.100.61.3 的出口是不是被 TUN 接管、ConfigMethod 是不是 Manual
swift run jlugate-probe --detect         # 只判定走哪条链路（发 1 个 challenge，不认证；真机用）
swift run jlugate-probe --net-detail     # 网口 / 路由 / DNS / VPN 快照，每个字段都带一句白话解释
swift run jlugate-probe --ping           # 网关、公网延迟（直连 vs 默认出口含 VPN）
swift run jlugate-probe --speed          # 下载测速（直连 vs VPN）
```

## 真机验证（只能在那台插着校园网线的 Mac 上做）

```bash
make release-probe        # universal 二进制
./.build/apple/Products/Release/jlugate-probe --login \
    --account <学号> --password <密码> --mac <登记MAC> --seconds 60
```

判定标准很简单：**能登录、能撑 10 分钟不掉线**。把终端输出和 `tcpdump -i en7 -n "udp port 61440"` 的抓包贴回来就行。完整流程见 [docs/runbook.md](docs/runbook.md)。

## 目录

| 路径 | 是什么 |
|---|---|
| `Sources/JLUGateCore` | 编解码 / 摘要 / 状态 / 退避 / 错误（纯协议，没有 I/O） |
| `Sources/JLUGateNet` | BSD 与 NW 两套 UDP 通道、网卡与路由解析、`DrcomEngine` actor |
| `Sources/jlugate-probe` | 诊断 + 离线自测的命令行工具 |
| `App/` | SwiftUI 菜单栏应用（macOS 26，Liquid Glass；XcodeGen 工程描述在 `App/project.yml`） |
| `App-Compat/` | 旧版适配（macOS 14，普通材质、无 Liquid Glass；和 `App/` 同源，只换 `AppearanceCompat`） |
| `Tools/mock-gateway` | 按帧表应答的 Dr.Com 模拟网关（支持丢包 / 延迟 / 拒绝） |
| `Tools/mock-portal` | 模拟校园网页认证（302 → 登录页 → POST → 204） |
| `Fixtures/` | 抓包样本（含凭据摘要，**不要公开**） |
| `docs/` | CHECKLIST / PLAN / protocol-findings / progress / runbook |

## 构建 / 运行 App

没有开发者账号也能在本机跑起来（ad-hoc 签名，不能分发、不能公证）：

```bash
make app-bundle     # → dist/JLU Gate.app（菜单栏常驻，macOS 26，Liquid Glass）
open "dist/JLU Gate.app"

make app-compat      # → dist/JLU Gate (Compat).app（macOS 14，普通材质，老系统用）
open "dist/JLU Gate (Compat).app"
```

有账号、要签名和公证时，走 XcodeGen（新版在 `App/`，旧版在 `App-Compat/`）：

```bash
brew install xcodegen
cd App && xcodegen generate && open JLUGate.xcodeproj        # 新版
cd App-Compat && xcodegen generate && open JLUGate.xcodeproj # 旧版适配
```

## 隐私

- 仓库里的 `Fixtures/` 已经**全部脱敏**（合成账号、保留地址、重算摘要），可以公开。
- 真实凭据和原始抓包只放在 `local/PRIVATE.md`：被 `.gitignore` 排除，而且 `.git/hooks/pre-commit` 会拦下误提交。详见 [SECURITY.md](SECURITY.md)。
- 任何 `*.pcap` / `*.har` 都不入库。
- 推送前跑 `./scripts/privacy-scan.sh`；发布流程见 [docs/PUBLISH.md](docs/PUBLISH.md)。

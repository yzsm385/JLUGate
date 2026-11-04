# JLU Gate

吉林大学校园网的 macOS 菜单栏小工具。

在吉大用 Mac 上网，一直有点割裂：宿舍网线要 Dr.Com，JLU.PC 也是 Dr.Com，JLU.WIFI 又得开浏览器走网页认证——三个入口，账号密码却是同一套。每次换网络都得重新折腾一遍；真断网了，对着一句"未连接"干瞪眼，不知道是学校的事、DNS 的事，还是自己开的代理的事。

JLU Gate 想把这些收进一个菜单栏图标里。账号密码填一次，三种接入共用；该走哪条路它自己判断，掉线了替你重连。顺手把教务、OA、邮箱、WebVPN 这些常用入口也摆在一起，点一下就开；再带一套网络体检，断网时能一层一层告诉你卡在哪、出口 IP 干不干净。

> 只在校园网环境里有意义；只跑在 macOS 26 及以上。

## 下载

去 [Releases](https://github.com/yzsm385/JLUGate/releases) 拿最新版的 DMG（或 ZIP）。拖进「应用程序」，第一次打开右键 → 打开（没有 Apple 开发者证书，系统会提示"无法验证"，右键放行一次就好）。之后想更新，在 App 里「设置 → 更新 → 检查更新」就行：有新版会自己下载、退出、替换、再打开，不用手动覆盖。

## 它解决了什么

下面这些是写这个程序时真实遇到、想顺手解决掉的麻烦：

- **三种接入各有各的客户端，账号密码却只有一套。** 填一次，三网共用；记到钥匙串里，之后不再反复输入。
- **JLU.WIFI 只让 3 台设备，被新设备挤掉时毫无提示。** 掉线时会告诉你"你大概是被挤掉的"，并说明重新登录会把队列里最早的那台顶下去（可能就是你自己的另一台设备）。
- **学校按 MAC 认设备，系统换成"私有 MAC"就认证失败。** 程序读的是出厂 MAC 去认证，界面上把当前 / 出厂 / 登记三个值并排放出来，一眼能对上。
- **开着代理（小火箭 / Clash）时，认证包可能被绕路。** 实测"认证通道延迟：直连 vs 经代理"，用数据判断该不该为校园网段改规则。
- **断网说不清是谁的锅。** 逐站点分层排查（DNS → TCP → TLS → HTTP），直接给结论和下一步，而不是甩一句"网络错误"。
- **代理 IP 被"重点照顾"，却不知道为什么。** 多个数据源交叉判断是住宅还是机房，DNS 出口和 IP 出口是不是同一个国家。

## 能做什么

**接入**
- 自动识别该走 Dr.Com（UDP 61440）还是网页认证；判断不是校园网时，一个认证包都不发。
- 10 秒保活、掉线指数退避重连、休眠唤醒自动恢复、插拔网线自适应。
- 静态参数能用系统读数一键填入（**仅当这块网卡是手动配置时**，DHCP 一律不抄，免得把别人的配置抄错）。
- 可以按 MAC 自动认网卡，也可以手动指定。

**用起来**
- 菜单栏常驻，不占 Dock；状态用一句话讲清"现在是什么情况、你该做什么"。
- 每条解释都贴在对应的那一行旁边，不堆在底下；文案尽量说人话，少用术语。
- 有个启动看门狗：万一上次崩过，下次进安全模式（不自动连、不读密码），保证你能进来改配置。

**网络体检**（下面这些都是真去测的，不是查表估的）
- **能不能上网**：google / brave / duckduckgo / bing / 百度，加上教务、OA、邮箱，逐站指出卡在 DNS、TCP、TLS 还是网站本身。
- **出口 IP**：Cloudflare / ipify / ifconfig.me 三源交叉，带国旗。
- **WebRTC**：自己实现了 STUN，拿的就是浏览器 WebRTC 那个公网地址（UDP 被封时会明说"这种情况下反而不会泄漏"）。
- **DNS 泄漏**：反查解析出口；系统 DNS 被代理接管时，会如实告诉你"比不出来"。
- **人机验证可达性**：reCAPTCHA / 国内镜像 / Cloudflare Turnstile / CF 挑战页能不能打开。
- **IP 纯净度**：ipinfo / ipapi / ipwho / BiliBili（可选 IP2Location / MaxMind）交叉判断住宅 or 机房。
- **带宽三档**：直连 / 默认出口 / 本地代理（本地端口自动探测，不用手输）。

**吉大常用入口，收在一处**
- 教务、本科生院、研究生院、图书馆、OA、办事大厅、统一身份认证、学生 / 教师邮箱、WebVPN、校园网自助、网管中心、主页、新闻——十四个常用站点分五类摆好，不用每次翻收藏夹。
- 每个站点标了「仅校内 / 需 VPN / 公网」三种范围：在校外一眼能看出哪个得先连 WebVPN 才打得开。
- 能搜（按标题、域名或用途），点一下就用系统浏览器打开；支持账号登录的站点，打开时顺手把账号复制好，省得再切去填。
- 要密码的页面给「复制密码」按钮，复制后 60 秒自动清空剪贴板（只清自己写的那条，不会误删你新复制的东西）。
- 「我的学院」：填一次学号、选一次学院，之后就认得；四十四个学院能搜，一键开学院官网。
- 「校园网门户 / 今日广告」：认证成功后学校常弹一个欢迎 / 广告页，这里给你按钮直接开，不让它自动弹。

**安全上的克制**
- JLU.WIFI 认证走系统浏览器，程序不碰明文密码，也不做任何 DOM 操作或自动填充。
- 客户端做的预检只提示、不拦截；到底放不放进网，由学校服务器说了算。
- 卸载脚本会把 App、配置、日志和钥匙串里的条目一起删掉，不留残留。

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
| `App/` | SwiftUI 菜单栏应用（XcodeGen 工程描述在 `App/project.yml`） |
| `Tools/mock-gateway` | 按帧表应答的 Dr.Com 模拟网关（支持丢包 / 延迟 / 拒绝） |
| `Tools/mock-portal` | 模拟校园网页认证（302 → 登录页 → POST → 204） |
| `Fixtures/` | 抓包样本（含凭据摘要，**不要公开**） |
| `docs/` | CHECKLIST / PLAN / protocol-findings / progress / runbook |

## 构建 / 运行 App

没有开发者账号也能在本机跑起来（ad-hoc 签名，不能分发、不能公证）：

```bash
make app-bundle     # → dist/JLU Gate.app（菜单栏常驻）
open "dist/JLU Gate.app"
```

有账号、要签名和公证时，走 XcodeGen：

```bash
brew install xcodegen
cd App && xcodegen generate && open JLUGate.xcodeproj
```

## 隐私

- 仓库里的 `Fixtures/` 已经**全部脱敏**（合成账号、保留地址、重算摘要），可以公开。
- 真实凭据和原始抓包只放在 `local/PRIVATE.md`：被 `.gitignore` 排除，而且 `.git/hooks/pre-commit` 会拦下误提交。详见 [SECURITY.md](SECURITY.md)。
- 任何 `*.pcap` / `*.har` 都不入库。
- 推送前跑 `./scripts/privacy-scan.sh`；发布流程见 [docs/PUBLISH.md](docs/PUBLISH.md)。

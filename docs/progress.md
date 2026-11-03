# 施工进度（第一轮）

> 依据：[CHECKLIST.md](CHECKLIST.md)。本轮只做排序里要求的三块：
> **① 编码器 + 黄金测试 → ② 通道 + 状态机 → ③ UI**。
> 施工机（本机）**没有做任何真实认证、没有抓校园网包**（CHECKLIST §0 / PLAN §14）。

日期：2026-11-03 · 版本：0.1.0

---

## 1. 一句话结论

| 项 | 状态 |
|---|---|
| 342 字节登录包能否复现抓包 | ✅ 逐字节相同（含摘要 A） |
| 保活 A / B 能否复现抓包 | ✅ 逐字节相同（A 的 16 字节 = 登录摘要 A，已解） |
| 单元测试 | ✅ `swift test` 119 条全绿（Core 61 + Net 58） |
| 离线全流程（模拟网关） | ✅ `swift run jlugate-probe --self-test` 通过 |
| 真实认证 | ⛔ **未执行**，必须拿到环境 B 上跑（见 §6） |
| UI | ✅ 源码完成并通过编译校验；`.app` 需在装了 XcodeGen 的机器上生成（见 §5） |

---

## 2. 已交付的代码

```text
Sources/
├── JLUGateCore/            # 纯协议，无 I/O，可在任何平台编译
│   ├── Bytes.swift         # 带边界检查的偏移读写器（越界抛 .malformed）
│   ├── DNSPacket.swift     # 自带 DNS 的 A 记录查询/解析（含压缩指针）
│   ├── MD5.swift           # RFC 1321 自实现（不用 CryptoKit）
│   ├── Addresses.swift     # IPv4Address / MACAddress
│   ├── PacketLayout.swift  # 唯一允许出现魔法偏移的地方
│   ├── DrcomPacket.swift   # 上下文/结果/帧模型 + 随机源
│   ├── DrcomCodec.swift    # 编解码（challenge/login/keepalive A/B/分类）
│   ├── DrcomError.swift    # 12 类错误，每类一句话 + 是否可重试/需用户
│   ├── SessionState.swift  # 状态 + 合法转移表
│   └── Backoff.swift       # min(60, 2×2^n) + jitter(0…3)，8 次封顶
├── JLUGateNet/
│   ├── DatagramChannel.swift   # 通道/时钟/网卡快照/路由契约
│   ├── BSDChannel.swift        # IP_BOUND_IF + bind(61440) + poll 收包
│   ├── NWChannel.swift         # NWParameters.udp + requiredInterface + requiredLocalEndpoint
│   ├── InterfaceResolver.swift # getifaddrs + route get + ipconfig getsummary
│   ├── PathMonitor.swift       # NWPathMonitor → PathEvent
│   ├── ConnectivityProbe.swift # 自带 DNS 的 204 探针（BSD 传输实现）
│   ├── PortalDetector.swift    # 门户入口解析（Location / form action / meta refresh）
│   ├── PortalEngine.swift      # JLU.WIFI 状态子集 + Cookie 静默 + 弹窗节流
│   ├── AuthCoordinator.swift   # AccessLink / AuthProvider / 选链路 / 遥测转发 / teardown
│   ├── RouteGuard.swift        # 三层路由判定 + helper 参数白名单
│   └── DrcomEngine.swift       # actor + epoch 状态机 + 保活 + 退避
├── jlugate-probe/          # --self-test / --interfaces / --route-check / --dump-login / --login
App/                        # MenuBarExtra + Liquid Glass（SwiftUI）
Tools/mock-gateway/mock_gateway.py
Tests/                      # Swift Testing：Core 40 + Net 11
Fixtures/session_sanitized.json  # 由原始抓包导出的 50 帧（已脱敏）
```

---

## 3. 验收命令与结果

```bash
# 1) 黄金测试（摘要 A + 342 字节复现 + 保活复现 + 状态/退避）
swift test --filter JLUGateCoreTests
#    → 40 tests passed

# 2) 离线全流程：对 127.0.0.1 的模拟网关跑 challenge→login→keepalive
swift run jlugate-probe --self-test
#    → 状态序列 idle → discovering → challenging → authenticating → online → idle
#    → 保活 A/B 各应答，✅ 自测通过

# 3) 全量
swift test
#    → 119 tests passed
```

> **本机注意**：这个工作区跑在受限沙箱里，SwiftPM 需要把缓存与临时目录指到工作区内、
> 并加 `--disable-sandbox`，否则会报 `Operation not permitted`。正常 Mac 上直接
> `swift test` / `swift run jlugate-probe --self-test` 即可（`make test` 已封装）。

实测日志（摘录）：

```
状态 → discovering / challenging / authenticating / online
会话建立：20230001 @ 192.0.2.10 session=0x631d
保活应答：在线 1s 统计 [732, 1, 9, 0, 1240, 653481]
c2s  20 01031d6331000000000000000000000000000000
s2c  76 02031d63<salt>…318c3b6f
c2s 342 0301001f<digest>…（342 字节）
s2c  45 0400000500d9040000b2f80900…Drco…
c2s  38 ff<digest>000000Drco…
```

---

## 4. 实测修订：CHECKLIST 里需要改的 14 处

> 全部以 `docs/captures/login.pcap` 的字节为准（不是推测）。
> 代码按右列实现，`PacketLayout` 里每处都有注释注明依据。

| # | CHECKLIST / findings 写法 | 抓包实测 | 说明 |
|---|---|---|---|
| 1 | 失败原因串在 `0x18` | **`0x14`** | `ldap…` 的 `l` 就在 0x14 |
| 2 | 原因串是 `ldap.auth error` | **`ldap auth error`**（空格，没有点） | 真机上要照抄服务器串，别自己补标点 |
| 3 | 未知区② `0x066`×8 | **`0x061..0x068`**（8 字节） | 两次登录的差异区间在这里 |
| 4 | 未知区③ `0x13A` 整 16 字节随机 | **`0x13A..0x143` 随机 + `0x144..0x145 = 02 0c` + `0x146..0x149` 随机** | 中间的 `02 0c` 两次完全一致，是常量 |
| 5 | 保活 A `0x11–0x13 = C1 00 00 00` | **`C1` 是 0x10**，`0x11..0x13 = 00 00 00` | `C1` 是"16 字节摘要"的最后一字节 |
| 6 | 保活 A `0x01–0x10` 疑似摘要（未解） | **就是登录摘要 A** | 20:29:52 之后的保活里，这 16 字节与那次登录包 `0x004` 完全相同 |
| 7 | 保活 A `0x24–0x25` "会话号" | **小端 16 位秒计数** | `40 63`→`53 63`→…→`a3 63`，即 0x6340→0x63a3；两次包隔 35s，值也涨 35 |
| 8 | 保活 A 客户端 IP 在 `0x1C` | **`0x1E..0x21`**；`0x1C..0x1D` 是服务器下发的 2 字节 | 该 2 字节与登录成功包 `Drco` 块里的同名字段一致 |
| 9 | 保活 B `0x14–0x17` 每包不同 | **镜像字段在 `0x10`**（回抄服务器上次的值）；**每包不同的是 `0x18..0x1B`**；客户端 IP 在 `0x1C` | 与 §6.2 的"`00×4 <check:4>`"公式一致 |
| 10 | 保活 B `0x02–0x03 = 28 00` | 同上，是**小端 40** | 按大端读会得到 10240 |
| 11 | 保活 A 应答统计从 `0x20` 起 5 个 | **`0x1C` 起 6 个小端 u32** | `stats[1]` 实测每约 20s +20（在线秒数） |
| 12 | —（未记载） | **challenge 应答 `0x26..0x27` = 服务器会话别名（小端 732）** | 保活 B 的 `0x06–0x07`、保活 A 应答 `stats[0]` 都是它 |
| 13 | 登录成功包"`0x18` 起是 Drco" | **`Drco` 块起点是 `0x17`** | 之后的相对结构固定：`+4` 服务器 IP、`+8` 不透明 2B、`+10` 客户端 IP、`+14` 不透明 2B |
| 14 | —（未记载） | 登录成功包尾部两个"不透明 2 字节"要**带进保活 A** | 抓包里 `e6 87` / `01 45` 原样出现在后续每一个保活 A 请求里 |

**结论**：CHECKLIST §11 里"未解"的 5 处中，**保活 A 的 16 字节已解（= 摘要 A）**、
**"会话号"已解（秒计数）**；剩下真正未知的是登录包的 4 处随机区、保活 B 的 4 字节校验。

> 建议把上表合并回 `CHECKLIST.md` / `protocol-findings.md`；本轮没有直接改那两份文档，
> 以免与人工维护的原文冲突。

---

## 4.5 本轮新增：探针 + 链路协调器（离线可测）

| 组件 | 行为 | 测试 |
|---|---|---|
| `DNSPacket`（Core） | 只查 A 记录；处理名字压缩指针；rcode≠0、越界一律抛错 | 5 条 |
| `ConnectivityProbe`（Net） | 目标 `generate_204`，学校 DNS 不通时回落内置字面 IP；204=健康、200/30x=门户、连不上=异常 | 7 条 |
| `AuthCoordinator`（Net） | `auto` 下：challenge 有回执→有线/JLU.PC；否则 204 被拦→JLU.WIFI；204 已通→直接 online；都不通→`failed(.notCampusNetwork)` | 10 条 |
| `DrcomAuthProvider` | 把 `DrcomEngine` 包成 `AuthProvider`（`AsyncStream<AuthState>`） | 间接覆盖 |

三个刻意的设计点：

1. **探测只发 1 个 challenge、3s 超时、不重试**（PLAN §5.4.4），并且 `autoDetect = false` 时就完全不碰网关。
2. **切换链路先 teardown**：`stop()` 一定 `await provider.stop()`，避免"Portal 已登录、UDP 还在保活"的双活。
3. **用户显式指定链路时不做探测**：即使 challenge 没回执也照用（用户可能知道得比探针多），失败原因由引擎逐条报。

新增两个错误分类（原 CHECKLIST §8 列表之外，理由都写进 `userMessage`）：

- `notCampusNetwork(detail:)` —— 两个探针都不通时给的一句话；
- `unsupportedLink(_:)` —— 选到了还没实现的链路（如 `JLU.WIFI`），**不进重试**。

> App 层已改为**全部经协调器**：`AppModel` 只订阅 `AuthCoordinator.Event`，
> 保活流量通过 `SessionTelemetryProviding` 转发上来（`.telemetry(.traffic(...))`），UI 事件没丢。

### 4.6 网页认证（`JLU.WIFI`）

| 组件 | 行为 | 测试 |
|---|---|---|
| `PortalDetector` | 302 的 Location → 入口；200 页面里抓 `<form action>` / meta refresh；都没有就回落配置入口 | 5 条 |
| `PortalEngine` | `detect → 静默重试 → 弹窗 → 204 确认 → online`；在线时探针连败 2 次回到 `authenticating`；弹窗 1 次/5 分钟 | 8 条 |
| `WKPortalBrowser`（App） | 真正的 `WKWebView` 窗口，Cookie 落盘可复用；**无任何 DOM 操作/表单填充**（决策 D-001） | 编译校验 |
| `Tools/mock-portal` | 302 → 登录页 → POST → 204 的完整门户 | `make portal-self-test` |
| `scripts/portal-app-e2e.sh` | **真实 App 二进制**跑通「探测 → 登录窗 → 204 → online」 | `make portal-e2e`（脚本化浏览器）/ `--window`（真实 WKWebView） |

刻意不做的事（决策 D-001，2026-11-03）：**不重放表单、不预填**。
`PortalBrowser.presentLogin(url:)` 只接收 URL，账号密码根本不进入浏览器接口；
认证永远是"浏览器里点一下"，页面改版/JS 加密/验证码都不会让客户端失效。
`PortalCredentials` / `PortalConfiguration.autoFill` / `AppConfig.portal.autoFill` / `WKWebView.evaluateJavaScript` 全部已删除。

### 4.7 路由保障（M2.5 的离线部分）

| 组件 | 行为 | 测试 |
|---|---|---|
| `RouteGuard` | A（出口已是物理口）/ B（helper 加 `-ifscope` /32）/ C（给可复制命令）/ 无路由，四态 | 7 条 |
| `RouteValidator` | host 必须在 /32 白名单、gateway 必须是 IPv4 字面量（挡住注入）、接口必须 `enN`、网关必须与接口一致 | 7 条 |

helper 进程本身（`SMAppService.daemon` + 签名）仍属 M2.5：**没有开发者账号签不出来**，
但最容易出事的那部分（参数白名单、argv 拼装、拒绝非法入参）已经离线测完了。

### 4.8 App 收尾（也都是离线能做完的）

| 项 | 实现 |
|---|---|
| 单实例 | `NSRunningApplication` 查重 → 激活已有实例并退出自己（避免两个进程抢 61440） |
| 文件日志 | `~/Library/Logs/JLUGate/agent.log`，2 MB 滚动一份，诊断包带最近 120 行 |
| 诊断导出 | 菜单"导出" → 临时目录 .txt + 访达定位；内容含接口/路由/ConfigMethod/端口占用/日志尾 |
| 网络参数卡 | 文本进剪贴板 + `CIFilter.qrCodeGenerator` 生成二维码 PNG（**不含密码**） |
| 鲁棒性 | 3000 个随机载荷的 fuzz：`classify` 不崩、解析器只抛错、DNS 解析不越界 |
| App Nap | `online` 期间 `ProcessInfo.beginActivity([.userInitiatedAllowingIdleSystemSleep])`，掉线/退出即释放（PLAN §3.2） |
| 失败通知 | 只有 `requiresUserAction` 的失败才发系统通知，同一原因只提醒一次；超时/退避静默（PLAN §3.2） |
| 账号格式 | 邮箱前缀自动归一化；学生/教师两种规则实时判定并提示（`AccountFormat`，6 条单测） |
| 三台上限 | JLU.WIFI 被挤下线 → 立刻重进（绕过 5 分钟冷却）+ 说明「会踢掉队列第二台」（+1 条引擎测试） |
| 网口说明 | 每个网口都有"用途 + 持有者 + 能不能认证"的白话解释（`InterfaceNarrator` 6 条单测） |
| 代理模式 | 用 `route get` 实测判定 直连 / 规则(校园网已直连) / 全局 / TUN 未生效，并可与用户自述的小火箭模式对照（`ProxyModeAnalyzer` 6 条单测） |
| 网络详情窗 | 网口/路由/DNS/VPN 可视化 + 每个字段白话解释 + Ping（直连 vs VPN）+ 测速对比（`FieldGuide`/`Throughput`/`PingSummary` 4 条单测） |
| 被动观测 | 未配账号但网络本来就通 → 直接显示"已连接"，不逼输密码；只有需要认证时才弹一次向导（`PassiveMonitor` 4 条单测） |
| 网卡类型 | 改用 SystemConfiguration 判定 Wi-Fi/USB，去掉 `networksetup` 子进程（修掉 dispatch_once 重入导致的崩溃） |
| 启动策略 | 账号密码记住且成功连过 → 静默自动连；只有缺凭据/缺静态地址才弹向导（`LaunchPolicy`，6 条单测） |
| 向导顺序 | 账号密码 → 接入方式 →（按需）网络参数；有线/JLU.PC 填过后不再追问（`WizardPolicy`，6 条单测） |
| 网络跃迁 | `PathMonitor` 事件去抖 1.5s → 自动 `retry()`；拔插网线不再等 30s 心跳超时（PLAN §8.6 的 ≤5s） |
| 拔线语义 | `adapterUnplugged` / `interfaceHasNoIPv4` 直接 `failed`，**不进退避空转**，等网络变化再重来（PLAN §6.3） |
| 地址漂移 | 接口 IP / 掩码与档案不一致 → `staticConfigMismatch`，一个认证包都不发（PLAN §6.3） |
| 参数卡导入 | 剪贴板里的参数卡可解析还原（全角冒号、乱序、注释都能吃）；**不含密码** |
| 静态参数校验 | 掩码连续性、"网关是否同网段"、"网关=本机 IP"、MAC 格式，全部在向导里当场拦下 |
| USB 网卡 | 用 `networksetup -listallhardwareports` 标出 USB 口（拔插换名时诊断用） |

---

## 5. UI 与构建

- `App/Sources/*`：`MenuBarExtra(.window)`、`GlassEffectContainer` + `.glassEffect(.regular.tint(...).interactive(), in: .rect(cornerRadius: 16))`、
  `.buttonStyle(.glass)`、`SettingsLink`、`LSUIElement`（由 `project.yml` 的 `INFOPLIST_KEY_LSUIElement` 注入）。
- 状态卡四态图标、链路/本机 IP/在线时长、失败原因**原样展示**、复制诊断、退出。
- 设置页：账号 / 密码（Keychain）/ 链路 / 通道实现 / **手填静态参数**（不自动填充）/ 服务器端口 / 开机自启；
  下方灰字展示"系统当前值（仅供核对）"。
- 休眠/唤醒：`willSleep` 关通道停任务（**不发 Logout**），`didWake` 等 2s 后由引擎重新获取一切。

生成 `.app`（本机没装 XcodeGen，未生成工程文件）：

```bash
brew install xcodegen
cd App && xcodegen generate && open JLUGate.xcodeproj
# 或：xcodebuild -project App/JLUGate.xcodeproj -scheme JLUGate -configuration Release build
```

> SwiftUI 源码不是"写完就交"：`Package.swift` 里有一个 `AppCompileCheck` target，
> 把 `App/Sources` 一起编译，所以 `swift build` 会连带校验 UI 层 API 是否仍然编译得过。

---

## 6. 真机上要做的三件事（施工机做不了）

### 6.1 打包 universal CLI

```bash
swift build -c release --arch arm64 --arch x86_64   # 产物在 .build/apple/Products/Release/jlugate-probe
lipo -info .build/apple/Products/Release/jlugate-probe
```

### 6.2 到环境 B 上按顺序跑

```bash
# 0) 先做只读诊断（3 秒，不影响上网）
./jlugate-probe --interfaces          # 确认有线口的 MAC，与学校登记值对一下
./jlugate-probe --route-check         # 确认 10.100.61.3 出口是物理口、ConfigMethod=Manual

# 1) 认证（会把官方客户端顶掉一次，先约定窗口）
sudo lsof -nP -iUDP:61440             # 官方 drcomauth 占着就先用官方客户端退出
./jlugate-probe --login --account <学号> --password <密码> --mac <登记MAC> --seconds 60

# 2) 抓包对照
sudo tcpdump -i en7 -n -s 0 -X "udp port 61440" -w ~/Desktop/jlugate.pcap
```

判定标准（CHECKLIST §11）：**能登录 + 能撑 10 分钟不掉线**就说明随机区不需要精确复现。

### 6.3 回传什么

`--login` 的终端输出 + `jlugate.pcap`。日志里不含密码，但**含摘要 A**，按敏感数据处理。

---

## 7. 完成度总览：哪些做完了、哪些还缺、缺在谁身上

| 里程碑 | 状态 | 说明 |
|---|---|---|
| M0 工具先行 | ✅ | `jlugate-probe`（self-test / portal-self-test / interfaces / route-check / detect / dump-login / login）、mock-gateway、mock-portal、脱敏夹具 |
| M1 协议核心 | ✅ | 342 字节逐字节复现、摘要 A 黄金向量、保活 A/B 复现、fuzz |
| M2 通道与引擎 | ✅ | BSD/NW 双通道、接口解析、路由/TUN 判定、actor + epoch 状态机、退避 |
| M2.5 路由 helper | ⚠️ 一半 | 参数白名单 + argv 拼装 + 三层判定已实现并测完；**daemon 本体未写**：`SMAppService.daemon` 必须先签名，没账号（OPEN-ITEMS A1）写出来也是死码，且无法验证 |
| M3 真机联调 | ⏳ 待环境 B | 编码器对真实网关、DHCP/Manual、TUN、休眠唤醒、Portal 真实字段 |
| M4 菜单栏 App + 向导 | ✅（源码） | 状态/链路/路由提示、向导、设置、诊断导出、参数卡、单实例、App Nap、失败通知；`.app` 需 `xcodegen generate` |
| M4.5 Portal | ✅ | 决策 D-001 落地：不做表单自动化，只做检测 + Cookie 复用 + 失败弹窗 |
| M5 打包分发 | ⏳ 待 A1 | 签名 / 公证 / 分发渠道 |
| M6 长稳 | ⏳ 待环境 B | 8h / 24h 观察 |

### 7.1 仍需外部条件的项（不是"没做"，是"做不了"）

| 项 | 卡在哪 | 我能做的已做 |
|---|---|---|
| Route helper daemon | Apple Developer 账号（签名） | 校验/白名单/argv/三层判定全测完；daemon 一旦有账号 1 天可补 |
| 真机认证与抓包 | 环境 B（另一台有线 Mac） | `docs/runbook.md` 已写成可照做的手册 |
| Portal 真实字段/入口 | U10 的 HAR | 现走 WKWebView，不依赖字段名；HAR 只用于优化入口猜测 |
| 有线口"挑战探测 +4 分" | 真网关 | 协调器已实现"1 个 challenge 判定链路"；引擎内部选口仍按 MAC+有线+IPv4 打分 |

### 7.2 刻意没做（有理由）

| 项 | 理由 |
|---|---|
| 表单自动填充 / 重放 | 决策 D-001：门户结构未公开，改版即失效；收益远小于脆弱面 |
| 界面本地化 | 目标用户是中文用户，v1 不做多语言 |
| 自绘毛玻璃 | 与系统 Liquid Glass 打架（PLAN §9） |

---

## 8. 本机环境观察（供环境 B 对照）

| 现象 | 本机 | 说明 |
|---|---|---|
| `getifaddrs` 的 AF_LINK | 多数接口给 `02:00:00:00:00:00` | 已在 `InterfaceResolver` 里加 `ifconfig` 回落；环境 B 应直接可用 |
| `networksetup -getmacaddress en0` | 硬件地址（示例 `02:00:00:00:00:01`） | 与 `ifconfig ether` 可能不同（隐私地址）；**登录要用 on-wire 那个** |
| 代理 TUN | 有（198.18.0.x） | `--route-check` 会报"出口是虚拟接口"，此时不该发认证包 |

> 因此本轮任何"本机跑一下真实登录"的尝试都被**主动跳过**（CHECKLIST §0 第 1 条）。

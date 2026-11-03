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
| 单元测试 | ✅ `swift test` 74 条全绿（Core 45 + Net 29） |
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
│   ├── AuthCoordinator.swift   # AccessLink / AuthProvider / 选链路 / teardown
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
#    → 74 tests passed
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

> App 层目前仍直连 `DrcomEngine`：协调器选完链路后还要能拿到保活流量统计，等 Portal 落地时
> 再统一改成"协调器 + 双 provider"，避免现在为了统一而把 UI 事件流砍掉一半。

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

## 7. 本轮没做（按 CHECKLIST/PLAN 顺序留到下一轮）

| 项 | 位置 | 原因 / 前置 |
|---|---|---|
| ~~`ConnectivityProbe`（自带 DNS 的 204 探针）~~ | PLAN §8.2 | ✅ 已实现并在离线单测覆盖（判定矩阵 7 条） |
| ~~`AuthCoordinator` 多链路切换~~ | PLAN §4 | ✅ 已实现（选链路/teardown/状态透传，10 条单测）；App 仍直连引擎，见下 |
| `JLUGateRouteHelper`（root LaunchDaemon） | PLAN §6.6 / M2.5 | 需要签名与 `SMAppService.daemon`，属 M2.5 |
| `PortalEngine` / `PortalDetector` / `WKWebView` 登录窗 | PLAN §5.4 / M4.5 | `JLU.WIFI` 链路，需 U10（HAR）；当前协调器选中 `.jluWiFi` 后会得到一个明确的 `unsupportedLink` 失败 |
| 链路选择的 "challenge 探测 +4 分" | PLAN §6.3 | 需要真网关；当前按 MAC + 有线 + IPv4 打分，探测留到 M3 |
| 界面本地化（String Catalog） | — | 当前为中文硬编码 |

---

## 8. 本机环境观察（供环境 B 对照）

| 现象 | 本机 | 说明 |
|---|---|---|
| `getifaddrs` 的 AF_LINK | 多数接口给 `02:00:00:00:00:00` | 已在 `InterfaceResolver` 里加 `ifconfig` 回落；环境 B 应直接可用 |
| `networksetup -getmacaddress en0` | 硬件地址（示例 `02:00:00:00:00:01`） | 与 `ifconfig ether` 可能不同（隐私地址）；**登录要用 on-wire 那个** |
| 代理 TUN | 有（198.18.0.x） | `--route-check` 会报"出口是虚拟接口"，此时不该发认证包 |

> 因此本轮任何"本机跑一下真实登录"的尝试都被**主动跳过**（CHECKLIST §0 第 1 条）。

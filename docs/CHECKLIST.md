# 施工清单（交接版）

> 给接手的施工方：**照这份做，不要重新设计**。协议细节全部来自真实抓包（见 [protocol-findings.md](protocol-findings.md)），不是推测。
> 上层设计与决策见 [PLAN.md](PLAN.md)；未决问题见 [OPEN-ITEMS.md](OPEN-ITEMS.md)。
> 版本：v1 · 2026-11-02

---

## 0. 三条铁律

1. **施工机（本机）没有任何 Dr.Com 环境**，跑不了任何联网验证。所有真机测试必须打包后拿到另一台有线 Mac 上跑。
2. **报文只能按本文件的偏移填**，不许自创字段、不许"看着差不多"。
3. **先证伪环境，再怀疑凭据**：接口/MAC/DHCP/路由任何一项不对，都不要发认证包。

---

## 1. 开工

```bash
cd ~/Documents/JLUGate
git init && printf '.build/\n*.xcuserstate\nFixtures/*.pcap\ndocs/captures/*.pcap\n' > .gitignore
mkdir -p Sources/{JLUGateCore,JLUGateNet,JLUGateRouteHelper,jlugate-probe} Tests/{JLUGateCoreTests,JLUGateNetTests} App Tools/mock-gateway Fixtures
swift package init --type library 2>/dev/null || true   # 之后改成多 target
```

`Package.swift`：`swift-tools-version: 6.0`，`platforms: [.macOS("26.0")]`，`swiftLanguageModes: [.v6]`。

---

## 2. 协议常量（全部实测）

| 名称 | 值 | 说明 |
|---|---|---|
| 服务器 | `10.100.61.3` | 可配置 |
| 服务器端口 | `61440` | |
| **本地端口** | `61440` | 实测源端口就是 61440，必须 `bind` |
| 客户端版本串 | `25.6.0` | 登录包 0xC0，**必须照抄** |
| 魔数 | `DrCOM` | 登录包 0xB6，登录/保活都有 |
| 静态令牌 | `56c68373463f4cd5b73dd3ac5e3673000a5fdd7e` | 40 个 ASCII 字符，两次登录完全一致，直接当常量 |

---

## 3. 报文一：Challenge（C→S，20 字节）

```
01 03 <serial:2> 31 00 ×15
```

| 偏移 | 值 | 来源 |
|---|---|---|
| 0x00 | `0x01` | 常量 |
| 0x01 | `0x03` | 常量（后续重试会变成 04、05…） |
| 0x02–0x03 | 序号 | 随机 UInt16 即可（实测 `1d63`/`2f63`/`3f63`） |
| 0x04 | `0x31` | 常量 |
| 0x05–0x13 | 0 | |

## 4. 报文二：Challenge 应答（S→C，76 字节）——**解析它取 salt**

| 偏移 | 内容 |
|---|---|
| 0x00–0x01 | `02 <subtype>` 回显 |
| 0x02–0x03 | 回显序号 |
| **0x04–0x07** | **salt（4 字节）** ← 登录摘要要用的就是它 |
| 0x14–0x17 | 客户端 IP |
| 其余 | 参数/保留 |

**坑**：一次登录流程里可能连着来好几次 challenge，**必须取"紧挨着本次登录"的那一次**的 salt。取错一个，MD5 永远算不对，而服务器只会回 `ldap.auth error`，查不出原因。

---

## 5. 报文三：登录包（C→S，**342 字节**）

### 5.1 字段表

| 偏移 | 长度 | 内容 | 类型 |
|---|---|---|---|
| 0x000 | 1 | `0x03` | 常量 |
| 0x001 | 1 | `0x01` | 常量 |
| 0x002 | 2 | `00 1F` | 常量（两次一致） |
| **0x004** | 16 | **摘要 A = MD5(0x03‖0x01‖salt‖password)** | 计算 |
| **0x014** | 32 | 账号，NUL 填充 | 配置 |
| 0x034 | 6 | `00` ×6 | 常量 |
| 0x03A | 22 | 未知区（两次登录全不同） | **随机 22 字节** |
| 0x050 | 1 | `0x02` | 常量 |
| **0x051** | 4 | 客户端 IPv4 | 运行时 |
| **0x055** | 4 | 接口的**链路本地 IPv4**（实测 `169.254.1.1`；没有就全 0） | 运行时 |
| 0x059 | 13 | `00` ×13 | 常量 |
| 0x066 | 8 | 未知区（两次不同） | **随机 8 字节** |
| **0x06E** | 26 | 主机名 `XXX.local`，NUL 填充至 0x88 | 运行时 |
| 0x088 | 45 | `00` | 常量 |
| 0x0B5 | 1 | `0x02` | 常量 |
| 0x0B6 | 5 | `DrCOM` | 常量 |
| 0x0BB | 5 | `00 CF 07 31 00` | 常量 |
| **0x0C0** | 6 | `25.6.0` | 常量 |
| 0x0C6 | 48 | `00` | 常量 |
| **0x0F6** | 40 | `56c6…dd7e`（ASCII） | 常量 |
| 0x11E | 24 | `00` | 常量 |
| 0x136 | 4 | `31 00 00 0A` | 常量 |
| 0x13A | 16 | 未知区（两次不同） | **随机 16 字节** |
| 0x14A | 2 | `00 00` | 常量 |
| **0x14C** | 6 | **接口 MAC** | 运行时 |
| 0x152 | 2 | `00 00` | 常量 |
| 0x154 | 2 | 未知（两次不同） | 随机 2 字节，先填 `0000` |

> "未知区"共 5 处（0x03A×22、0x066×8、0x13A×16、0x154×2）。它们到底是随机还是跟 salt/会话相关，目前**没解出来**；先填随机值，真机跑一次就知道服务端认不认（见 §10）。

### 5.2 摘要 A（已用真实样本逐字节验证 ✅）

```swift
let digestA = Insecure.MD5.hash(data: Data([0x03, 0x01]) + salt + Data(password.utf8))
```

**黄金测试向量（必须写进单测）**：

```
account  = "20230001"
password = "test-pass-2024"
salt     = 49 cb 72 0f
→ digestA = 13 bd e6 0a 98 1b 4e 94 b7 64 d4 02 d1 2f 2d 3c
```

### 5.3 登录结果

| 帧 | 长度 | 含义 | 处理 |
|---|---|---|---|
| `04 00 …` | **45** | **成功** | 进 `online`，起保活 |
| `05 00 …` | **37** | **失败** | 原因串在 **0x18**，NUL 结尾，**原样展示给用户** |

实测失败样本：`ldap.auth error`（密码错）。不要自己翻译成"密码错误"——欠费/顶号大概率是同一位置的别的字符串。

---

## 6. 报文四：保活（两型交替）

### 6.1 A 型：38 → 72

请求（38）：

| 偏移 | 内容 |
|---|---|
| 0x00 | `0xFF`（**不是 0x07**） |
| 0x01–0x10 | 16 字节，会话内固定（疑似摘要，**未解**） |
| 0x11–0x13 | `C1 00 00 00` |
| 0x14 | `Drcom` 魔数 + 服务器 IP + 客户端 IP |
| 0x20–0x21 | `01 F4` |
| 0x24–0x25 | 会话号（= 本次 challenge 的序号） |

应答（72）：`07 01 10 00 06 00 <会话号> …`，其中 0x20 起是**流量/时长统计**（`dc 02 00 00`、`26 00 00 00`、`09 00 00 00`、`d8 04 00 00`、`a9 f8 09 00`），可读出来显示"本次已用流量"。

### 6.2 B 型：40 → 40

```
07 <round> 28 00 0B <seq> DC 02 <time:4> 00×4 <check:4> 00×24
```

- `0x01` = **轮次计数**（实测 05,06,07,08,09,0A,0B,0C 递增）
- `0x02–0x03` = `28 00` = 40（长度）
- `0x05` = **包计数**，01→02→03→04，**请求与应答共用同一个计数**
- `0x06–0x07` = `DC 02` 会话号
- `0x08–0x0B` = 时间戳
- `0x14–0x17` = 每包不同的 4 字节（疑似校验，**未解**）

> 序号必须按"每收一包 +1"推进，只按自己发了几次计数会错位。

### 6.3 调度

A/B 交替，约每 10s 一轮；A 型一轮内可连发两对。连续 3 轮无应答 → 重连。

---

## 7. 网络层（决定成败的地方）

| 项 | 做法 |
|---|---|
| 选口 | 按 **MAC 命中**（+8 权重）→ 有线 +2 → 有默认路由 +1 → challenge 探测成功 +4，取最高分 |
| 源 IP | `bind(localIP)`，**不要靠内核选** |
| 出口 | `IP_BOUND_IF`（BSD）或 `requiredInterface`（NW）；两套实现共用 `DatagramChannel` 协议 |
| 端口 | 绑 61440；`EADDRINUSE` 时先 `lsof` 认人，是 `drcomauth` 就提示卸载官方 daemon |
| 静态配置 | 认证前查 `ipconfig getsummary <if>` 的 `ConfigMethod`，**不是 Manual 就直接报错不发包** |
| 路由 | `route get 10.100.61.3`；出口是 utun → 三层降级：直连 / helper 加 `-ifscope` 的 `/32` / 给用户可复制命令 |
| DNS | **不要用系统 DNS**（被代理劫持成 `198.18.0.2`）；探针自己向学校 DNS 发 UDP 53 查询 |
| 休眠 | `willSleep` 全关；`didWake` 等 2s 后**重建 socket**，ifindex/MAC/IP 全部重读 |

---

## 8. 状态与错误

状态：`idle → discovering → challenging → authenticating → online → reconnecting → failed`。
并发：`actor` + `epoch` 世代号，旧任务不许写新状态。

错误必须分类（每类一句话，不许笼统"登录失败"）：
`macMismatch` / `interfaceHasNoIPv4` / `adapterUnplugged` / `dhcpAssigned` / `staticConfigMismatch` / `gatewayUnreachable` / `capturedByTunnel` / `officialClientRunning` / `localPortInUse` / `accountInUse` / `macInUse` / `rejected(reason:)`。

其中 `rejected` 的原因串**直接来自服务器**。

---

## 9. UI（macOS 26 / Liquid Glass）

- 名称 **JLU Gate**，`LSUIElement=YES`，`MenuBarExtra` + `.menuBarExtraStyle(.window)`
- 玻璃：`GlassEffectContainer { … }.glassEffect(.regular.tint(statusColor).interactive(), in: .rect(cornerRadius: 16))`
- 可用 API（已在 SDK 核对，全部 macOS 26.0+）：`Glass.regular/.clear/.identity`、`.tint()`、`.interactive()`、`.glassEffect(_:in:)`、`GlassEffectContainer(spacing:)`、`.glassEffectID(_:in:)`
- 不要用 `NSVisualEffectView` 自绘，会和系统玻璃打架

---

## 10. 怎么在没有校园网的情况下验证（关键）

### 10.1 黄金测试：复现那次"错密码登录"

我们有**完整的已知样本**（账号 `20230001`、密码 `test-pass-2024`、salt `49cb720f`）：

```
构造 342 字节登录包，除 0x03A(22B) / 0x066(8B) / 0x13A(16B) / 0x154(2B) 外，
必须与 capture 逐字节相同。
```

把抓包存成 `Fixtures/login_golden.hex`，单测直接比对。**这条过了，编码器就是对的。**

### 10.2 模拟网关

`Tools/mock-gateway/mock_gateway.py`：按帧表应答（20→76 给 salt、342→45、38→72、40→40），支持 `--loss/--delay/--reject-reason`。

### 10.3 真机三步

1. 打包 universal CLI：`swift build -c release` + `lipo`
2. 拿到有线 Mac 跑：`./jlugate-probe --login`
3. 回传日志与 `tcpdump -i en7 -n "udp port 61440"` 输出

---

## 11. 未解项（不阻塞，按此策略处理）

| 项 | 策略 |
|---|---|
| 登录包 5 处未知区 | 先随机；若被拒，改成"复制抓包常量"重试；仍拒 → 需要再抓一次 |
| 保活 A 的 16 字节开头 | 先复制抓包值；若被拒再研究 |
| 保活 B 的 `0x14–0x17` 4 字节 | 每包随机，观察服务端是否拒绝 |
| 摘要 B（0x03A 前 16 字节） | 同"未知区"处理 |

> 判定标准很简单：**真机能登录、能撑 10 分钟不掉线**，就说明这些字段不需要精确复现。

---

## 12. 禁止事项

- 禁止在施工机发起任何认证（会顶掉另一台设备）
- 禁止把 `192.0.2.1`、`10.10.10.10`、`192.0.2.10` 写成默认值
- 禁止用系统 DNS 做连通性探针
- 禁止用随机本地端口（实测 61440）
- 禁止 `reconnecting` 时无限重登（会形成顶号乒乓）
- 禁止 helper 执行 shell 字符串或接受任意目标地址
- 禁止照抄旧文档的 128/334/44/0x07-challenge —— 全部作废

---

## 13. 第一个里程碑的验收命令

```bash
swift test --filter JLUGateCoreTests     # 黄金向量 + 342 字节复现
swift run jlugate-probe --self-test      # 离线：对着 mock gateway 跑完整流程
```

两条全绿，再进真机。

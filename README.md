# JLU Gate

**吉林大学校园网的一体化 Mac 客户端 + 网络体检工具。**

把「有线 Dr.Com」「JLU.PC 无线 Dr.Com」「JLU.WIFI 网页认证」三条路收进一个菜单栏应用，
再用一套真实测量的体检工具回答两个问题：**为什么上不了网**，以及**我的出口 IP 够不够干净**。

## 解决什么

| 真实痛点 | 本程序的做法 |
|---|---|
| 三种接入各有各的客户端，账号密码却只有一套 | 账号密码填一次，三网共用；记住后不再反复输入 |
| JLU.WIFI 只允许 3 台设备，被新设备挤掉毫无提示 | 掉线时提示"你是被挤掉的"，并说明会顶掉队列里的第二台 |
| 学校按 MAC 认设备，系统换私有 MAC 就认证失败 | 读**出厂 MAC** 去认证；并在界面上并排列出当前/出厂/登记三个值 |
| 小火箭/Clash 接管路由后，认证包可能绕路 | 实测"认证通道延迟：直连 vs 经代理"，用数据判断该不该改规则 |
| 断网时说不清是校园网、DNS、代理还是网站的问题 | 逐站点分层排查（DNS→TCP→TLS→HTTP），直接给结论和下一步 |
| 机场/住宅代理的 IP 被重点照顾，却不知道为什么 | 多源交叉判定住宅/机房、DNS 出口与 IP 出口是否同国 |

## 能力一览

**接入**
- 自动识别该走 Dr.Com（UDP 61440）还是网页认证；不是校园网就不发任何认证包
- 10 秒保活、指数退避重连、休眠唤醒、插拔网线自适应
- 静态参数可用系统读数一键填入（**仅当该网卡是手动配置时**，DHCP 一律不抄）
- 可按 MAC 自动认卡，也可手动指定网卡

**体验**
- 菜单栏常驻，状态一句话说清"现在是什么情况、你该做什么"
- 所有解释贴着对应那一行，不堆在底部；文案是人话，不走术语
- 启动看门狗：万一崩过一次，下次进安全模式（不自动连、不读密码），保证能进来改配置

**网络体检**（全部真实测量）
- 能不能上网：google / brave / duckduckgo / bing / baidu + 教务 / OA / 邮箱，逐层归因
- 出口 IP：Cloudflare / ipify / ifconfig.me 三源交叉，带国旗
- WebRTC：自实现 STUN，拿浏览器同款公网地址（UDP 被封时会明说"反而不会泄漏"）
- DNS 泄漏：反查解析出口；系统 DNS 被代理接管时如实说"比不出来"
- 人机验证：reCAPTCHA / 国内镜像 / Cloudflare Turnstile / CF 挑战页可达性
- IP 纯净度：ipinfo / ipapi / ipwho / BiliBili（+ 可选 IP2Location / MaxMind）交叉判断住宅 or 机房
- 带宽三档：直连 / 默认出口 / 本地代理（自动探测本地端口，无需手输）

**安全**
- JLU.WIFI 认证走系统浏览器，程序不接触明文密码，也不做任何 DOM 操作/自动填充
- 客户端预检只提示不拦截；是否放行由服务器裁定
- 卸载脚本会删掉 App、配置、日志与钥匙串条目，不留残留

## 三条工程铁律（开发用）

1. **施工机不做任何联网验证**：不认证、不抓校园网包。唯一允许的"联网"是对 `127.0.0.1` 的模拟网关。
2. **报文只能按 [docs/CHECKLIST.md](docs/CHECKLIST.md) 的偏移填**，不许自创字段；偏移与抓包不一致时以抓包为准，
   差异记在 [docs/progress.md](docs/progress.md) §4。
3. **先证伪环境，再怀疑凭据**：接口 / MAC / DHCP / 路由任何一项不对，都不发认证包。

## 快速开始

```bash
make test        # 119 条单元测试（编码器黄金向量 + 状态机 + 通道 + 探针/选路/网页认证/路由守卫）
make self-test        # 对 127.0.0.1 的模拟网关跑 challenge→login→保活 全流程
make portal-self-test # 对 127.0.0.1 的模拟门户跑 302→登录页→POST→204
make ci               # 上面三件 + 隐私扫描（与 GitHub Actions 一致）
make dump-login  # 离线打印 342 字节登录包，人工核对偏移
```

只读诊断（不改任何系统状态，随时可跑）：

```bash
swift run jlugate-probe --interfaces     # 网卡 / MAC / IPv4
swift run jlugate-probe --route-check    # 10.100.61.3 的出口是不是被 TUN 接管、ConfigMethod 是否 Manual
swift run jlugate-probe --detect         # 只判定走哪条链路（发 1 个 challenge，不认证；真机用）
swift run jlugate-probe --net-detail     # 网口/路由/DNS/VPN 快照 + 每个字段的白话解释
swift run jlugate-probe --ping           # 网关/公网延迟（直连 vs 默认出口含 VPN）
swift run jlugate-probe --speed          # 下载测速（直连 vs VPN）
```

## 真机（只能在有线 Mac 上做）

```bash
make release-probe        # universal 二进制
./.build/apple/Products/Release/jlugate-probe --login \
    --account <学号> --password <密码> --mac <登记MAC> --seconds 60
```

判定标准：**能登录、能撑 10 分钟不掉线**。回传终端输出 + `tcpdump -i en7 -n "udp port 61440"` 的抓包。

## 目录

| 路径 | 内容 |
|---|---|
| `Sources/JLUGateCore` | 编解码 / 摘要 / 状态 / 退避 / 错误（纯协议，无 I/O） |
| `Sources/JLUGateNet` | BSD 与 NW 两套 UDP 通道、网卡与路由解析、`DrcomEngine` actor |
| `Sources/jlugate-probe` | 诊断 + 离线自测 CLI |
| `App/` | SwiftUI 菜单栏应用（XcodeGen 工程描述在 `App/project.yml`） |
| `Tools/mock-gateway` | 按帧表应答的 Dr.Com 模拟网关（支持丢包/延迟/拒绝） |
| `Tools/mock-portal` | 模拟校园网页认证（302 → 登录页 → POST → 204） |
| `Fixtures/` | 抓包样本（含凭据摘要，**不要公开**） |
| `docs/` | CHECKLIST / PLAN / protocol-findings / progress / runbook |

## 生成 / 运行 App

没有开发者账号也能在本机跑起来（ad-hoc 签名，不能分发、不能公证）：

```bash
make app-bundle     # → dist/JLU Gate.app（LSUIElement，菜单栏常驻）
open "dist/JLU Gate.app"
```

有账号、要签名和公证时走 XcodeGen：

```bash
brew install xcodegen
cd App && xcodegen generate && open JLUGate.xcodeproj
```

## 隐私

- 仓库里的 `Fixtures/` 已**全部脱敏**（合成账号、保留地址、重算摘要），可公开。
- 真实凭据与原始抓包只放在 `local/PRIVATE.md`：**被 `.gitignore` 排除**，且
  `.git/hooks/pre-commit` 会拦截误提交。详见 [SECURITY.md](SECURITY.md)。
- 任何 `*.pcap` / `*.har` 都不入库。
- 推送前跑 `./scripts/privacy-scan.sh`；发布流程见 [docs/PUBLISH.md](docs/PUBLISH.md)。

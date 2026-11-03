# JLU Gate

macOS 26 的校园网认证客户端（Dr.Com UDP + 菜单栏常驻 + Liquid Glass）。
本仓库按 [docs/CHECKLIST.md](docs/CHECKLIST.md) 施工，协议细节全部来自真实抓包。

## 三条铁律（先读）

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

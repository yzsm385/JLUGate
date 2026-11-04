# 连接路径冻结（2026-11-04 起）

登录/连接这一条链路已经验证可用。从 0.3.6 起，**这一部分代码冻结**。

## 受保护的文件

- `Sources/JLUGateNet/DrcomEngine.swift`
- `Sources/JLUGateNet/AuthCoordinator.swift`
- `Sources/JLUGateNet/DatagramChannel.swift`
- `Sources/JLUGateNet/BSDChannel.swift`
- `Sources/JLUGateNet/NWChannel.swift`
- `Sources/JLUGateNet/InterfaceResolver.swift`
- `Sources/JLUGateCore/DrcomCodec.swift`
- `Sources/JLUGateCore/PacketLayout.swift`
- `Sources/JLUGateCore/DrcomPacket.swift`
- `Sources/JLUGateCore/MD5.swift`

## 规则

1. **界面、文案、站点、学院、体检**等改动，不得顺手动上面的文件；
2. 确实需要改连接时：
   - 单独一个提交，提交信息以 `[CONN]` 开头；
   - 必须同时更新 `docs/connection-freeze.sha256`（表示"我知道自己在动连接"）；
   - 必须跑 `make ci`，并附上真机验证结果；
3. `make ci` 会自动执行 `scripts/connection-guard.sh`：
   受保护文件与冻结哈希不一致、而冻结清单没更新时，直接失败。

## 已确认的故障模式（写下来避免重犯）

| 症状 | 真因 |
|---|---|
| 一直 `ldap auth error` / `0x15` | 启动时把**旧密码**读进内存，connect() 当成"本次输入"；旧密码从未成功过 |
| 更新后突然连不上 | 配置解码失败被静默丢弃，账号/网关变空 |
| 自动模式选了无线 | 选口被"强制有线/旧锁定"等规则干扰 |

修复时间线见 `docs/releases/v0.3.5.md`、`v0.3.6.md`。

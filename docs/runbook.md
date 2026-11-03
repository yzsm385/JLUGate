# 真机操作手册（环境 B）

> 环境 A（施工机）只做编译、单测、`127.0.0.1` 模拟网关/模拟门户。
> 这份手册假设你坐在**那台有校园网的有线 Mac** 前，且它正被官方客户端占着。
> 配套：[progress.md](progress.md)（实现状态）、[CHECKLIST.md](CHECKLIST.md)（协议）。

---

## 0. 准备

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

1. 连上 `JLU.WIFI`；
2. `./jlugate-probe --detect` 应显示"被拦截 → 应走 JLU.WIFI"；
3. App 版会弹 `WKWebView` 登录窗（命令行版没有浏览器，只能验证探测与状态机）；
4. 首次要人工输入一次，之后靠 Cookie 静默恢复。

想省掉向导里的手填：把表单字段名（`username` / `password` 之类）和入口 URL 记下来，填进设置页的"网页认证入口 URL"。

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

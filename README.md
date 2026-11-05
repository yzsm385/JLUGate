<a id="top"></a>
# JLU Gate 🛡️

<p>
  <a href="#top">🌐 中文</a> ·
  <a href="#english">🇬🇧 English</a>
</p>

> 📌 吉林大学校园网的 macOS 菜单栏小工具。

在吉大用 Mac 上网，有点像进了一栋有三个门、却只发一张卡的大楼 🏢：宿舍网线走 Dr.Com，JLU.PC 也走 Dr.Com，JLU.WIFI 又得开浏览器点网页认证——三个入口，账号密码却是同一套。每次换网络都得重新刷一遍卡；真断网了，对着一句冷冰冰的"未连接"干瞪眼 🫠，分不清是学校的事、DNS 的事，还是自己开的代理在捣乱。

JLU Gate 想把这三个门并成一个闸口 🚪✨。账号密码填一次，三种接入共用；该走哪条路它自己认，掉了线替你悄悄重连 🔁。顺手把教务、OA、邮箱、WebVPN 这些散落各处的入口也拢到一处，点一下就开 🔗；再配一套网络体检 🩺，断网时一层一层替你查到底卡在哪、出口那扇门后面干不干净。

> 🎯 只在校园网环境里有意义；主包跑在 macOS 26 及以上（Liquid Glass 界面），老系统（macOS 14/15）用 Compat 包。

---

## 📥 下载与安装

1. 去 [Releases](https://github.com/yzsm385/JLUGate/releases) 下最新版的 **ZIP** 📦：
   - **macOS 26 及以上** → 下主包 `JLU Gate x.x.x.zip`（Liquid Glass 界面 ✨）；
   - **macOS 14 / 15** → 下 `JLU Gate x.x.x (Compat).zip`（普通材质，功能一样，不会崩 🛠️）。
   - 两个包同名同 bundle id，**别同时装** ⚠️——启动守卫会把同 id 的旧进程顶掉。
2. 解压后，把里面的 **JLU Gate.app** 拖进「应用程序」 📁。
3. 第一次打开，系统会拦一下，提示"无法验证开发者"或"没认证" 🚧——因为这个程序没有 Apple 开发者签名。别慌，按下面走：
   - 打开「系统设置 → 隐私与安全性」，一直拉到最底下 ⬇️；
   - 会看到一行"已阻止使用 JLU Gate"，旁边有个「仍要打开」按钮，点它 👆；
   - 输你的开机密码确认 🔐；
   - 再回去打开 App，这次就能进了 ✅。

> 💡 这个"没认证"不是程序有问题，纯粹是我没买 Apple 开发者账号（¥688/年）；放行一次之后，往后打开都不会再问。

### 🔄 自动更新：从 1.0.0 才开始有

| 你手上的版本 | 能不能自动更新 |
|---|---|
| 0.1.x / 0.2.0 / 0.2.1 | ❌ 不能，连「检查更新」都没有 |
| 0.2.2 – 0.3.17 | 🟡 只能「检查更新 + 打开下载链接」，替换还得手动拖 |
| **1.0.0** | ✅ 第一个带一键更新的正式版 |
| **1.0.1 及以后** | ✅ 一键更新，还会自动挑对包、装完清理安装包 |

⚠️ 两个坑先说清楚：

- **macOS 14 / 15 的同学**：1.0.0 的适配包是按 macOS 26 编译的，在 14/15 上根本打不开（会提示"不能与此版本的 macOS 配合使用"）。所以旧系统要**手动装一次 1.0.1（或更新）的 Compat 包**，从那以后才能用面板上的「更新」自动升级。
- **macOS 26 的同学**：1.0.0 可以一键更新，但旧更新器拿到的是 Release 里排第一的 Compat 包（没有 Liquid Glass）。想要新界面，手动下最新主包（`JLU-Gate-vx.y.z.zip` 或 `.dmg`）。

装好 1.0.1 之后，更新只需要一步：面板上点「更新」→ 自动查最新 → 下载 → 退出替换 → 重新打开，安装包会自动删掉，不占空间。

---

## 🎓 新生 / 第一次用：先查这三样

**固定 IP、网关、登记 MAC** 不用猜，学校自助平台里都有，但**不在同一个地方**（只有**有线 / JLU.PC** 需要这些；
**JLU.WIFI 一个都不用填**——它本质是 HTTP 网页认证，地址由 DHCP 动态分配）：

> ⚠️ **认准名字**：学校的无线只有 `JLU.WIFI` 和 `JLU.PC` 两个，名字要一模一样（大写、中间是一个点）。
> 有人会开同名热点伪装成学校网络——在可疑网络里别输账号密码。

1. 打开 [校园网自助平台](https://ip.jlu.edu.cn/pay)，用**校园卡号**（录取通知书上那串，如 `20220501324`）＋ **6 位数字密码**（吉大 V 卡密码）＋ 验证码登录；
2. 点「**查询信息**」：IP、网关、DNS 都在这儿——**但这里没有 MAC**；
3. 登记 MAC 走另一个入口：点「**变更 MAC**」进去看 / 改；
4. 列表里没有你的设备 → 回主菜单点「**网络开户**」，按提示开通后再回来查。

🖥️ **自己这台 Mac 的 MAC 在哪看**（要的是网卡的物理地址）：

- **有线网卡**：系统设置 → 网络 → 点那根有线（USB 网卡也在这）→ 详细信息 → MAC 地址；
- **Wi-Fi**：系统设置 → Wi-Fi → 点已加入的网（JLU.WIFI / JLU.PC）旁的「⋯」→ MAC。

> 系统若开着「私有 Wi-Fi 地址 / 随机 MAC」，先关掉它，或者在 App 里勾「用登记的 MAC 认证」。

⚠️ 三套密码别弄混（自助平台和本 App 用的不是同一套）：

| 哪一套 | 账号 | 密码 / 用在哪 |
|---|---|---|
| 吉大 V 卡（校园卡） | 录取通知书号，如 `20220501324` | **6 位数字**；自助平台查 IP、校园卡业务 |
| 吉大邮箱 | 与统一账号同格式 | 独立的一套密码，**只**用来登邮箱 |
| 统一身份认证 | 学号 / 邮箱前缀 | 教务、VPN、**本 App 登录校园网**用的就是这套 |

💰 **连不上也可能是欠费**：余额 **-10 元、0 元都还能正常上**；一旦到 **-20 元**就断（有线 / JLU.PC / JLU.WIFI 都一样）。
充值档位只有 **20 / 40 / 100**，钱从校园卡余额里扣——欠 20 的时候充 20（变成 0）不算数，
要充 **40**（余额变成 +20）才能用。

> App 的「设置」页顶部、向导的账号与网络参数两步，都放了这张「不会填？去自助平台查」的卡片，点一下就能打开；
> 选成 JLU.WIFI 时它会自动换成"不用填 IP / MAC"的说法。

---

## 🤔 它解决了什么

下面这些是写这个程序时真实撞上、想顺手抹平的坎：

- 🗝️ **三个门却只发一张卡。** 卡填一次，三处通用；存进钥匙串，往后不用再掏。
- 👥 **JLU.WIFI 只认 3 台设备，被新来的挤下去时悄无声息。** 掉线时它会告诉你"多半是被挤了"，并说清重新登入会顶掉队尾那一台（没准正是你自己的另一台机器）。
- 🪪 **学校认网卡，系统却爱给网卡换脸。** 它读的是出厂那张"原貌"去认证，三个值——当前、出厂、登记——并排摆出来，一眼对得上。
- 🛤️ **代理开了条岔路，认证包走着走着被拐走。** 实测"直连 vs 经代理"两条路差多远，拿数据替你拿主意该不该给校园网段改规则。
- 🕵️ **断了网，分不清该找谁。** 一站一站掀开看（DNS → TCP → TLS → HTTP），给出结论和下一步，而不是丢一句"网络错误"了事。
- 🌍 **代理 IP 被重点盯上，却不知为何。** 多个来源交叉比对是住宅还是机房，DNS 出口和 IP 出口是不是同一个国家，都讲明白。

---

## ⚙️ 能做什么

按板块分一下，每块管一类事、解决一类别处没解的麻烦：

| 板块 | 这块在干什么 | 具体能力 |
|---|---|---|
| 🌐 **三网接入** | 大楼那三个门，一把钥匙开三把锁；认得该走哪扇，掉了链子自己接上 | 自动认该走哪条路（发一个 challenge 判定，不是校园网就一个包都不发）；10 秒保活、掉线指数退避重连、休眠唤醒自动恢复、插拔网线自适应；按 MAC 自动认网卡或手动指定 |
| 🔧 **参数与 MAC** | 学校凭网卡认人，系统偏又爱给网卡换"面具"——这块专门撕下面具、对上身份证 | 读出厂 MAC 去认证，界面上并排显示当前 / 出厂 / 登记三个值；静态参数能用系统读数一键填（**仅当网卡是手动配置时**，DHCP 一律不抄） |
| 🔖 **吉大常用入口** | 校园里那些东一个西一个的牌子，收进同一个橱窗，伸手就能够到 | 14 个站点分五类摆好，每个标「仅校内 / 需 VPN / 公网」；能搜（标题 / 域名 / 用途）；点开用系统浏览器，支持登录的顺手复制账号；「复制密码」60 秒后自动清空剪贴板；「我的学院」填学号认学院，44 个学院可搜、一键开官网；「校园网门户 / 今日广告」给按钮直接开、不自动弹 |
| 🩺 **网络体检** | 断网时不让你对着黑箱猜，一层层掀开看：是路断了、门关了，还是屋里没人在 | 能不能上网：google / brave / duckduckgo / bing / 百度 + 教务 / OA / 邮箱逐站归因；出口 IP 三源交叉（Cloudflare / ipify / ifconfig.me）带国旗；自实现 STUN 拿浏览器同款 WebRTC 公网地址；DNS 泄漏反查解析出口；人机验证可达性（reCAPTCHA / 国内镜像 / Turnstile / CF 挑战页）；IP 纯净度多源交叉判住宅 or 机房；带宽三档（直连 / 默认出口 / 本地代理，端口自动探测） |
| 🛤️ **代理与路由** | 你开的代理像条岔路，认证包可能走着走着就被拐走了；这块帮你量清楚两条路差多远 | 实测"认证通道延迟：直连 vs 经代理"；路由出口是不是被 TUN 接管、ConfigMethod 是不是 Manual，都直接给结论 |
| 🖥️ **界面与状态** | 不跟你拽术语，像旁边站了个懂行的人，指着那一行告诉你"现在这样、下一步该干嘛" | 菜单栏常驻不占 Dock；文案说人话少用术语；启动看门狗——崩过一次就进安全模式（不自动连、不读密码），保证能进来改配置 |
| 🔄 **更新与卸载** | 来了就走、走了不留痕 | 设置里检查更新，有新版自己下载 → 退出 → 替换 → 重开，不用手动覆盖；卸载脚本删掉 App、配置、日志和钥匙串条目 |
| 🔒 **安全上的克制** | 该它管的它管，不该它碰的一根手指都不伸 | JLU.WIFI 走系统浏览器，程序不碰明文密码、不做 DOM 操作或自动填充；预检只提示不拦截，放不放行由学校服务器定 |

---

## 🤝 参与贡献

这个工具是一个人照着自己在吉大撞过的坑写的，**覆盖面肯定不全** 🫠。下面这几块是最容易补、也最希望同学们帮忙的地方——不用会写 Swift，会认字、会上网就行。

### 🎓 我的学院没收进去 / 学号认不出学院

学院目录在 [Sources/JLUGateCore/CollegeDirectory.swift](Sources/JLUGateCore/CollegeDirectory.swift)，目前收了官网「院系设置」页列出的 **44 个学院**。如果你发现：

- 🏫 你的学院不在这份名单里（比如新成立的、或者独立学院/研究院/中心也想收进来）；
- 🆔 填了学号却认不出学院——吉大**没有公开的"学号前缀 → 学院"对照表**，现在的做法是"你选一次、本机记住同前缀"，所以**只有你一个人用的时候它学得会，换个人就又得重选**。

能怎么帮：
- 💬 在 [Issues](https://github.com/yzsm385/JLUGate/issues) 开一条，写明「学院名 + 官网域名 +（如果知道的话）学号前缀」，我加进目录；
- 🛠️ 或者直接 PR 改 `CollegeDirectory.all`，照着现有格式加一行 `College(name:host:)` 就行。

### 🔗 想把某个常用网站收进合集

站点合集在 [Sources/JLUGateCore/JLUSiteDirectory.swift](Sources/JLUGateCore/JLUSiteDirectory.swift)，目前 **14 个**（教务 / OA / 邮箱 / WebVPN / 校园网自助 / 官网新闻）。如果你每次都得去收藏夹翻的入口不在里面——比如你学院的教务系统、某个办事流程页、某个实验室/课题组的站点、图书馆某个常用数据库入口：

- 💬 开 Issue 说「网站名 + 域名 + 是仅校内 / 需 VPN / 公网 + 一句话用途」；
- 🛠️ 直接 PR 也行，照 `JLUSite` 的字段加一条，`category` 选已有的五类之一，`access` 选 `公网 / 仅校内 / 需 VPN` 三个之一。

### ✨ 其他想补的

- 🩺 **体检站点**：[Sources/JLUGateNet/ReachabilityService.swift](Sources/JLUGateNet/ReachabilityService.swift) 里"能不能上网"探的站点是 google / brave / duckduckgo / bing / 百度 + 教务 / OA / 邮箱，想加别的探针也欢迎；
- 💻 **真机验证**：作者只有一台插校园网线的 Mac，别的机型 / 别的校区（朝阳 / 南湖 / 和平 / 南岭 / 新民 / 南部）的网络环境没试过，反馈真实环境的掉线日志和 `tcpdump` 抓包（**记得脱敏**）很有价值；
- ✍️ **文案**：界面上哪句"人话"没说人话、哪段注解看不懂，直接开 Issue 说该怎么说。

> ⚠️ 不收任何真实凭据。Issue / PR 里**别贴明文密码、别贴原始抓包**；脱敏规则见 [SECURITY.md](SECURITY.md) 和 [docs/CHECKLIST.md](docs/CHECKLIST.md)。

---

## 📚 更多文档

详细的开发者文档都搬到 [Wiki](https://github.com/yzsm385/JLUGate/wiki) 了（中英双语，每页顶部可切语言）：

| Wiki 页 | 内容 |
|---|---|
| [功能详解](https://github.com/yzsm385/JLUGate/wiki/Features) | 三网接入 / 参数与 MAC / 吉大入口 / 网络体检 / 代理路由 / 界面状态 / 更新卸载 / 安全克制，每块展开讲 |
| [快速开始](https://github.com/yzsm385/JLUGate/wiki/Quick-Start) | `make` 命令、`jlugate-probe` 只读诊断 |
| [构建与运行](https://github.com/yzsm385/JLUGate/wiki/Build) | 新版（macOS 26）/ 旧版适配（macOS 14）的构建、签名、打包 |
| [连接路径冻结](https://github.com/yzsm385/JLUGate/wiki/Freeze-Policy) | 哪些文件冻结了、为什么、怎么改才不违反 |
| [真机验证](https://github.com/yzsm385/JLUGate/wiki/Real-Device-Test) | 在真实校园网环境验证登录和保活的完整流程 |
| [隐私与安全](https://github.com/yzsm385/JLUGate/wiki/Privacy) | Fixtures 脱敏、凭据存放、隐私扫描、发布流程 |

> 📖 English versions of all Wiki pages are available—click **🇬🇧 English** at the top of any Wiki page.

---

<a id="english"></a>

## 🇬🇧 English

<details>
<summary><b>🌐 Click here for English</b></summary>

# JLU Gate 🛡️

> 📌 A macOS menu-bar tool for Jilin University's campus network.

Using a Mac on the JLU campus is a bit like entering a building with three doors but only one key card 🏢: dorm wired internet uses Dr.Com, JLU.PC also uses Dr.Com, and JLU.WIFI requires a browser-based web login—three entrances, one shared set of credentials. Every time you switch networks you re-authenticate; when the connection drops, you stare at a cold "not connected" message 🫠, unsure whether it's the school, DNS, or your own proxy causing trouble.

JLU Gate merges those three doors into one gateway 🚪✨. Enter credentials once, shared across all three access methods; it picks the right path automatically and quietly reconnects when dropped 🔁. It also gathers scattered entrances—academic system, OA, email, WebVPN—into one place, one click to open 🔗; plus a network health check 🩺 that walks you layer by layer through what's broken when you're offline.

> 🎯 Only meaningful in a campus-network context. The main build runs on macOS 26+ (Liquid Glass UI); older systems (macOS 14/15) use the Compat build.

---

### 📥 Download & Install

1. Grab the latest **ZIP** 📦 from [Releases](https://github.com/yzsm385/JLUGate/releases):
   - **macOS 26+** → main build `JLU Gate x.x.x.zip` (Liquid Glass UI ✨);
   - **macOS 14 / 15** → `JLU Gate x.x.x (Compat).zip` (plain material, same features, won't crash 🛠️).
   - Both share the same name and bundle id—**don't install both at once** ⚠️ (the launch guard kills the older process with the same id).
2. Unzip and drag **JLU Gate.app** into **Applications** 📁.
3. On first launch macOS will block it with an "unidentified developer" warning 🚧—because there's no Apple Developer signature. Don't panic:
   - Open **System Settings → Privacy & Security**, scroll to the bottom ⬇️;
   - Find the "JLU Gate was blocked" line, click **Open Anyway** 👆;
   - Enter your login password 🔐;
   - Launch the app again—it works now ✅.

> 💡 The "unverified" warning isn't a bug; I simply don't have an Apple Developer account (¥688/year). After allowing it once, it won't ask again.

Auto-update only exists from **1.0.0** onward:

| Your version | Auto-update? |
|---|---|
| 0.1.x / 0.2.0 / 0.2.1 | ❌ No—not even an update check |
| 0.2.2 – 0.3.17 | 🟡 Check + open the download link only; replacing is still manual |
| **1.0.0** | ✅ First release with one-click update |
| **1.0.1+** | ✅ One-click, picks the right build, and removes the downloaded package |

⚠️ Two caveats:

- **macOS 14 / 15**: the 1.0.0 Compat build was compiled against macOS 26 and won't launch on 14/15. Install the **1.0.1 (or newer) Compat** build once by hand; from then on, the in-app **Update** button works.
- **macOS 26**: 1.0.0 can update itself, but the old updater grabs the first ZIP in the release—the Compat build (no Liquid Glass). For the main build, download the latest `JLU-Gate-vx.y.z.zip` or `.dmg` manually.

Once you're on 1.0.1, updating is one click: **Update** in the panel → check → download → quit & replace → relaunch, and the downloaded package is removed automatically.

---

### ⚙️ What It Does

| Module | What it's for | Capabilities |
|---|---|---|
| 🌐 **Three-network access** | One key for all three doors; auto-picks the right one, reconnects on drops | Auto-detects the path (one challenge packet; sends nothing if off-campus); 10s keepalive, exponential-backoff reconnect, sleep/wake recovery, plug/unplug adapt; MAC-based NIC selection or manual |
| 🔧 **Parameters & MAC** | School auths by NIC, but the system keeps changing its "face"—this strips the mask | Authenticates with the factory MAC; shows current / factory / registered MAC side by side; one-click fill from system readings (**only when NIC is manually configured**, never from DHCP) |
| 🔖 **JLU quick links** | Scattered campus entrances gathered into one showcase | 14 sites in 5 categories, each tagged campus-only / VPN-needed / public; searchable (title / domain / use); opens in system browser; credential copy for logins; "copy password" auto-clears clipboard after 60s; "my college" recognizes college from student ID, 44 colleges searchable, one-click to official site |
| 🩺 **Network health check** | Don't guess at a black box—open it layer by layer: road broken, door closed, or no one home | Can-you-surf: google / brave / duckduckgo / bing / Baidu + academic / OA / mail per-site attribution; egress IP from 3 sources with flags; self-implemented STUN for WebRTC public IP; DNS-leak reverse lookup; captcha reachability; IP purity (residential vs datacenter); bandwidth tiers (direct / default / local proxy) |
| 🛤️ **Proxy & routing** | Your proxy is a detour that may hijack auth packets; this measures both paths | "Auth-channel latency: direct vs via proxy"; whether the route is TUN-hijacked or ConfigMethod is Manual—clear verdicts |
| 🖥️ **UI & status** | No jargon—like a savvy friend pointing at the line saying "here's where you are, here's what to do next" | Menu-bar resident, no Dock; plain-language copy; launch watchdog—crashes once → safe mode (no auto-connect, no password read) so you can still open settings |
| 🔄 **Update & uninstall** | Arrives cleanly, leaves cleanly | In-app update check: download → quit → replace → relaunch; uninstall script removes app, config, logs, keychain entries |
| 🔒 **Restraint** | It minds its own business and doesn't touch what it shouldn't | JLU.WIFI goes through the system browser; the app never handles plaintext passwords, no DOM ops or auto-fill; pre-checks only advise, never block—the server decides |

---

### 🤝 Contributing

This tool was written by one person based on their own JLU pain points, so **coverage is definitely incomplete** 🫠. The easiest ways to help—no Swift needed:

- 🎓 **College directory** ([CollegeDirectory.swift](Sources/JLUGateCore/CollegeDirectory.swift)): 44 colleges listed; if yours is missing or your student ID isn't recognized, open an [Issue](https://github.com/yzsm385/JLUGate/issues) with «college name + official domain + student-ID prefix (if known)».
- 🔗 **Site directory** ([JLUSiteDirectory.swift](Sources/JLUGateCore/JLUSiteDirectory.swift)): 14 sites; if a frequently-used entrance is missing, open an Issue with «site name + domain + campus-only/VPN/public + one-line purpose».
- 🩺 **Health-check probes**, 💻 **real-device verification** (other Mac models / campuses), ✍️ **copy feedback**—all welcome.

> ⚠️ No real credentials accepted. Don't paste plaintext passwords or raw captures in Issues/PRs; see [SECURITY.md](SECURITY.md) for redaction rules.

> 📖 Full developer docs (build, tests, freeze policy, real-device testing, privacy) are in the [Wiki](https://github.com/yzsm385/JLUGate/wiki)—English versions available, click **🇬🇧 English** at the top of any Wiki page.

</details>

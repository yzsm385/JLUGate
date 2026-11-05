# 课表 × 日程：JLU Gate 集成方案（讨论稿 v0.1）

> **状态**：方案讨论稿，尚未写代码。本文只回答三件事：**能不能做、做成什么样、怎么一步步做**。
> **结论先行**：能做，而且吉大的条件比大多数学校好——课表有**整学期一次返回的 JSON 接口**，不用去啃 HTML 表格。真正难的只有三处：① 本 App 历史上有 WKWebView 崩溃记录；② 登录态/证书/代理路径；③ 重新同步时**不能覆盖用户手改过的内容**。
> **最后更新**：2026-11-05

---

## 0. 30 秒版

| 问题 | 结论 |
|---|---|
| 能不能记住课表地址，直接进？ | 能。`https://iedu.jlu.edu.cn/jwapp/sys/wdkb/*default/index.do#/xskcb` 存为默认入口，登录态用 Cookie 记住 |
| 未登录会不会自动跳登录页？ | 会。CAS（`cas.jlu.edu.cn/tpass/login`）接管，登录后回跳；我们把 `#/xskcb` 补回去，直接落在课表 |
| 登录后能不能自动导入？ | 能。页面自己会请求 `cxxszhxqkb.do`，我们在 WebView 里挂个钩子把响应截下来；也可以直接用 Cookie 走原生请求 |
| 能不能改了再改（纠正）？ | 能。课表以「节次」为坐标存，时间由「作息表」换算；格子可拖、可拉长、可改周次；另有「本周临时调课」层 |
| 能不能再加活动？ | 能。活动和课程是两套模型，共用网格，可重复、可提醒、可导出 ICS |
| 能不能反复更新？ | 能。按学期归档，重新同步走**三方合并**：学校改的更新，你改的保留，两边都改的让你选 |
| 能不能存好几个学期？ | 能。本地是一个「档案」，里面 N 个学期；当前学期自动识别，历史学期只增不删 |
| 规则模式下能不能用？ | 能，但要先做一次**预检**：`jlu.edu.cn` / `10.0.0.0/8` 有没有被代理吞掉。吞掉了就给你一条可复制的 DIRECT 规则 |
| 最大风险是什么？ | WKWebView 在这个 App 里崩过。**M0 先花 1–2 天专门验证**，崩就退到「原生 CAS + 粘贴兜底」 |

### 0.1 先说难听的：值不值得做

- **如果只想"在 Mac 上看课表"**，现成的 [JLU_schedule](https://github.com/JFyuhong/JLU_schedule) 的 iOS/PWA 版、手机上的 WakeUp 都能用，没必要重造。
- **JLU Gate 做这件事的增量**只有四点：① 登录态和校园网在同一个 App，不用先开浏览器；② 入口就在菜单栏，和"连没连校园网"联动；③ 能做"下一节课/上课提醒"这种贴着菜单栏的提醒；④ 课表能和网络体检/站点合集放在一个地方。
- **代价**：一个新子系统（约 20 人日）+ 一条长期维护面（教务一改版就得跟）。
- **折中方案**：先做 **M1+M2（只读 + 导入 + 同步）**，编辑/活动看使用频率再加；或者干脆只做"导出 ICS 给系统日历"，一天就能收工。本文按"完整做"来写，但里程碑是可裁剪的。

---

## 1. 需求转写

把聊天里的要求拆成可验收的用户故事（U1–U10），后面每一节都对着它们做。

| # | 用户故事 | 验收标准 |
|---|---|---|
| U1 | 我记得课表地址，不想每次从教务首页点进去 | 首次填一次 URL，之后「课表」入口一键直达；URL 可改、可恢复默认 |
| U2 | 没登录时它自己跳登录页，登录完直接看到课表 | 打开 → CAS → 登录 → 回跳 → 自动补 `#/xskcb` → 课表渲染完成，全程不用再点 |
| U3 | 看到课表后，能把课表导进来 | 页面上出现「导入本学期（32 门）」；点一下进预览，确认后落库 |
| U4 | 导进来只是起点，时间/格子/周次都能改 | 网格里点、拖、拉、右键都能改；改完立刻生效并持久化 |
| U5 | 颜色要好看、稳定，不要每次导入都变 | 同一门课跨学期同色；深浅色两套；可手动改色；改完不被同步覆盖 |
| U6 | 除了课，还要能加活动（社团、实验、约会…） | 可建一次性/每周重复的活动，显示在同一个网格和「今天」列表里，可设提醒 |
| U7 | 课表会变（调课、停课、补课），要能再同步 | 「同步」按钮 → diff 预览 → 应用；手工改动不被覆盖；可撤销 |
| U8 | 好几个学期的课表都要留着 | 学期列表可切换/重命名/删除；新学期自动建；旧学期不因同步消失 |
| U9 | 开着代理（规则模式）时也能用 | 预检通过才发请求；失败时给出「加 DIRECT 规则 / 先连校园网 / 用 WebVPN」的可执行建议 |
| U10 | 出问题别只报「网络错误」 | 分阶段状态：未登录 / 登录过期 / 不是校园网 / 代理接管 / 证书不受信 / 接口变了，各有各的说法和下一步 |

**非目标（明确不做）**：抢课、查成绩/考试（后续可复用同一会话）、自动提交表单、绕过验证码、后台定时爬取、上传课表到任何服务器。

---

## 2. 现有工程的约束（必须先承认）

这些不是"注意事项"，是设计输入。绕开它们会返工。

| 约束 | 出处 | 对本功能的影响 |
|---|---|---|
| 所有界面都在 **380pt 宽的菜单栏 popover** 里，且**故意不开窗口** | `App/Sources/JLUGateApp.swift`、`MenuContent.swift` 注释 | 完整课表/编辑必须另开窗口，或做成"面板看、窗口改" |
| **WKWebView 在这个 App 里崩过**（AppKit display cycle → SIGABRT） | `WKPortalBrowser.swift`、`PortalViewerView.swift` 注释 | 登录页不能直接塞进 popover；必须独立窗口 + 生命周期正确，且要有降级路径 |
| 决策 D-001：**不做表单重放、不做 DOM 操作/自动填充** | `WKPortalBrowser.swift` | 网页里默认不代填账号密码；「帮填」只能是显式开关 |
| `JLUGateCore` **不得 import 网络框架**，必须能离线 `swift test` | `docs/PLAN.md` §0 | 解析/合并/周次计算放纯逻辑层，网络单独放 |
| DrCOM 连接链路冻结（10 个文件） | `docs/connection-freeze.md` | 新增文件不受限，但**一个字节都不能顺手动**那几个文件 |
| 无第三方依赖（SwiftPM 无 dependencies） | `Package.swift` | WebView、JSON、ICS、颜色全部原生实现 |
| 文案三语（简/繁/英），且 `CopyTests` 写死了 **711 条** | `Sources/JLUGateCore/CopyTable-*.swift`、`Tests/.../CopyTests.swift` | 新增文案要同步三张表 + 改测试里的数字 |
| 隐私扫描禁止真实 MAC/IP/学号入库 | `scripts/privacy-scan.sh` | 测试夹具只能用合成数据；真实响应**绝不入库** |
| 配置走 0600 文件 / Keychain 双后端 | `FilePrivacy.swift`、`CredentialStore.swift` | 课表与 Cookie 沿用同一套 |
| `App/` 与 `App-Compat/` 是**两份物理源码** | `App-Compat/Sources` | 每个新 View 要放两遍（逻辑尽量下沉到 Core/Schedule，UI 重复才可控） |

**推论**：课表是"第二个产品面"，不要塞进 DrCOM 状态机，也不要塞进 `AppConfig`。它应该是**独立子系统 + 独立存储 + 独立 target**。

---

## 3. 外部调研：别人怎么做的

### 3.1 同类实现对比

| 方案 | 形态 | 导入方式 | 值得借鉴 | 不足/教训 |
|---|---|---|---|---|
| [JLU_schedule](https://github.com/JFyuhong/JLU_schedule)（吉大，开源，GPL-3.0） | Android + iOS + 鸿蒙 + PWA | ① 内嵌 WebView 登录后**捕获页面自身的 XHR 响应**；② 原生 CAS(TPASS) + 原生二跳接口；③ Cookie 在 WebView ↔ 原生之间双向迁移 | 把吉大的接口链、字段名、周次表达式、节次表全踩过一遍；"捕获"比"猜参数"稳；多课表 + 备份 + 小组件 | 它的默认节次时间**和学校官方表不一致**（少了课间），说明"内置时间必须可改"；GPL 代码不能直接抄进 MIT 项目 |
| [AiScheduleForNewJLU](https://github.com/Temsys-Shen/AiScheduleForNewJLU) | 小爱课程表适配脚本 | DOM/JSON 解析 | 证明"新教务"的课表页结构可解析 | 页面一改就废；只做一次性导入 |
| [jlu-mobile-schedule](https://github.com/con9uer666/jlu-mobile-schedule) | Flutter 多端 | 教务导入 + 手动 | 调课、提醒、学习事项、桌面小组件的产品形态 | 功能参考，不是架构参考 |
| [ClassIsland](https://www.classisland.tech/) | Windows 桌面 | 拖入 ICS/课表文件、手动 | **课表 / 时间表 / 科目 三层模型**；时间表可复用；调课是独立概念 | 面向教室大屏，交互偏重 |
| WakeUp / 超级课程表 / 星链 | 手机 App | 教务适配、分享码、ICS/JSON | 周视图、配色、多课表、桌面小组件；生态里 ICS/JSON 是事实标准 | 闭源，规则由社区维护 |
| 强智系高校脚本（如 [classCrawl](https://github.com/inannan423/classCrawl)） | 脚本 | 直接调 `app.do?method=...` JSON | 说明"能拿 JSON 就别解析 HTML"是普遍经验 | 强智 ≠ 吉大用的这套，仅作方法论参考 |

> 许可证提醒：`JLU_schedule` 是 **GPL-3.0**，本仓库是 **MIT**。可以读它的**行为与接口事实**（协议、字段名属互操作性事实），**不要复制代码/注释/资源**。真要移植解析器，先决定整个项目的许可证。

### 3.2 三条被反复验证的经验

1. **优先 JSON 接口，其次响应捕获，最后才是 HTML 解析。** 吉大这套正好是第一种。
2. **登录只负责产出 Cookie。** 把"怎么拿到登录态"和"怎么解析课表"彻底解耦，换登录方式不影响解析。
3. **一次性导入的产品都活不久。** 课表会变（调课/停课/补课/重修），必须有"再同步 + 合并"。

### 3.3 反向清单（不要学）

- ❌ 把账号密码塞进网页自动提交（验证码/风控一改就死，也有安全争议）
- ❌ 后台常驻轮询教务（无意义、易被封、耗电）
- ❌ 把课表传到云端做"多端同步"（本工具定位是本地优先）
- ❌ 用 HTML 表格当唯一数据源（页面改版必炸）

---

## 4. 吉大教务的真实链路

> 标记：✅ 已从公开页面/开源实现确认；⚠️ 逻辑成立但未在吉大真机验证；❓ 完全未知。

### 4.1 地址与请求链

| 用途 | 地址 | 状态 |
|---|---|---|
| 课表页（你给的） | `https://iedu.jlu.edu.cn/jwapp/sys/wdkb/*default/index.do#/xskcb` | ✅ |
| 教务门户 | `https://iedu.jlu.edu.cn/jwapp/sys/emaphome/portal/index.do` | ✅ |
| 统一认证 | `https://cas.jlu.edu.cn/tpass/login?service=<urlencoded 门户>` | ✅ |
| 当前学期 | `POST .../wdkb/modules/jshkcb/dqxnxq.do`（空表单） | ⚠️ |
| 整学期课表 | `POST .../wdkb/modules/xskcb/cxxszhxqkb.do`，body `XNXQDM=<学期码>` | ⚠️ |

发请求时要带的三样东西（缺一个就可能被网关拦）：

```
Referer: https://iedu.jlu.edu.cn/jwapp/sys/wdkb/*default/index.do
X-Requested-With: XMLHttpRequest
User-Agent: <和 WebView 里一致的浏览器 UA>
```

**关键点**：`#/xskcb` 是前端路由，**不会发给服务器**。所以 CAS 的 `service` 参数里带不带它都行；登录回跳后由我们补一句 `location.hash = '#/xskcb'`，就落在课表页。这正好实现你要的"登录后直接显示课表"。

### 4.2 返回结构

顶层是 `datas` → 若干张表 → 每张表 `rows`。课表在 `xskcb` 那张表里。

```json
{
  "datas": {
    "xskcb": {
      "rows": [
        {
          "KCM": "数据结构",
          "SKJS": "张三",
          "YPSJDD": "1-16周 星期一 第1-2节 逸夫楼101",
          "ZCMC": "1-16周",
          "SKXQ": "1",
          "KSJC": "1",
          "JSJC": "2",
          "JASMC": "逸夫楼101",
          "JXLDM_DISPLAY": "逸夫楼",
          "XNXQDM": "2025-2026-1",
          "XNXQDM_DISPLAY": "2025-2026学年第一学期",
          "XF": "3.0"
        }
      ]
    }
  }
}
```

| 字段 | 含义 | 我们的用法 |
|---|---|---|
| `KCM` | 课程名 | 身份键 + 显示 |
| `SKJS` | 教师 | 显示、身份键 |
| `YPSJDD` | 安排时间地点（可能是多段拼接） | **主解析源** |
| `ZCMC` | 周次文本 | 兜底 / 校对 |
| `SKXQ` / `KSJC` / `JSJC` | 星期数字 / 起止节 | 兜底（`YPSJDD` 解析失败时） |
| `JASMC` / `JXLDM_DISPLAY` | 教室 / 教学楼 | 显示 |
| `XNXQDM(_DISPLAY)` | 学期码 / 学期名 | **归档依据** |
| `XF` | 学分 | 可选显示 |

> ⚠️ 以上字段来自开源实现的行为记录，不是吉大官方文档；真机抓一次即可确认（附录 A）。

### 4.3 周次与节次

周次表达式至少这几种形态，解析器必须全覆盖，认不出的**原样保留 + 标黄**，不能猜：

```
1-16周            1-16周(单)        1,3,5,7周
2-8周,10-16周     1-4周,6-9周,11-16周      待定
```

节次时间用学校官方表（2023–2024 学年第二学期起执行，[本科生院](http://jwc.jlu.edu.cn/sksj.htm)）：

| 节 | 时间 | 节 | 时间 |
|---|---|---|---|
| 1 | 08:00–08:45 | 7 | 15:30–16:15 |
| 2 | 08:55–09:40 | 8 | 16:25–17:10 |
| 3 | 10:00–10:45 | 9 | 18:20–19:05 |
| 4 | 10:55–11:40 | 10 | 19:05–19:50 |
| 5 | 13:30–14:15 | 11 | 20:00–20:45 |
| 6 | 14:25–15:10 | 12 | 20:45–21:30 |

注意：晚上 9、10 节**之间不休息**；下午 5、6 节之间 10 分钟。这类细节必须能改（见 §9.4），因为不同校区/季节可能不一样。

### 4.4 三条获取路径（A + B 都要，C 兜底）

| 路径 | 做法 | 优点 | 缺点 | 用在哪 |
|---|---|---|---|---|
| **A. 页面捕获** | WebView 里注入脚本，包 `fetch`/`XMLHttpRequest`，命中 `cxxszhxqkb.do` 就把响应体 `postMessage` 给原生 | 不用猜参数、不用管学期码；用户看到的和拿到的必然一致 | 依赖 WebView 稳定；页面若改用别的传输方式要跟进 | **首次导入 / 登录后自动导入** |
| **B. 原生二跳** | 用 A 拿到的 Cookie，直接 `URLSession`：激活 `wdkb` → `dqxnxq` → `cxxszhxqkb` | 快（<1s）、无 UI、可后台刷新 | 需要 Cookie 有效；参数/UA 要跟页面一致 | **日常「同步」按钮 / 自动检查更新** |
| **C. 兜底** | 粘贴 JSON、导入 `.ics`、纯手动录入 | 永不失效；换学校也能用 | 麻烦 | 接口改版 / 非校园网 / 调试 |

> 设计上把三者都收敛成同一个产物：`ImportedSemester`。后面所有逻辑（解析、diff、合并）只认这个结构。

### 4.5 待真机验证（M0 的一部分）

| # | 未知 | 怎么验 | 影响 |
|---|---|---|---|
| V1 | `cxxszhxqkb.do` 到底是 POST 还是 GET、参数名大小写 | DevTools 抓一次 | 决定 B 路径 |
| V2 | 一次返回是否包含**全部周次**（不是只本周） | 看行数与 `YPSJDD` | 决定要不要按周循环拉 |
| V3 | 传历史 `XNXQDM` 能不能拉到往期学期 | 改参数试 | 决定"补拉历史学期"能否做 |
| V4 | CAS 是否弹图形验证码/二次验证 | 无痕窗口登录一次 | 决定"静默重登"可行性 |
| V5 | `iedu` 证书是否被 macOS 信任 | `openssl s_client` / 浏览器看锁 | 决定要不要做 TOFU 信任 |
| V6 | WebVPN 下的课表 URL 长什么样 | 校外登录 WebVPN 复制地址 | 决定校外兜底方案 |
| V7 | Cookie 有效期多久 | 隔天再打开 | 决定同步频率 |
| V8 | 页面发请求时是否带额外 header（如签名） | 看 Request Headers | 决定 B 路径能否完全复刻 |

---

## 5. 总体架构

### 5.1 分层

```
┌──────────────────────────── App (SwiftUI) ────────────────────────────┐
│ TimetablePanel(380)   TimetableWindow(编辑)   ImportWindow(WKWebView)  │
│        │                    │                        │               │
│        └──────── TimetableController (@MainActor) ────┘               │
│                    状态机 / 预览 / 冲突 / 撤销                          │
└───────────────┬───────────────────────────────┬───────────────────────┘
                │                               │
      ┌─────────▼─────────┐           ┌─────────▼──────────┐
      │ JLUGateSchedule   │           │ JLUGateNet         │
      │ (纯逻辑, 可离线测) │           │ JwxtClient         │
      │ Model / Parser    │           │ CampusSession      │
      │ Merge / WeekMath  │           │ CampusTrust(TOFU)  │
      │ Color / ICS       │           │ Preflight(代理/可达)│
      └─────────┬─────────┘           └─────────┬──────────┘
                │                               │
      ┌─────────▼───────────────────────────────▼──────────┐
      │ TimetableStore (actor, 原子写, 快照)                │
      │ ~/Library/Application Support/JLUGate/timetable/    │
      └────────────────────────────────────────────────────┘
```

**分层原则**：
- `JLUGateSchedule` 不 import WebKit/Network，能 `swift test` 离线跑完解析与合并；
- 登录方式（WebView / 原生 / 粘贴）只是"**产出 Cookie 或 JSON**"的策略，换掉不影响下游；
- UI 只做展示与手势，业务判断全在 Controller / 纯函数里。

### 5.2 新增文件（建议）

| 文件 | 层 | 职责 |
|---|---|---|
| `Sources/JLUGateSchedule/Model.swift` | Schedule | `TimetableArchive` / `Semester` / `Course` / `Meeting` / `WeekPattern` / `Event` |
| `.../WeekMath.swift` | Schedule | 第几周、日期↔周次、跨学期边界 |
| `.../PeriodProfile.swift` | Schedule | 作息表、节次→时间、默认吉大表 |
| `.../JwxtParser.swift` | Schedule | `datas.*.rows` → `ImportedSemester`；`YPSJDD`/周次解析 |
| `.../TimetableMerge.swift` | Schedule | 三方合并、diff、冲突 |
| `.../ColorPalette.swift` | Schedule | 稳定配色、对比度 |
| `.../ICSExport.swift` | Schedule | 导出 `.ics`（RFC 5545） |
| `Sources/JLUGateNet/CampusSession.swift` | Net | Cookie 存取（Keychain/0600）、WKWebView ↔ 原生迁移 |
| `Sources/JLUGateNet/JwxtClient.swift` | Net | 二跳请求、错误分类 |
| `Sources/JLUGateNet/CampusTrust.swift` | Net | 校园站点证书 TOFU（仅 `*.jlu.edu.cn`） |
| `Sources/JLUGateNet/TimetablePreflight.swift` | Net | 复用 `ProxyModeAnalyzer` + `ReachabilityService` 做预检 |
| `App/Sources/Timetable*.swift` | App | 面板、窗口、导入窗、编辑器、手势 |

> `Package.swift` 加 target + test target；`App/project.yml` 加依赖；`App-Compat/Sources` 同步一份 View。

### 5.3 控制器状态机

```
idle
 ├─(打开课表/同步)→ preflight ─┬─ ok ──→ sessionCheck ─┬─ valid ──→ fetching → review → commit
 │                             │                       └─ expired ─→ loginWindow ─→ capturing → review
 │                             ├─ proxyGlobal ─→ 提示加 DIRECT 规则（可重试）
 │                             ├─ notCampus    ─→ 提示先连校园网 / 用 WebVPN
 │                             └─ certUntrusted → 指纹确认（仅 jlu 域）
 └─(首次)→ importWindow(URL) → login → capturing → review → commit
```

`review` 是**必须**的一步：哪怕只有"无变化"也要告诉用户结论；有变化就进 diff 面板。

---

## 6. 登录与会话

### 6.1 主路径：独立窗口里的 WKWebView

**为什么必须独立窗口**：popover 里塞 WebView 是已知崩溃源；而且登录页需要键盘焦点、要能开新标签、要能记住密码管理器。

**窗口生命周期（关键，历史崩溃大概率就出在这）**：

```swift
final class ImportWindowController: NSWindowController {
    private let webView: WKWebView
    init(...) {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()          // 持久 Cookie：下次不用重新登录
        cfg.userContentController.add(handler, name: "timetable")
        cfg.userContentController.addUserScript(hookScript)  // atDocumentStart
        webView = WKWebView(frame: .zero, configuration: cfg)
        let window = NSWindow(contentRect: ..., styleMask: [.titled, .closable, .resizable], ...)
        window.isReleasedWhenClosed = false        // ← 不加这句就是 use-after-free
        window.contentView = webView
        super.init(window: window)
    }
}
```

> 我的判断：当年的 SIGABRT 更像是 `NSWindow` 被释放后仍在 display cycle 里被访问（默认 `isReleasedWhenClosed = true`），而不是 WebKit 本身的问题。M0 用最朴素的窗口验证一次就能证实/证伪。

**注入的钩子**（简化）：

```js
// atDocumentStart, forMainFrameOnly: false
(function () {
  const send = (url, text) => {
    try { window.webkit.messageHandlers.timetable.postMessage({ url, text }); } catch (e) {}
  };
  const hit = u => /cxxszhxqkb\.do/i.test(u);
  const of = window.fetch;
  window.fetch = function (...args) {
    const p = of.apply(this, args);
    p.then(r => { if (hit(r.url)) r.clone().text().then(t => send(r.url, t)); }).catch(() => {});
    return p;
  };
  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (m, u, ...rest) {
    this.addEventListener('load', () => {
      if (hit(u)) send(String(u), this.responseText);
    });
    return open.call(this, m, u, ...rest);
  };
})();
```

**收尾逻辑**：
1. `didFinish` 时看 URL：落在 `cas.jlu.edu.cn` → 状态"等你登录"；
2. 落在 `iedu.jlu.edu.cn` 且没有 `#/xskcb` → `evaluateJavaScript("location.hash='#/xskcb'")`；
3. 捕获到响应 → 停止收集（去抖 1.2s）→ 解析 → 弹"导入/更新"确认；
4. 25s 没捕获到 → 提示"页面好像没加载课表，点这里重试 / 换成粘贴导入"。

**默认不自动填充**（遵守 D-001）。可以给一个显式开关「帮我把账号填上」，只做 `value = ...` 不自动提交；关掉就完全手输。

### 6.2 可选快路径：原生 CAS

参考实现证明 TPASS 可以纯原生登录：GET 登录页拿 `lt/execution` → `rsa = DES(用户名+密码+lt)` → POST。好处是**无 WebView、可静默重登**；坏处是要实现 TPASS 的 DES 细节、要处理验证码、CAS 一改就崩。

**建议**：v1 不做。等 A 路径跑顺了，如果发现"每天都要重新登录"很烦，再把"用已存密码静默重登"作为**可选开关**加上（失败自动回落到网页登录）。这样风险可控。

### 6.3 会话存储

- WebView 用 `.default()` 数据仓库，Cookie 由 WebKit 自己持久化；
- 原生请求需要同一份 Cookie：`WKWebsiteDataStore.default().httpCookieStore.getAllCookies` → 过滤 `.jlu.edu.cn` → 存 `CampusSession`；
- `CampusSession` 落盘沿用 `CredentialStore` 的双后端：正式签名 → Keychain；ad-hoc → 0600 文件；
- 提供「退出登录」= 清 WebView 数据 + 清 `CampusSession`。

### 6.4 安全边界

- **不做**：绕过证书校验、把 Cookie 写日志、把课表/学号发到任何服务器；
- 证书不受信时（V5），只对 `*.jlu.edu.cn` 弹一次"指纹确认"，把 SPKI SHA-256 存下来做 TOFU；换证书要重新确认；
- 课表文件 0600；崩溃报告与诊断导出**不包含**课程名/教室；
- 导出 ICS/JSON 只在用户点按钮时发生，路径由用户选。

### 6.5 代理 / 规则模式

“规则模式能不能用”本质是：**去 `iedu.jlu.edu.cn` 的流量有没有被 TUN 接管**。做法：

1. 读路由（复用 `ProxyModeAnalyzer`）→ `direct / ruleSplit / global / tunnelIdle`；
2. 同时探一次 `iedu.jlu.edu.cn`（复用 `ReachabilityService`，只发 HEAD/GET，不带凭据）；
3. 组合出结论：

| 路由 | 探测 | 结论 | 给的下一步 |
|---|---|---|---|
| ruleSplit / direct | 通 | ✅ 可以 | 直接进 |
| global | 通 | ⚠️ 能通但绕路 | "能用，但登录/同步可能慢；建议给 `jlu.edu.cn` 加 DIRECT" |
| global | 不通 | ❌ 被代理吞了 | 复制规则：`DOMAIN-SUFFIX,jlu.edu.cn,DIRECT` + `IP-CIDR,10.0.0.0/8,DIRECT` |
| direct | 不通 | ❌ 不在校园网/未认证 | "先连校园网并认证；校外用 WebVPN 地址" |

规则片段一键复制，不自动改用户的代理配置（那是另一个 App 的地盘）。

---

## 7. 数据模型

### 7.1 存储位置

```
~/Library/Application Support/JLUGate/timetable/
├── timetable.json           # 全部学期（一个文件，原子写，0600）
├── timetable.backup.json    # 上一版
└── snapshots/               # 最近 10 次提交前的快照（可回滚）
    └── 2026-11-05T09-12-33Z.json
```

**为什么不用 `config.json`**：配置很小、要向前兼容、每次启动读；课表会长到几百 KB，且有独立版本节奏。分开存，互不拖累。

### 7.2 结构（Swift）

```swift
public struct TimetableArchive: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var semesters: [Semester] = []          // 多学期并存，按 firstWeekMonday 排序
    public var activeSemesterID: UUID?
    public var periodProfiles: [PeriodProfile] = [.jluDefault]  // 作息表可复用
    public var colorOverrides: [String: Int] = [:] // colorKey -> 调色板下标
    public var updatedAt: Date = .now
}

public struct Semester: Codable, Sendable, Identifiable {
    public var id: UUID
    public var code: String?            // "2025-2026-1"（来自 XNXQDM）
    public var title: String            // "2025–2026 学年 第一学期"
    public var firstWeekMonday: String  // "2025-09-01"（存字符串，避时区坑）
    public var weekCount: Int           // 20
    public var periodProfileID: UUID
    public var courses: [Course]
    public var events: [ScheduleEvent]
    public var overrides: [SessionOverride]  // 本周临时调课/停课/补课
    public var importMeta: ImportMeta?       // 来源 URL、时间、原始行数
    public var createdAt: Date
    public var updatedAt: Date
}

public struct Course: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var teacher: String
    public var note: String
    public var credit: Double?
    public var colorKey: String          // 默认 = 归一化课名（"数据结构"）
    public var colorIndex: Int?          // 用户手动改色
    public var meetings: [Meeting]
    public var sourceKey: String?        // 教务来源稳定键（手工课为 nil）
    public var origin: Origin            // .imported / .manual / .copied
    public var hidden: Bool              // 软删除（防止下次同步复活）
    public var edits: [String: FieldEdit] // 字段级"我改过"
}

public struct Meeting: Codable, Sendable, Identifiable {
    public var id: UUID
    public var weekday: Int              // 1...7
    public var startPeriod: Int          // 1...12（坐标是节次，不是钟点）
    public var endPeriod: Int
    public var weeks: WeekPattern
    public var location: String
    public var timeOverride: ClockRange? // 例外：这门课就是 14:00–15:30
    public var edits: [String: FieldEdit]
}

public struct WeekPattern: Codable, Sendable, Hashable {
    public var ranges: [WeekRange]       // [1...16]
    public var parity: Parity            // .all / .odd / .even
    public var unknownText: String?      // "待定" 原样留着，UI 标黄
    public func weekSet() -> Set<Int>    // 合并/比较用这个
}

/// 三方合并的关键：记下"我改的时候，学校那边是什么值"
public struct FieldEdit: Codable, Sendable {
    public var value: String
    public var importedValueAtEdit: String?
    public var at: Date
}
```

### 7.3 JSON 样例

```json
{
  "schemaVersion": 1,
  "activeSemesterID": "6F1C…",
  "semesters": [{
    "id": "6F1C…",
    "code": "2025-2026-1",
    "title": "2025–2026 学年 第一学期",
    "firstWeekMonday": "2025-09-01",
    "weekCount": 20,
    "courses": [{
      "id": "A2…",
      "name": "数据结构",
      "teacher": "张三",
      "colorKey": "数据结构",
      "meetings": [{
        "weekday": 1, "startPeriod": 1, "endPeriod": 2,
        "weeks": { "ranges": [{"start": 1, "end": 16}], "parity": "all" },
        "location": "逸夫楼101"
      }],
      "origin": "imported",
      "hidden": false,
      "edits": { "teacher": { "value": "张三（调）", "importedValueAtEdit": "张三", "at": "2026-03-01T…" } }
    }],
    "events": [],
    "overrides": []
  }]
}
```

### 7.4 迁移

- 顶层 `schemaVersion`；每次读先跑迁移链（v1 → v2 …），迁移函数是纯函数、有测试；
- 读失败**绝不覆盖**：照 `ConfigStore` 的做法留 `timetable.unreadable-<时间>.json` 再回退备份；
- 未识别字段用 `decodeIfPresent` 兜默认值（和 `AppConfig` 同一套纪律）。

---

## 8. 导入、更新与合并

### 8.1 管线

```
原始响应(JSON) → JwxtParser → ImportedSemester
                              ├─ courses: [ImportedCourse]（含 warnings）
                              └─ code/title
        ↓
   TimetableMerge.apply(incoming, into: archive)
        ├─ .unchanged
        ├─ .changes([Change])       // 新增/修改/删除/冲突
        └─ .conflicts([Conflict])
        ↓
   review UI → commit → TimetableStore.save(snapshot first)
```

### 8.2 身份键（决定"谁是谁"）

- **课程级**：`normalize(KCM)` + `SKJS`；
- **上课时段级**：课程键 + `weekday` + `startPeriod` + `endPeriod`；
- **地点/周次**是属性，不参与身份——否则教室一换就变成"删一门加一门"；
- 同一门课同一天同一节但周次不同（单双周分开排）→ 合并 `weekSet`，保留两条 `WeekPattern` 供展示；
- 手工新增的课 `sourceKey = nil`，永远不参与"被学校删除"。

### 8.3 三方合并（这是"能反复更新"的核心）

对每个字段（名称/教师/地点/节次/周次）：

| 本地 | 学校新值 | 结果 |
|---|---|---|
| 没改过（无 `FieldEdit`） | 变了 | 用学校值，标"已更新" |
| 没改过 | 没变 | 不动 |
| 改过（`value`） | 等于 `importedValueAtEdit`（学校没动） | **保留本地** |
| 改过 | 等于 `value`（改到一块去了） | 收敛，删掉 `FieldEdit` |
| 改过 | 既不是本地值也不是编辑时的学校值 | **冲突**：默认留本地，列表里让你二选一 |
| 本地隐藏（tombstone） | 又出现了 | 保持隐藏，提示"学校又排回来了" |
| 本地改过 | 学校删了 | 保留 + 提示"学校已撤课，要删吗" |

> 一句话：**存了 `importedValueAtEdit`，才知道"到底是谁改的"**。没有它就只能猜，猜错就会覆盖用户。

### 8.4 变更预览

```
本次同步：新增 2 · 修改 3 · 删除 1 · 冲突 1
┌──────────────────────────────────────────────┐
│ ＋ 人工智能导论   周四 5-6 节  1-16 周         │
│ ～ 数据结构       教室 逸夫楼101 → 理化楼203   │
│ ～ 大学英语       周次 1-16 → 1-8,10-16       │
│ － 体育（游泳）                                │
│ ⚠ 高等数学       你改成"王老师"，学校改成"李老师" │
│                   [用我的] [用学校的]          │
└──────────────────────────────────────────────┘
        [全部采用学校]  [只应用无冲突项]  [取消]
```

应用后弹一条"已更新，可撤销"，撤销就是把快照写回去。

### 8.5 多学期

- 每次同步先取 `dqxnxq.do` 的当前学期码；返回的 `XNXQDM` 决定写进哪个学期；
- 学期不存在 → 新建（可选"从上一学期复制课程"，因为很多课跨学期重复）；
- **历史学期只增不删**；已结束的学期在列表里标"已结束"，仍可查看/导出；
- 若 V3 验证通过（接口支持传历史 `XNXQDM`），提供"补拉往期"；否则只能从本学期开始积累；
- 切换学期不改变 `activeSemesterID` 之外的数据，互不影响。

### 8.6 自动同步

- 默认**关**。开启后：启动时若距上次同步 > 12h 且 Cookie 有效 → 后台拉一次；
- 有变化只发通知 + 角标，**不自动应用**（避免把用户改的东西悄悄冲掉）；
- 无变化静默。

---

## 9. 纠错机制（你说的"调节"）

核心思想：**课表以「周几 + 第几节 + 哪些周」为坐标，钟点由作息表算出来**。这样改作息不会破坏课表，改课表也不用手算时间。

### 9.1 网格手势

| 操作 | 结果 |
|---|---|
| 点空格 | 新建：课程 / 活动（二选一） |
| 点卡片 | 详情浮层：地点、教师、周次、颜色、备注、删除 |
| 拖卡片 | 移动；松手问"仅本周 / 从本周起 / 整门课" |
| 拖卡片上下边缘 | 改节数（1→2 节） |
| 右键 | 复制、隐藏、改色、导出该门课 |
| ⌘Z | 撤销（编辑与同步共用一个 undo 栈） |
| 拖入 `.ics` / JSON | 导入外部课表 |

### 9.2 周次编辑

- 一排 1…20 的方格，点选/框选；单双周开关；
- 文本框与方格双向同步：输入 `1-8,10-16(单)` 立刻体现在格子上；
- 解析失败不覆盖原文，标红并保留 `unknownText`。

### 9.3 「本周调整」层（真实校园生活必备）

课程是"模板"，某一周可能被调走/停掉/补一次。三者都不改模板，只加一条 `SessionOverride`：

```swift
public struct SessionOverride {
    public var date: String          // 2026-03-09
    public var courseID: UUID?
    public var kind: Kind            // .cancelled / .moved / .extra
    public var newStart: Int?        // moved/extra：新节次
    public var newEnd: Int?
    public var newLocation: String?
    public var note: String
}
```

- 网格上：停课划一道灰线；调课在原位置留"→周四 5-6"的小字；补课用虚线框；
- 导出 ICS 时按"模板 + override"展开成实际发生的事件；
- 同步时 override **永远不被覆盖**（它本来就不是学校数据）。

### 9.4 作息表（时间）

- 内置官方 12 节表（§4.3），**可编辑**：改名、改起止、增删节次、加"午休/晚休"分隔；
- 多套作息并存（本部 / 某校区 / 夏季），学期引用其中一套；
- 改完立刻重算所有卡片上的钟点，课程数据一个字节不动；
- 单节课的例外（`timeOverride`）只影响那一节。

> 参考实现里内置的节次时间是"连续"的（少了 8:45–8:55 这种课间），和官方表不一致——这正说明"必须可改 + 默认值要准"。

### 9.5 学期边界

- 第一周周一：默认从学期码推断（秋季≈9 月第一个周一，春季≈2 月最后一周一），**显式让用户确认**；
- 总周数默认 20，可改；
- 今天落在第几周由 `WeekMath` 纯函数算，有测试覆盖跨年、开学前、放假后。

### 9.6 导入校对报告

导入后先给一份"体检"，而不是直接落库：

| 检查 | 处理 |
|---|---|
| 周次没解析出来 | 标黄，要求选周次或保留原文 |
| 地点为空 | 允许留空，提示可后补 |
| 节次越界（13 节） | 标红，阻止提交 |
| 两门课同格 | 允许（真实存在），但列出冲突清单 |
| 同课名不同教师 | 视为不同课，提示是否合并 |

---

## 10. 颜色

### 10.1 分配

```
colorKey = 归一化课程名（去空格、全半角统一）
index = stableHash(colorKey) % 12
```

- 同名同色，**跨学期、跨导入稳定**；
- 同学期内两门课撞色 → 按黄金角二次扰动（+5），保证相邻不撞；
- 用户改色存 `colorIndex`，同步不覆盖。

### 10.2 两套色板

- 浅色：`S≈0.55, B≈0.95` 的柔和底 + 深色字；
- 深色：`S≈0.45, B≈0.55` + 浅色字；
- 文字颜色由相对亮度算，不手写；
- 卡片圆角 8、左侧 3pt 色条、课程名最多两行、教室省略号。

### 10.3 状态

| 状态 | 表现 |
|---|---|
| 非本周 | 整体 35% 透明 + 虚线边 |
| 冲突 | 右上角红色小三角，详情里列冲突对象 |
| 临时调整 | 右下角"调"字角标 |
| 手工添加 | 无角标；详情里标"我加的" |
| 已隐藏 | 不显示，管理页可恢复 |

### 10.4 可访问性

- 不靠颜色单独传达信息（都有文字/角标）；
- 色板避开红绿唯一对比（红/绿都配图标）；
- 提供"高对比"开关（描边加深、去透明）。

---

## 11. 活动 / 日程

### 11.1 模型

```swift
public struct ScheduleEvent: Codable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var location: String
    public var note: String
    public var colorIndex: Int?
    public var timing: EventTiming
    public var reminderMinutes: [Int]   // 0 / 10 / 30
    public var semesterID: UUID?        // nil = 跨学期长期活动
}

public enum EventTiming: Codable, Sendable {
    case once(date: String, start: Int?, end: Int?)                  // 分钟数；nil = 全天
    case weekly(weekdays: [Int], weeks: WeekPattern, start: Int, end: Int)
    case daily(from: String, to: String, start: Int, end: Int)
}
```

### 11.2 与课程的关系

- 两套数据，共用网格与"今天"列表；
- 活动可以"挂在某门课旁边"（如"实验课预习"），但不继承课程时间；
- 冲突只提示不阻止（现实里就是会撞）；
- 跨学期活动（`semesterID = nil`）在每个月都显示，适合"每周三健身"。

### 11.3 提醒

- `UNUserNotificationCenter`，只排未来 7 天，App 启动/切换周时滚动补排（避开 64 条上限）；
- 冲突/停课不提醒；
- 默认关，用户开。

### 11.4 导出

- **ICS**：课程按"模板 + override"展开成 `VEVENT`，`RRULE` 用 `BYDAY` + `INTERVAL`（单双周用 `INTERVAL=2`），带 `UID`/`DTSTAMP`；
- **JSON**：整份档案（备份/迁移）；
- 可选 **EventKit** 写入系统日历（需要用户授权，写到一个专门日历，避免污染）。

---

## 12. 界面

### 12.1 面板（380pt）

```
┌ 课表 ────────────────────────────┐
│ 第 10 周 · 11/03–11/09      [同步]│
│ ┌──────────────────────────────┐ │
│ │ 一 二 三 四 五 六 日          │ │
│ │ ▓▓ ▓▓ ·  ▓▓ ·  ·  ·          │ │  ← 12 节压缩成 40px/节
│ │ ▓▓ ·  ▓▓ ▓▓ ·  ·  ·          │ │
│ └──────────────────────────────┘ │
│ 今天                                     │
│ 08:00 数据结构 · 逸夫楼101      [进行中] │
│ 13:30 大学英语 · 外语楼302               │
│ 19:00 社团例会 · 活动中心（活动）        │
│ [打开完整课表]  [＋ 加活动]              │
└──────────────────────────────────┘
```

### 12.2 完整窗口（900×640）

- 左：7 列 × 12 行网格（可缩放密度），周切换器，学期选择；
- 右：Inspector（选中项的详情/编辑）；
- 顶：同步状态 + 变更徽标 + 撤销；
- 底：图例（课程/活动/调课/非本周）。

### 12.3 导入窗口

```
┌ 导入课表 ────────────────────────────────┐
│ 地址 [https://iedu.jlu.edu.cn/...xskcb] [打开]│
│ 状态：● 等待登录 / ● 已进入课表 / ● 已捕获 32 门 │
│ ┌─────────────────────────────────────┐ │
│ │            (WKWebView)              │ │
│ └─────────────────────────────────────┘ │
│ [从当前页面导入]        [改用粘贴 JSON]   │
└──────────────────────────────────────────┘
```

### 12.4 首次引导与失败诊断

- 三步：打开 → 登录 → 导入；每步都有"卡住了？"展开项；
- 失败按 §6.5 的表给结论，不甩"网络错误"；
- 面板里放一个"课表"入口 + 一个"下一节课"小卡（可选，后续做）。

### 12.5 文案成本

新增约 **90–120 条**文案 × 3 语言；`CopyTests.fullTables` 的 711 要同步改。建议文案编号用新段（如 `TB01…`），别和现有 `T01`（站点）混。

---

## 13. 里程碑

| 阶段 | 内容 | 产出/验收 | 估时 |
|---|---|---|---|
| **M0 可行性验证** | ① 独立 NSWindow 装 WKWebView，加载课表 URL，登录后停留 30 分钟不崩；② 从 WebView 取 Cookie，用 `URLSession` 拉 `cxxszhxqkb.do` 拿到 JSON；③ 用真实响应跑通"字段 → 课程"的粗解析 | 一份验证记录（含崩溃/不崩、字段实际形态）；决定主路径 | 1–2 天 |
| **M1 数据层** | `JLUGateSchedule` target：模型、周次解析、`YPSJDD` 解析、周次计算、作息表、存储与迁移 | 单测全绿；能读写 `timetable.json`；假数据可渲染 | 3–4 天 |
| **M2 导入闭环** | 导入窗（WebView + 钩子 + 状态机）、Cookie 持久化、预览与提交、错误分类 | 真机走通"打开→登录→导入"；二次打开免登录 | 4–5 天 |
| **M3 编辑与更新** | 网格编辑/拖拽/周次、作息表编辑、diff + 三方合并、撤销、多学期管理 | 改完再同步不丢改动；冲突可解决；可回滚 | 5–6 天 |
| **M4 活动与提醒** | 事件模型/编辑器/重复规则、今日视图、通知、ICS 导出 | 能加活动并按时提醒；导出可被系统日历识别 | 3–4 天 |
| **M5 打磨** | 颜色与密度、三语文案、无障碍、面板紧凑视图、隐私审查、文档 | `make ci` 全绿；隐私扫描干净；截图 | 3–4 天 |

合计约 **19–25 人日**（业余 4–6 周）。M0 之后可以砍范围：只做 M1+M2+M3 就是"能导入、能改、能更新"的最小可用版。

---

## 14. 风险登记

| 风险 | 概率 | 影响 | 对策 | 触发降级 |
|---|---|---|---|---|
| WKWebView 仍崩 | 中 | 高（登录路径没了） | M0 先验；独立窗口 + `isReleasedWhenClosed=false`；崩了只影响导入窗 | 降级到"原生 CAS"或"系统浏览器 + 粘贴 JSON" |
| 教务接口/页面改版 | 中 | 中 | 解析与取数分离；保留 C 路径；字段缺失不崩 | 提示"接口变了"，引导粘贴 |
| CAS 要验证码/二次验证 | 中 | 中 | 只做人工网页登录，不绕过 | 每次都手登，可接受 |
| 证书不受信 | 中 | 中 | TOFU + 指纹确认，仅限 `jlu.edu.cn` | 提示手动信任，不做全局放开 |
| 全局代理吞掉校园域 | 高 | 中 | 预检 + DIRECT 规则片段 | 用户改规则后重试 |
| 同步覆盖用户改动 | 中 | 高（信任崩塌） | 三方合并 + 快照 + 撤销 + 默认不自动应用 | 出问题一键回滚 |
| 学期/周次错位 | 中 | 中 | 第一周周一显式确认 + 预览 | 手动改 |
| 隐私泄漏（课表/学号/MAC） | 低 | 高 | 0600、日志脱敏、扫描脚本、导出由用户触发 | 删数据 + 修日志 |
| App-Compat 双份源码漏改 | 中 | 低 | 逻辑下沉；UI 双份有清单 | 编译期就会报错 |
| 范围膨胀（做成"校园 App"） | 高 | 中 | 明确非目标；先 M1–M3 | 砍 M4/M5 |

---

## 15. 测试与隐私

**单测（离线，进 `make test`）**
- 周次表达式：`1-16`、`1-16(单)`、`1,3,5`、`2-8,10-16`、`待定`、空；
- `YPSJDD` 多段：`1-16周 星期一 第1-2节 A楼101, 1-8周 星期三 第5-6节 B楼202`；
- 兜底字段（`SKXQ/KSJC/JSJC`）；
- 三方合并矩阵的每一行；
- 周次/日期计算（跨年、开学前、第 21 周）；
- 配色稳定性（同名同色、跨学期一致）；
- ICS 生成（单双周 RRULE）。

**夹具**
- 只用合成数据（张三/数据结构/逸夫楼101），**不放真实响应**；
- 真实响应只在本机 `/tmp` 里验证，验完删；`privacy-scan` 会拦学号/IP。

**手工验收**
- 断网、退出登录、Cookie 过期、切换学期、改作息、调课、删课、重复导入、冲突解决、撤销。

---

## 16. 不做什么

- 不做抢课/自动提交/验证码识别；
- 不做成绩、考试（可后续复用会话，但不是这次）；
- 不做云端同步/分享码/社交；
- 不做后台常驻轮询；
- 不为了"看起来功能多"而做导出到 Notion/飞书。

---

## 17. 需要你拍板

1. **登录主路径**：先做 WebView（贴近你的描述，但有崩溃风险），还是先做原生 CAS（稳，但要处理验证码，且要决定"能不能用已存密码"）？
   我的建议：**M0 先用一天验证 WebView；不崩就走 WebView**，崩了再换。
2. **能不能用统一身份认证密码做原生登录**？如果只允许网页手输，就永远不做静默重登。
3. **编辑界面**：开独立窗口（推荐，信息密度够）还是硬塞进 380 面板（不用窗口，但编辑很憋）？
4. **活动要不要写进系统日历**（EventKit）？要的话首次会弹权限。
5. **自动同步**默认开还是关？我倾向**默认关**，只在打开课表时提示"有 3 处变化"。
6. **历史学期**：只从本学期开始积累，还是要我尝试"补拉往期"（依赖 V3 验证）？

---

## 附录 A：怎么抓一次真实响应（M0 用）

1. 校园网内，浏览器登录教务 → 打开课表页；
2. DevTools → Network → 过滤 `cxxszhxqkb` → 刷新/切周；
3. 右键请求 → **Copy as cURL**；响应 → Save all as HAR/JSON；
4. 把 JSON 存到 `/tmp/jlu-schedule.json`，用最小脚本验证字段；
5. **验证完删除**，不要 `git add`（`privacy-scan.sh` 会拦学号）。

## 附录 B：参考资料

- 吉大本科教学作息时间表：<http://jwc.jlu.edu.cn/sksj.htm>
- 吉大教务入口（CAS 链接可见）：<http://jwc.jlu.edu.cn/>
- 参考实现（GPL-3.0，仅参考行为）：<https://github.com/JFyuhong/JLU_schedule>
- 小爱课表吉大适配：<https://github.com/Temsys-Shen/AiScheduleForNewJLU>
- 吉大课表 Flutter 实现：<https://github.com/con9uer666/jlu-mobile-schedule>
- 强智系课表 API 思路：<https://github.com/inannan423/classCrawl>
- ClassIsland 档案/时间表模型：<https://docs.classisland.tech/app/profile/>
- iCalendar 规范：<https://datatracker.ietf.org/doc/html/rfc5545>
- 本仓库连接冻结规则：`docs/connection-freeze.md`

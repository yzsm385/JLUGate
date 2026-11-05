# 课表 × 日程：JLU Gate 集成方案（v0.4 讨论稿）

> **状态**：方案讨论稿，尚未写代码。
> **v0.4 修订**（2026-11-05，按你的两条新要求）：
>
> | 上一版 | 这一版 | 为什么 |
> |---|---|---|
> | 原生扫码 + 原生密码 | **只嵌网页 + 只预填账号** | 扫码协议有风险；验证码不代填、不识别、不自动提交 |
> | 周方格流为主 | **二维周网格为主**，方格流降为备用 | 先做成熟形态 |
> | 纵轴按节次等分 | 纵轴 = **真实时间**，节次线是刻度；长休息可折叠 | 既保留网格，又能容纳"晚半小时"的课 |
>
> v0.2/v0.3 的学期日历、起止周、显示开关、作息表（节数/课间/放学）、开机提醒，全部保留。

---

## 0. 结论

| 问题 | 结论 |
|---|---|
| 能不能记住地址直接进？ | 能。`https://iedu.jlu.edu.cn/jwapp/sys/wdkb/*default/index.do#/xskcb` 存为默认入口 |
| 未登录怎么办？ | 实测该地址会 302 到 `cas.jlu.edu.cn/tpass/login?service=<原地址>`；登录后原路返回，补 `#/xskcb` 就是课表 |
| 登录怎么做？ | **面板里嵌 CAS 网页**；用户自己扫码/输密码/填验证码；我们**只预填账号**，不提交、不识别验证码 |
| 为什么不实现扫码协议？ | 要复刻企业微信 OAuth + uuid 轮询，任何一步变了就废；而页面本身就能扫码，没必要重写 |
| 能不能塞进 380 面板？ | 能：**7 列 × 真实时间的二维网格**；周末可隐藏，列宽自动变大 |
| 不规整的课怎么办？ | 纵轴按**真实分钟**排，节次线只是刻度；08:30 的课就画在 08:30，不强行对齐 |
| 更新/多学期？ | 一个 `timetable.json` 存 N 个学期；重新同步走三方合并，手改不被覆盖 |
| 最大风险？ | **WKWebView 在面板里崩/太挤**（M0 先验）；教务接口字段变化；同步覆盖手改 |

---

## 0.1 先说难听的：值不值得做

- 只想"看课表"：手机上的 WakeUp、开源 [JLU_schedule](https://github.com/JFyuhong/JLU_schedule) 都能用。
- JLU Gate 的增量：登录态/校园网/入口/提醒在一个 App；菜单栏一眼看到"下一节"；课表变动能和网络状态一起解释。
- 代价：一个新子系统（约 15–20 人日）+ 一条长期维护面。
- 可裁剪：只做 **M1+M2**（导入 + 同步 + 只读展示）约 1 周多；编辑和活动后加。

---

## 1. 需求（含本轮新增）

| # | 用户故事 | 验收 |
|---|---|---|
| U1 | 记住课表地址，一键直达 | 首次填一次，之后点「课表」就开 |
| U2 | 没登录自动跳登录，登录完直接看到课表 | 302 → CAS → 回跳 → 补 `#/xskcb` |
| U3 | 登录后能导入 | 「导入本学期（32 门）」→ 预览 → 落库 |
| U4 | 时间/格子/周次都能改 | 点方块改、拖时间、改周次 |
| U5 | 颜色稳定好看 | 同名同色、跨学期一致、可手改 |
| U6 | 能加活动 | 一次性/每周/全天，可提醒 |
| U7 | 能反复更新 | 同步 → diff → 合并，手改不丢 |
| U8 | 多学期并存 | 学期列表切换，历史不删 |
| U9 | 规则模式下能用 | 预检 + DIRECT 规则提示 |
| U10 | **不规整的课不被强行对齐** | 08:30 的课画在 08:30；重叠并排；可标「偏轴」 |
| U11 | **时间轴本身可调** | 改起止、缩放、改节次表；改完所有课自动重算 |
| U12 | **全部在 380 面板里完成** | 不出现独立窗口（v1 硬约束） |
| U13 | 登录界面能预填 | 网页登录时填 `#un`/`#pd`；原生表单直接带出账号密码 |

---

## 2. 约束

| 约束 | 影响 |
|---|---|
| 380pt popover，**v1 不开独立窗口** | 不能做 7×12 大网格；编辑用内联卡片；登录不能靠大网页 |
| WKWebView 历史崩溃 | v1 只在**登录页**用 WebView；M0 先验面板内稳定性，崩了就退独立登录窗 |
| Core 不 import 网络 | 解析/合并/时间轴/配色全放纯逻辑 target |
| DrCOM 冻结 10 个文件 | 新文件随便加，别碰旧的 |
| 无三方依赖 | QR 用 CoreImage，HTTP 用 URLSession |
| 文案三语 + `CopyTests` 写死 711 | 新文案要同步三张表并改数字 |
| `App/` 与 `App-Compat/` 两份源码 | View 要放两遍，逻辑下沉 |
| MIT 仓库 | 参考实现是 GPL-3.0，只参考行为，不抄代码 |

---

## 3. 调研（结论没变，压缩）

| 方案 | 学到什么 |
|---|---|
| [JLU_schedule](https://github.com/JFyuhong/JLU_schedule)（吉大，GPL） | 吉大接口链、字段、周次表达式；WebView 捕获 vs 原生二跳；多课表/备份/小组件 |
| [AiScheduleForNewJLU](https://github.com/Temsys-Shen/AiScheduleForNewJLU) | 新教务页面可解析；但一次性导入、页面一改就废 |
| [ClassIsland](https://docs.classisland.tech/app/profile/) | 「课表 / 时间表 / 科目」三层；时间表可复用、可单独改 |
| WakeUp / 超级课程表 | 周视图、配色、多课表、小组件；ICS/JSON 是事实交换格式 |
| [classCrawl](https://github.com/inannan423/classCrawl) | "能拿 JSON 就别抓 HTML"的普遍经验 |

三条经验：**优先 JSON；登录只产出 Cookie；一次性导入的产品活不久。**

---

## 4. 吉大链路（含本轮实测）

### 4.1 地址

| 用途 | 地址 |
|---|---|
| 课表页 | `https://iedu.jlu.edu.cn/jwapp/sys/wdkb/*default/index.do#/xskcb` |
| 门户 | `https://iedu.jlu.edu.cn/jwapp/sys/emaphome/portal/index.do` |
| CAS | `https://cas.jlu.edu.cn/tpass/login?service=<encoded>` |
| 当前学期 | `POST .../wdkb/modules/jshkcb/dqxnxq.do` |
| 整学期课表 | `POST .../wdkb/modules/xskcb/cxxszhxqkb.do`，body `XNXQDM=<学期码>` |

### 4.2 302 链（实测）

```
GET https://iedu.jlu.edu.cn/jwapp/sys/wdkb/*default/index.do
  → 302 Location: https://cas.jlu.edu.cn/tpass/login?service=https%3A%2F%2Fiedu.jlu.edu.cn%2Fjwapp%2Fsys%2Fwdkb%2F%2Adefault%2Findex.do
  → Set-Cookie: route=...
GET https://cas.jlu.edu.cn/tpass/login?...
  → 200, Set-Cookie: tpasssessionid=...; UqZBpD3n=...
```

所以"登录后直接显示课表"是天然的：**service 就是课表地址本身**，登录成功 CAS 会把浏览器送回它。`#/xskcb` 只是前端路由，我们回跳后补一句 `location.hash` 即可。

### 4.3 返回结构

```json
{"datas":{"xskcb":{"rows":[
  {"KCM":"数据结构","SKJS":"张三","YPSJDD":"1-16周 星期一 第1-2节 逸夫楼101",
   "ZCMC":"1-16周","SKXQ":"1","KSJC":"1","JSJC":"2",
   "JASMC":"逸夫楼101","JXLDM_DISPLAY":"逸夫楼",
   "XNXQDM":"2025-2026-1","XNXQDM_DISPLAY":"2025-2026学年第一学期","XF":"3.0"}
]}}}
```

| 字段 | 用法 |
|---|---|
| `KCM` / `SKJS` | 课程名/教师；身份键 |
| `YPSJDD` | 主解析源（多段拼接） |
| `ZCMC` | 周次兜底 |
| `SKXQ`/`KSJC`/`JSJC` | 星期/起止节兜底 |
| `JASMC`/`JXLDM_DISPLAY` | 教室/教学楼 |
| `XNXQDM` | 学期归档依据 |

### 4.4 节次（官方表，2023–2024 第二学期起）

| 节 | 时间 | 节 | 时间 |
|---|---|---|---|
| 1 | 08:00–08:45 | 7 | 15:30–16:15 |
| 2 | 08:55–09:40 | 8 | 16:25–17:10 |
| 3 | 10:00–10:45 | 9 | 18:20–19:05 |
| 4 | 10:55–11:40 | 10 | 19:05–19:50 |
| 5 | 13:30–14:15 | 11 | 20:00–20:45 |
| 6 | 14:25–15:10 | 12 | 20:45–21:30 |

> 参考实现内置的表是"连续"的（8:45 就上第二节），和官方不一致——这就是"时间轴必须可调"的现实理由。

### 4.5 周次表达式

`1-16周` / `1-16周(单)` / `1,3,5,7周` / `2-8周,10-16周` / `待定`。
认不出就保留原文 + 标黄，不猜。

### 4.6 本轮实测记录（2026-11-05，本机、非校园网）

| # | 实测 | 结果 |
|---|---|---|
| 1 | `cas.jlu.edu.cn` | 200，标题「智慧校园」；公网可达 |
| 2 | `iedu.jlu.edu.cn` | 公网可达；`/` 302 到门户；`wdkb` 302 到 CAS |
| 3 | CAS 三个 tab | 扫码登录（默认）/ 密码登录 / 手机登录 |
| 4 | 密码模板 | 只有 `#un`、`#pd`，**没有图形验证码**；验证码在「手机登录」tab（`#code`、`/tpass/code`） |
| 5 | 密码提交 | `rsa = strEnc(un+pd+lt,'1','2','3')`，表单 POST；`des.js` 是学校自定义实现 |
| 6 | `strEnc('test','1','2','3')` | `D8D35E5019288C41`，与标准 3DES-ECB（`c80c8db3…`）**不一致** → 移植要按它的位序来 |
| 7 | 扫码二维码内容 | `https://cas.jlu.edu.cn/tpass/qyQrLogin?uuid=<uuid>&service=<编码后前100字符>` |
| 8 | 扫码轮询 | 每 3s `GET /tpass/checkQRCodeScan?uuid=...`；未扫码返回空 body；成功后页面直接 reload |
| 9 | `qyQrLogin` | 302 到 `open.weixin.qq.com` 企业微信 OAuth（appid `ww3b03…`） → 扫码走「智慧吉大」 |
| 10 | 380 宽下的 CAS 页 | 横向溢出，tab 被切、字号巨大（见下图）→ 只能当"登录页"用，不能当主界面；必要时注入 CSS 收一下 |

**仍未验证**：面板内 WebView 稳定性、账号预填、密码是否二次验证、Cookie 名称与有效期。

### 4.7 待真机验证

| # | 未知 | 怎么验 |
|---|---|---|
| V1 | **面板内 WKWebView 稳不稳** | 380×520 里打开 CAS → 登录 → 停留 30 分钟，看崩不崩 |
| V2 | **账号预填能不能生效** | 点「密码登录」后读回 `#un.value` |
| V3 | 密码登录是否需要微信二次验证 | 真机用错/对密码各试一次（用户操作） |
| V4 | `cxxszhxqkb.do` POST/GET、参数大小写 | DevTools 抓页面自己的请求 |
| V5 | 一次是否返回整学期（不是单周） | 看 `YPSJDD` 的行数与周次 |
| V6 | 历史 `XNXQDM` 能否拉往期 | 改参数试 |
| V7 | `iedu` 是否真的"仅校内" | 校外网络再试一次 |

> 扫码协议的抓包（§4.6 #7–#9）**只作为背景**：v0.4 明确不实现原生扫码，页面里的二维码照常可用。

---

## 5. 架构（v1：只有登录用 WebView，不开独立窗口）

```
┌──────────────────── JLU Gate 菜单栏面板 (380) ────────────────────┐
│  课表 tab                                                          │
│   ├─ 未登录：CAS 登录页（WKWebView，预填账号）                      │
│   ├─ 已登录：二维周网格 / 单日放大 / 导入预览 / 编辑卡              │
│   └─ 状态条：校园网 / 代理 / 会话 / 同步                            │
└───────────────┬───────────────────────────────┬───────────────────┘
                │                               │
      ┌─────────▼─────────┐           ┌─────────▼──────────┐
      │ JLUGateSchedule   │           │ JLUGateNet         │
      │ 纯逻辑，可离线测   │           │ LoginBridge(捕获)  │
      │ Model / Parser    │           │ JwxtClient         │
      │ TimeAxis / Merge  │           │ CampusSession      │
      │ Color / ICS       │           │ Preflight          │
      └─────────┬─────────┘           └─────────┬──────────┘
                └──────────────┬────────────────┘
                     ┌─────────▼──────────┐
                     │ TimetableStore     │
                     │ actor + 原子写 + 快照│
                     └────────────────────┘
```

**关键决定**：登录**不做协议、不做自动化**，而是把学校的 CAS 页面放进面板，只帮用户填一个账号。扫码、密码、验证码、二次验证全部由页面和用户完成。我们只负责：

- 打开页面、判断"是否已登录"；
- 预填 `#un`（仅此一个字段）；
- 捕获课表响应，或把 Cookie 交给原生请求做日常同步。

### 5.1 新增文件

| 文件 | 层 | 职责 |
|---|---|---|
| `Sources/JLUGateSchedule/Model.swift` | Schedule | `TimetableArchive` / `Semester` / `Course` / `Meeting` / `WeekPattern` / `Event` |
| `.../TimeAxis.swift` | Schedule | 分钟↔y、节次参考线、重叠分列、不规整判定 |
| `.../PeriodProfile.swift` | Schedule | 作息表（可编辑、多套） |
| `.../JwxtParser.swift` | Schedule | `datas.*.rows` → `ImportedSemester`；周次/时间解析 |
| `.../TimetableMerge.swift` | Schedule | 三方合并、diff、冲突 |
| `.../ColorPalette.swift` | Schedule | 稳定配色、对比度 |
| `.../ICSExport.swift` | Schedule | 导出 `.ics` |
| `App/Sources/TimetableLoginWebView.swift` | App | 面板内 WKWebView、账号预填、响应捕获 |
| `Sources/JLUGateNet/TimetableSession.swift` | Net | 从 WKWebView 取 Cookie、供原生同步 |
| `Sources/JLUGateNet/JwxtClient.swift` | Net | `dqxnxq` + `cxxszhxqkb` + 错误分类 |
| `Sources/JLUGateNet/CampusSession.swift` | Net | Cookie 持久化（Keychain/0600） |
| `Sources/JLUGateNet/TimetablePreflight.swift` | Net | 路由/可达性预检 |
| `App/Sources/Timetable*.swift` | App | 登录卡、周视图、日视图、编辑卡、同步预览 |

---

## 6. 登录（只做网页 + 账号预填）

### 6.1 主路径：面板内嵌 CAS 页

```
点「课表」
 → WKWebView 加载 https://iedu.jlu.edu.cn/jwapp/sys/wdkb/*default/index.do#/xskcb
 → 302 到 cas.jlu.edu.cn/tpass/login?service=<原地址>
 → 用户自己完成：扫码 / 密码 / 验证码（页面怎么变我们不管）
 → 登录成功回跳 wdkb → 补 #/xskcb
 → 页面自己请求 cxxszhxqkb.do → 我们捕获响应（或读 Cookie 走原生）
 → 预览 → 导入
```

- 先放面板（380×520）；M0 验证能不能正常显示、输入、滚动、不崩；
- 崩了或实在挤 → **只给"登录"开一个独立窗口**（唯一例外），主界面仍在面板；
- 捕获：注入 hook 包 `fetch`/`XHR`，命中 `cxxszhxqkb.do` 就把 body 发回原生；
- 同时把 Cookie 存 `CampusSession`，下次「同步」直接用原生请求，省得再开网页。

### 6.2 预填：只有账号，而且不抢你的 tab

- CAS 页默认是扫码 tab；密码模板要点「密码登录」后才会进 DOM；
- 我们**不主动切 tab**，只做两件事：
  1. 页面加载完，如果密码 tab 已经激活（页面自己记了上次选择），直接把 `#un` 填上；
  2. 否则挂一个 capture 阶段的点击监听：你点「密码登录」后，等 `#un` 出现，立刻填入；
- 填入时派发 `input`/`change`，兼容页面校验；**不填密码、不点登录、不碰验证码**；
- 开关「帮我填账号」默认开；关掉就完全不注入；
- 只在 `cas.jlu.edu.cn/tpass/login` 注入，其他页面（含教务）一律不碰。

### 6.3 明确不做（风险边界）

| 不做 | 原因 |
|---|---|
| 原生扫码协议 | 企业微信 OAuth + uuid 轮询，任何一步变了就废；页面本身能扫 |
| 验证码识别/代填 | 你明确不要；也避免触发风控 |
| 自动提交 | 密码错会锁号；验证码/二次验证无法处理 |
| 预填密码 | 只做账号；密码只给 DrCOM 用 |
| 读页面里的密码 | 不读、不存、不日志 |

> 页面默认就是扫码 tab：用户想扫码，直接拿手机扫屏幕上的二维码即可。**这是网页自己的能力，不是我们实现的扫码。**

### 6.4 会话与安全

- Cookie 存 `CampusSession`：正式签名 → Keychain；ad-hoc → 0600 文件；
- 提供「退出登录」清 Cookie；
- 日志不打印 Cookie/密码/课程名；
- 不做后台轮询；只在用户点「课表」或「同步」时发请求；
- 不做证书绕过；`iedu` 目前是正常证书（实测 200），若将来不受信，只对 `*.jlu.edu.cn` 做一次性指纹确认。

### 6.5 规则模式预检

| 路由 | 探测 | 提示 |
|---|---|---|
| direct / ruleSplit | 通 | 直接进 |
| global | 通 | "能用，但慢；建议 `DOMAIN-SUFFIX,jlu.edu.cn,DIRECT`" |
| global | 不通 | 复制 `DOMAIN-SUFFIX,jlu.edu.cn,DIRECT` + `IP-CIDR,10.0.0.0/8,DIRECT` |
| direct | 不通 | 先连校园网；校外可直接试（实测公网可达），不行再用 WebVPN |

### 6.6 如果面板里不行

- **崩** → 退到独立登录窗口（只此一处），登录完关掉，课表仍在面板；
- **不崩但挤** → 可选注入一点 CSS 隐藏背景图/底部提示，让登录框占满（只改样式，不动表单、不提交）；不做也能用，只是要滚动；
- **系统浏览器** → 只能看，Cookie 拿不回，不能作为导入路径。

---

## 7. 数据模型

### 7.1 存储

```
~/Library/Application Support/JLUGate/timetable/
├── timetable.json           # 全部学期，0600，原子写
├── timetable.backup.json
└── snapshots/               # 最近 10 次提交前
```

### 7.2 结构（关键部分）

```swift
public struct TimetableArchive: Codable, Sendable {
    public var schemaVersion = 1
    public var semesters: [Semester] = []
    public var activeSemesterID: UUID?
    public var periodProfiles: [PeriodProfile] = [.jluDefault]
    public var colorOverrides: [String: Int] = [:]
}

public struct Semester: Codable, Sendable, Identifiable {
    public var id: UUID
    public var code: String?             // "2025-2026-1"
    public var title: String
    // ── 学期日历（三个都能改）──
    public var firstWeekStart: String    // 第 1 周第 1 天的日期，如 "2025-09-01"
    public var weekStartsOn: Int         // 1=周一 … 7=周日（只影响分栏和"本周"边界）
    public var weekCount: Int            // 一共几周，默认 20
    public var periodProfileID: UUID
    public var courses: [Course]
    public var events: [ScheduleEvent]
    public var overrides: [SessionOverride]
    public var importMeta: ImportMeta?
}

/// 作息表：节数、每节起止、课间、放学
public struct PeriodProfile: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String              // "本部 · 春秋" / "某校区"
    public var periods: [Period]         // 有序；数量 = 一天几节（1...16）
    public var gapLabels: [Int: String]  // afterPeriod -> "午休" / "晚餐"（可选）
    public var dismissLabel: String      // 最后一节结束 = 放学
}

public struct Period: Codable, Sendable, Hashable {
    public var index: Int                // 1...N
    public var startMinute: Int          // 距 00:00，08:00 = 480
    public var endMinute: Int            // 08:45 = 525
    // 相邻两节的课间 = 下一节.start - 本节.end
    // 最后一节之后**没有**课间：那是放学
}

/// 只看不改的显示偏好
public struct DisplaySettings: Codable, Sendable {
    public var showOffWeekCourses = true   // 非本周：淡显；关掉就完全不画
    public var showSaturday = true
    public var showSunday = false
    public var defaultView: ViewMode = .week
}

/// 一门课的时间：常规按节次，特殊按真实钟点
public enum MeetingTime: Codable, Sendable, Hashable {
    case periods(start: Int, end: Int)     // 1...12，交给作息表换算
    case clock(startMinute: Int, endMinute: Int)  // 08:30–10:05，不规整
}

public struct Meeting: Codable, Sendable, Identifiable {
    public var id: UUID
    public var weekday: Int
    public var weeks: WeekPattern
    public var location: String
    public var time: MeetingTime
    public var note: String
    public var edits: [String: FieldEdit]
}
```

**为什么用枚举**：常规课跟着作息表走（改作息自动重算），特殊课保存真实钟点（永远不规整）。两种都能画在同一条时间轴上。

### 7.3 周次

```swift
public struct WeekPattern: Codable, Sendable, Hashable {
    public var ranges: [WeekRange]
    public var parity: Parity        // all / odd / even
    public var unknownText: String?  // "待定"
    public func weekSet() -> Set<Int>
}
```

### 7.4 三方合并的关键

```swift
public struct FieldEdit: Codable, Sendable {
    public var value: String                 // 我改成的值
    public var importedValueAtEdit: String?  // 我改的时候学校是什么
    public var at: Date
}
```

没有 `importedValueAtEdit` 就分不清"谁改的"，只能覆盖用户。

---

## 8. 导入 / 更新 / 多学期

（与 v0.1 一致，压缩）

- 管线：`JSON → JwxtParser → ImportedSemester → Merge → 预览 → 提交（先快照）`；
- 身份键：课程 = `KCM + SKJS`；时段 = 课程 + 周几 + 起止；地点/周次是属性；
- 合并矩阵：没改过→跟学校；改过且学校没动→留；改到一处→收敛；都改→冲突（默认留我）；
- 预览：`＋2 ～3 －1 ⚠1`，可"全部采用学校/只应用无冲突/逐项"；
- 多学期：`XNXQDM` 决定写哪个学期；不存在就新建；历史只增不删；可"从上一学期复制"；
- 自动同步默认关；有变化只提示，不自动应用。

---

## 9. 显示与纠错（本轮重点）

### 9.1 主视图：二维周网格（7 列 × 真实时间）

```
        一     二     三     四     五     六     日
  1   ████   ████
  2   ████   ████
  3                 ████                 ████
  4                 ████                 ████
 …                  （纵轴是真实时间，节次线是刻度）
```

- 横轴 7 天（周六/周日可隐藏），纵轴 **08:00–21:30 真实分钟**；
- 左侧 1…12 是节次刻度，不是硬格子——所以 8:30 的课就画在 8:30；
- **长休息可折叠**：午休 110 分钟、晚餐 70 分钟压成一条 12pt 的"午休/晚餐"标记，省出空间；
- 列宽：7 天 ≈ 48pt；隐藏周日 ≈ 56pt；周六也隐藏 ≈ 67pt（课名能多放两个字）；
- 课名 2 行（9pt），地点/教师放详情；重叠自动并排；非本周淡显；活动画成底部细条；
- 点格子 → 编辑卡；点某天标题 → 单日放大（时间轴更宽，可拖拽改时间）。

![二维周网格：纵轴真实时间，8:30 的物理实验不强行对齐](mock/week-grid.png)

**备用：方格流**（设置里可切，不是默认）

- 7 行 × 若干 70×56 方块，只显示课名 + 时间；
- 完全不依赖坐标轴，适合"扫一眼这周有什么课"；
- 保留它是因为 380 里它确实更宽松，但不作为主形态——避免变成"一课一方块、还得滑"。

![备用：周方格流](mock/week-squares.png)

### 9.2 时间轴可调

| 可调项 | 入口 | 效果 |
|---|---|---|
| 一天显示范围 | 网格上下拖 / 设置 | 07:30–22:00 变 08:00–21:00 |
| 长休息折叠 | 设置 → 显示 | 午休/晚餐压成标记，多出 ~25% 高度 |
| 缩放 | 捏合 / 密度按钮 | 紧凑/舒适 |
| 节次表 | 设置 → 作息 | 改起止、增删节、多套（本部/校区/夏季） |
| 单节课时间 | 点格子 → 时间 | 按节次 ↔ 按钟点 切换 |
| 学期日历 | 学期设置 | 第一周开始日 / 每周起始日 / 总周数，改完周次与日期全部重算 |

改作息时：`periods` 类型的课自动跟着变；`clock` 类型的课不动（它本来就不规整）。

### 9.3 不规整的视觉语言

| 状态 | 表现 |
|---|---|
| 常规（按节次） | 左色条 + 正常圆角 |
| 偏轴（钟点与节次对不上） | 左色条变虚线 + 时间文字橙色 + 小角标"偏轴" |
| 与别人重叠 | 并排 + 细分割线（不遮字） |
| 非本周 | 35% 透明 + 虚线框 |
| 临时调课 | 角标"调"；停课划线；补课虚线 |
| 活动 | 紫色虚线边 + "活动"角标 |

### 9.4 编辑（都在面板内，内联卡片）

| 操作 | 结果 |
|---|---|
| 点方块 | 下方展开编辑卡：课名/教师/地点/周次/颜色/时间 |
| 时间 | 两个模式：按节次（1–12 选择器）/ 按钟点（时间选择器） |
| 拖格子（网格） | 改时间；松手问"仅本周 / 此后 / 整门" |
| 拉边缘 | 改节数/时长 |
| 长按 | 快捷菜单：复制、隐藏、改色、删除 |
| 周次 | 1–20 方格 + 文本框双向同步（`1-8,10-16(单)`） |
| 冲突 | 允许并存，编辑卡里列冲突对象 |

### 9.5 临时调整层

`SessionOverride`：停课 / 调课 / 补课，按日期存，不动模板；导出 ICS 时展开。

### 9.6 学期与周次（回答你的三个问题）

| 设置 | 默认 | 说明 |
|---|---|---|
| 一学期几周 | **20 周** | 1…30 可改；周次选择器的上限；调大不丢数据 |
| 第一周从哪天开始 | 从学期码推断：秋季 ≈ 9 月第一个周一；春季 ≈ 2 月最后一个周一 | **第一次导入时弹一次确认**，显示"第 1 周 9/1–9/7"；可手动改 |
| 每周从周几开始 | **周一** | 可选周日；只影响分栏顺序与"本周"边界，不影响周次编号 |
| 学期结束 | 自动 = 第一周开始 + 周数×7 − 1 | 只读展示 |

课程周次编辑（点方块 → 编辑卡）：

```
周次   第 [ 1 ] 周  →  第 [16] 周     ☐ 单周  ☐ 双周
       [更多]  自定义：1-8,10-16(单)
```

- 默认就是"起始周 / 结束周"两个 stepper，覆盖 90% 场景；
- 单双周、离散周、多段周放"更多"里，文本框与方格双向同步；
- 校验：起始 ≤ 结束，范围落在 `1...weekCount`；超出只警告不丢数据；
- 展示：`1–16 周`、`1–16 周（单）`、`1,3,5–9 周`。

### 9.7 作息表：节数、课间、放学

编辑的是 `PeriodProfile`，不是每门课。改完所有 `periods` 课自动重算，`clock` 课不动。

```
节次   开始    结束    之后
 1    08:00   08:45   课间 10 分钟
 2    08:55   09:40   课间 20 分钟
 3    10:00   10:45   课间 10 分钟
 4    10:55   11:40   午休 110 分钟
 5    13:30   14:15   课间 10 分钟
 …
 9    18:20   19:05   课间 0 分钟   ← 晚上两小节之间不休息
10    19:05   19:50   课间 10 分钟
11    20:00   20:45   课间 0 分钟
12    20:45   21:30   **放学**      ← 不是课间
```

- **节数**：默认 12，1…16 可增删；删掉的节如果被课程引用，先提示再改；
- **每节起止**：5 分钟粒度，可单节微调，也可"从第 N 节起整体 +5 分钟"；
- **课间**：相邻两节的空隙，改它默认顺延后面所有节（有开关可只改这一段）；
- **放学**：最后一节结束就是放学，**编辑器和时间轴都不给它加"休息"块**；时间轴到这儿就结束（最多留一点视觉留白）；
- **午休/晚餐**：长空隙可命名，显示在时间轴上，但不算"课间"；
- **多套作息**：本部/校区/夏季各一套，学期选一套；有"恢复官方表"。

![课表设置：学期周数 / 第一周 / 每周起始日 / 显示开关 / 作息表（最后一格是"放学"，不是课间）](mock/settings.png)

### 9.8 显示开关

| 开关 | 默认 | 行为 |
|---|---|---|
| 显示非本周课程 | **开** | 淡显（35% + 虚线）；关掉就完全不画，周视图更干净 |
| 显示周六 | **开** | 关掉后整列隐藏；若当天有课，底部提示"周六有 2 节，已隐藏 [显示]" |
| 显示周日 | **关** | 同上 |

三个开关存在 `DisplaySettings`，全局生效（不随学期变）；改动立即重绘，不用重新导入。

---

## 10. 颜色

- `colorKey = 归一化课名`，`index = stableHash % 12` → 同名同色、跨学期稳定；
- 撞色 + 黄金角扰动；
- 浅色/深色两套色板；文字颜色按相对亮度算；
- 手改色存 `colorIndex`，同步不覆盖；
- 状态（偏轴/非本周/冲突/调课）用形状+文字，不只靠颜色；
- 高对比开关。

---

## 11. 活动

- `ScheduleEvent`：一次性 / 每周 / 按周次 / 全天；`semesterID = nil` 表示长期；
- 与课程共用主网格/备用方格流，紫色虚线样式；
- 提醒：`UNUserNotificationCenter`，只排未来 7 天；
- 导出 ICS；可选 EventKit（后续）。

---

## 12. 面板信息架构

```
[课表]  ← 主面板新增入口（与"站点/体检"并列）

未登录：
┌ 课表 ─────────────────────┐
│ 第 10 周 · 11/03–11/09    │
│ ┌───────────────────────┐ │
│ │    [ CAS 登录页 ]      │ │  ← 网页，账号已填好
│ │  扫码 / 密码 / 验证码   │ │
│ │  都由你在这儿完成       │ │
│ └───────────────────────┘ │
│ 校园网 ✓ · 规则模式 ✓      │
└───────────────────────────┘

已登录：
┌ 课表 ─────────────────────┐
│ 第 10 周   6 天   同步     │
│  一  二  三  四  五  六    │
│  ██  ██  ██  ██  ██  ██   │
│  ██  ██      ██  ██       │
│ 下一节 13:30 大学英语      │
│ [导入/更新] [＋活动]       │
└───────────────────────────┘
```

- **登录页在面板里**；只有它崩/挤到没法用时，才开"只给登录用"的独立窗口（唯一例外）；
- 网格、编辑、预览永远在面板，不开窗口；
- 编辑卡从底部滑入，替代弹窗。

### 12.1 下一节课 & 开机提醒

**面板里**：顶部一行"下一节 13:30 大学英语 · 外语楼302（还有 35 分钟）"，点一下进日视图。

**通知**（你要的"刚开机提醒"）：

| 项 | 做法 |
|---|---|
| 触发点 | App 启动（开机自启已开）、从睡眠唤醒（`NSWorkspace.didWakeNotification`）；**不轮询** |
| 算什么 | 今天剩下的课（先按本周筛选，再套临时调整），取最近一节；活动默认不算 |
| 条件 | 开关开 + 有通知权限 + 距开课 ≤ 6 小时 + 今天这一节没提醒过 |
| 文案 | "今天下一节 **13:30 大学英语** · 外语楼302（还有 35 分钟）" |
| 没课 | 不打扰（可选"今天没课了"，默认关） |
| 去重 | `yyyy-MM-dd + meetingID` 存 UserDefaults，重启不重复 |
| 权限 | 沿用 `Notifier.requestAuthorizationIfNeeded()`；首次开启开关时请求 |

---

## 13. 里程碑（v0.4）

| 阶段 | 内容 | 验收 | 估时 |
|---|---|---|---|
| **M0 验证** | ① 380×520 面板里 WKWebView 打开 CAS/课表页，登录后停 30 分钟不崩；② 账号预填生效；③ 用 Cookie 拉 `cxxszhxqkb.do` 得到 JSON；④ 密码是否有微信二次验证（你操作） | 一份验证记录；决定登录放面板还是独立窗 | 1–2 天 |
| **M1 数据/时间轴** | 模型、周次解析、`YPSJDD` 解析、`PeriodProfile`、`TimeAxis`（分钟↔y、长休息折叠、重叠分列）、存储 | 单测全绿；假数据能画网格 | 3–4 天 |
| **M2 网页登录+导入** | 面板 WebView + 账号预填 + 响应捕获 + Cookie + 原生同步 + 预览 + 提交 | 真机：打开→登录→导入 | 3–4 天 |
| **M3 编辑/设置** | 内联编辑、拖拽、**起止周 / 学期日历 / 作息表（节数·课间·放学）/ 显示开关**、三方合并、快照/撤销、学期管理 | 改完再同步不丢；冲突可解；改作息后课表重算正确 | 6–7 天 |
| **M4 活动/提醒** | 事件、编辑器、**开机/唤醒"下一节"通知**、ICS | 能加活动；开机收到一次准确提醒 | 3–4 天 |
| **M5 打磨** | 网格/方格流切换、颜色、三语、无障碍、隐私、文档 | `make ci` 绿 | 3 天 |

合计 **19–23 人日**。M0 之后可砍 M3/M4 先上"只读 + 导入 + 同步"。

---

## 14. 风险

| 风险 | 概率 | 影响 | 对策 |
|---|---|---|---|
| **WKWebView 在面板里崩** | 中高 | 高 | M0 先验；退"只给登录用"的独立窗（唯一例外）；主界面不受影响 |
| 380 里的 CAS 页太挤 | 高 | 中 | 注入 CSS 收掉背景/提示；或退独立登录窗；不影响导入 |
| 预填被页面改版打断 | 中 | 低 | 只填 `#un`，失败就静默；用户手输 |
| 教务接口改字段 | 中 | 中 | 解析容错 + 导入体检 + 保留原始 JSON |
| 380 网格太密 | 中 | 中 | 隐藏周末 / 密度切换 / 方格流备用 |
| 同步覆盖手改 | 中 | 高 | 三方合并 + 快照 + 撤销 |
| 隐私（Cookie/课表） | 低 | 高 | 0600/Keychain、日志脱敏、扫描脚本 |
| 双份 App/App-Compat | 中 | 低 | 逻辑下沉，UI 双份清单 |

---

## 15. 测试与隐私

- 单测：周次表达式、起止周校验、`YPSJDD` 多段、时间轴换算（分钟/节次/偏轴）、重叠分列、合并矩阵、配色稳定、ICS；
- 作息：节数增删、课间顺延、**最后一节之后不产生"休息"块**、跨午休的时间轴；
- 显示：周日隐藏但有课时的提示、非本周开关；
- 提醒：开机只发一次、同一天不重复、无课不发；
- 夹具全合成（张三/数据结构/逸夫楼101），真实响应只放 `/tmp`，验完删；
- 登录/预填用手工验收清单（无法自动化）；
- 日志不出现 Cookie、密码、课程名；诊断导出不含课表。

---

## 16. 不做

抢课、成绩/考试（后续可复用会话）、**原生扫码协议、验证码识别/代填、自动提交登录**、后台轮询、云同步。独立窗口只允许"登录"这一个例外。

---

## 17. 需要你拍板

1. **登录页放面板**：如果 380 里太挤/崩，允许"只给登录开一个独立窗口"吗？（我按"允许、唯一例外"写的）
2. **预填时机**：我按"不主动切 tab，你点密码登录时自动填"写；要不要改成"一进来就切到密码 tab"？我倾向前者——扫码的人直接扫，密码的人自己点一下就有账号。
3. **网格默认几天**：7 天，还是默认隐藏周日（6 天，列更宽）？我按"周日隐藏、周六显示"写的。
4. **方格流**：只放设置里当备用，可以吗？

以下默认值先按表写进方案，觉得不对再说：

| 项 | 默认值 |
|---|---|
| 一学期几周 | **20 周**（可改 1–30） |
| 第一周从哪天开始 | 从学期码推断（秋 9 月第一个周一 / 春 2 月最后一个周一），**导入时确认一次** |
| 每周从周几开始 | **周一**（可选周日） |
| 显示 | 非本周**淡显**、周六**显示**、周日**隐藏**（有课会给提示） |
| 开机提醒 | **开**，只在 6 小时内有课时发一次 |
| 预填 | 只填账号，不填密码、不提交 |

---

## 18. 验证产物

- [二维周网格](mock/week-grid.png)：主视图，纵轴真实时间、8:30 偏轴课
- [周方格流](mock/week-squares.png)：备用视图
- [单日真时间轴](mock/day-axis.png)：含 8:30 偏轴课、重叠并排
- [课表设置](mock/settings.png)：学期日历 + 显示开关 + 作息表（含"放学"）
- [CAS 登录页 @380](mock/cas-380.png)：真实页面塞进面板的样子（说明为什么不做网页登录）

![CAS 登录页在 380 宽下](mock/cas-380.png)

## 附录：抓真实响应（M0）

1. 校园网/公网均可，浏览器打开课表 URL → 登录（扫码最快）；
2. DevTools → Network → 过滤 `cxxszhxqkb` → 切周触发；
3. 右键 → Copy as cURL；响应存 `/tmp/jlu.json`；
4. 用最小脚本核对字段；
5. 验完删除，别 `git add`。

## 参考

- 作息表：<http://jwc.jlu.edu.cn/sksj.htm>
- 参考实现（GPL，仅行为参考）：<https://github.com/JFyuhong/JLU_schedule>
- 小爱适配：<https://github.com/Temsys-Shen/AiScheduleForNewJLU>
- ClassIsland 时间表模型：<https://docs.classisland.tech/app/profile/>
- ICS：<https://datatracker.ietf.org/doc/html/rfc5545>

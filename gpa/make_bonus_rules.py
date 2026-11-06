# -*- coding: utf-8 -*-
"""生成软件工程 25 届推免加分细则（按用户提供的图片/文字表）。

只做软件学院；不加其他学院；图片未覆盖的类别不编分值。
"""
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

HERE = Path(__file__).parent

POINTS = {
    "A": (0.4, 0.2, 0.1),
    "B": (0.2, 0.1, 0.05),
    "B*": (0.2, 0.1, 0.05),
    "C": (0.1, 0.05, 0.02),
}

# 25 届图片“计算机类学科竞赛列表”13 项；官方等级用《学科竞赛体系（2022）》XLSX 辅助匹配
CS13 = [
    ("ACM-ICPC国际大学生程序设计竞赛", "B"),
    ("中国大学生服务外包创新创业大赛", "B"),
    ("中国高校计算机大赛（大数据挑战赛）", "B"),
    ("CCSP大学生计算机系统与程序设计竞赛", "C"),
    ("全国大学生物联网设计竞赛", "C"),
    ("CCPC中国大学生程序设计竞赛", "C"),
    ("全国大学生信息安全竞赛", "B*"),
    ("全国大学生信息安全竞赛（信息安全作品赛；创新实践能力赛）", "C"),
    ("中国高校计算机大赛（团体程序设计天梯赛/移动应用创新赛/网络技术挑战赛/人工智能创意赛）", "B"),
    ("中国高校计算机大赛（微信小程序开发赛）", "C"),
    ("全国大学生数学建模竞赛", "B"),
    ("美国大学生数学建模竞赛", "C"),
    ("全国高校密码数学挑战赛", "C"),
    ("全国大学生数学竞赛", "B"),
]

L = []
L.append("# 软件工程 25 届推免加分细则（按你给的图片）")
L.append("")
L.append("> **请你核对**：这是按你提供的 25 届软件加分细则图片整理的；图片识别可能有误，分值和名单以原图/学院文件为准。")
L.append("> 只做软件学院；没有其他学院细则；图片没覆盖的类别不编分值。")
L.append("")
L.append("## 0. 上限与累计")
L.append("")
L.append("- 同类成果不累计，取代表作最高分；五大类别之间可累加；**总分上限 0.4 GPA**。")
L.append("- 论文必须**第一作者**，第一单位**吉林大学软件学院**；论文/竞赛需答辩、学院专家认定。")
L.append("- 竞赛只认国家级/国际级；A/B/C 类按《吉林大学本科学生学科竞赛体系（2022）》。")
L.append("- 材料截止日期：以当年学院通知为准（图片未写具体日期）。")
L.append("")
L.append("## 1. 竞赛加分")
L.append("")
L.append("| 等级 | 国家级一等奖/金奖 | 国家级二等奖/银奖 | 国家级三等奖/铜奖 |")
L.append("| --- | ---: | ---: | ---: |")
for cls in ["A", "B", "C"]:
    p = POINTS[cls]
    L.append(f"| {cls} 类 | {p[0]:.2f} | {p[1]:.2f} | {p[2]:.2f} |")
L.append("")
L.append("**队伍规则**：每组不足 6 人认定实际获奖人；≥6 人只认定前 6 人，每人加分相同；国际/洲际赛等同国家级；设特等奖的赛事按“特等对一等”顺延；排名以证书为准，无个人成绩的按贡献+指导教师意见排序。")
L.append("")
L.append("**非计算机类**：A/B/C 类奖项对应分值**减半**（A 类国一 0.2、B 类国一 0.1、C 类国一 0.05）。")
L.append("")
L.append("### 计算机类学科竞赛 13 项（图片原文）")
L.append("")
L.append("| # | 竞赛 | 等级（辅助匹配） | 国一 | 国二 | 国三 |")
L.append("| ---: | --- | --- | ---: | ---: | ---: |")
for i, (name, cls) in enumerate(CS13, 1):
    p = POINTS[cls]
    L.append(f"| {i} | {name} | {cls} | {p[0]:.2f} | {p[1]:.2f} | {p[2]:.2f} |")
L.append("")
L.append("> 等级列是我用官方《学科竞赛体系（2022）》XLSX 辅助匹配的，**图片本身没写 A/B/C**；请你重点核对。原图第 9 项含天梯/移动/网络/AI/微信小程序，微信小程序为 C，本表拆成两行。")
L.append("")
L.append("## 2. 科研成果")
L.append("")
L.append("| 项目 | 加分对象 | 分值 | 条件 |")
L.append("| --- | --- | ---: | --- |")
L.append("| 大创国家级优秀结题 | 负责人 | 0.10 | 排名与立项、中期、结题一致 |")
L.append("| 大创国家级优秀结题 | 第二名 | 0.05 | 同上 |")
L.append("| CELL/NATURE/SCIENCE | 第一作者 | 0.40 | 第一单位吉林大学软件学院，答辩 |")
L.append("| CCF-A 期刊 / CCF-A 会议长文 / CCF-B 会议最佳论文或最佳学生论文 | 第一作者 | 0.20 | 同上 |")
L.append("| CCF-B 期刊 / 中科院一区 / CCF-C 会议最佳论文或最佳学生论文 | 第一作者 | 0.10 | 同上 |")
L.append("| CCF-C 期刊 / CCF-B 会议长文 / 中科院二区 / 计算机学报、软件学报 | 第一作者 | 0.05 | 同上 |")
L.append("| 影响因子非 0 的 SCI 期刊 / CCF-C 会议长文 / 中国科学：信息科学等 | 第一作者 | 0.02 | 同上 |")
L.append("| EI 检索期刊 | 第一作者 | 0.01 | 同上 |")
L.append("")
L.append("## 3. 图片未覆盖的类别")
L.append("")
L.append("- 图片只有“科研成果”和“竞赛获奖”两张表；**参军入伍、志愿服务、国际组织实习**没有给分值。")
L.append("- 这三类按学校相关部门认定；在拿到学校《素质类项目加分指导意见》前，不填具体分数。")
L.append("- 体育竞赛、艺术竞赛也不在图片里，按学校相关部门认定，不套用学科竞赛表。")
L.append("")
L.append("## 4. 请你核对")
L.append("")
L.append("- [ ] 13 项计算机类竞赛名单。")
L.append("- [ ] A/B/C 等级（官方 XLSX 辅助匹配：ACM/数学建模/服务外包/中国高校计算机大赛/数学竞赛 = B；CCSP/物联网/CCPC/美赛/密码 = C；信息安全 = B*；信息安全作品赛 = C；微信小程序 = C）。")
L.append("- [ ] 非计算机类减半的适用范围。")
L.append("- [ ] 论文分区/CCF 等级对应。")
L.append("- [ ] 图片里是否还有“参军/志愿/国际组织”的页；目前只看到科研/竞赛两张表。")
L.append("")
L.append("## 5. 来源")
L.append("")
L.append("- 你提供的 25 届软件加分细则图片（科研/竞赛表、竞赛名单）")
L.append("- `jingsai_tixi.xlsx`：吉林大学本科学生学科竞赛体系（2022，官方）——仅用于等级辅助匹配")
L.append("")

(HERE / "BONUS_RULES.md").write_text("\n".join(L), encoding="utf-8")

BLUE = "0D4F8B"
thin = Side(style="thin", color="DCE5EF")
border = Border(left=thin, right=thin, top=thin, bottom=thin)


def head(ws, n):
    for c in range(1, n + 1):
        cell = ws.cell(row=1, column=c)
        cell.font = Font(name="PingFang SC", bold=True, color="FFFFFF", size=10.5)
        cell.fill = PatternFill("solid", fgColor=BLUE)
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        cell.border = border
    ws.row_dimensions[1].height = 28


def body(ws, n, wrap=()):
    for r in range(2, ws.max_row + 1):
        for c in range(1, n + 1):
            cell = ws.cell(row=r, column=c)
            cell.font = Font(name="PingFang SC", size=10)
            cell.border = border
            cell.alignment = Alignment(vertical="center", wrap_text=(c in wrap))


wb = Workbook()

ws = wb.active
ws.title = "竞赛13项"
ws.append(["序号", "竞赛", "等级（辅助匹配）", "国一", "国二", "国三"])
for i, (name, cls) in enumerate(CS13, 1):
    p = POINTS[cls]
    ws.append([i, name, cls, p[0], p[1], p[2]])
head(ws, 6)
body(ws, 6, (2,))
for i, w in enumerate([6, 60, 14, 7, 7, 7], 1):
    ws.column_dimensions[get_column_letter(i)].width = w
ws.freeze_panes = "A2"

ws2 = wb.create_sheet("竞赛分值")
ws2.append(["等级", "国一", "国二", "国三", "说明"])
for cls in ["A", "B", "B*", "C"]:
    p = POINTS[cls]
    ws2.append([cls, p[0], p[1], p[2], "B*视同B类" if cls == "B*" else ""])
ws2.append(["非计算机类（减半）", "", "", "", "A:0.2/0.1/0.05；B:0.1/0.05/0.025；C:0.05/0.025/0.01"])
head(ws2, 5)
body(ws2, 5, (5,))
for i, w in enumerate([22, 8, 8, 8, 60], 1):
    ws2.column_dimensions[get_column_letter(i)].width = w

ws3 = wb.create_sheet("科研")
ws3.append(["项目", "加分对象", "分值", "条件"])
for row in [
    ("大创国家级优秀结题", "负责人", 0.1, "排名与立项、中期、结题一致"),
    ("大创国家级优秀结题", "第二名", 0.05, "同上"),
    ("CELL/NATURE/SCIENCE", "第一作者", 0.4, "第一单位吉林大学软件学院，答辩"),
    ("CCF-A期刊/CCF-A会议长文/CCF-B会议最佳", "第一作者", 0.2, "同上"),
    ("CCF-B期刊/中科院一区/CCF-C会议最佳", "第一作者", 0.1, "同上"),
    ("CCF-C期刊/CCF-B会议长文/中科院二区/计算机学报、软件学报", "第一作者", 0.05, "同上"),
    ("影响因子非0 SCI/CCF-C会议长文/中国科学：信息科学等", "第一作者", 0.02, "同上"),
    ("EI检索期刊", "第一作者", 0.01, "同上"),
]:
    ws3.append(row)
head(ws3, 4)
body(ws3, 4, (1, 4))
for i, w in enumerate([55, 12, 8, 38], 1):
    ws3.column_dimensions[get_column_letter(i)].width = w

ws4 = wb.create_sheet("待核对")
ws4.append(["#", "待核对项", "我的判断", "你的核对"])
for i, (a, b) in enumerate([
    ("13项名单", "按图片原文；微信小程序拆行"),
    ("A/B/C等级", "官方XLSX辅助匹配；图片未写等级"),
    ("非计算机类减半", "图片说明第4条"),
    ("论文分区/CCF", "按图片表"),
    ("参军/志愿/国际组织", "图片未覆盖，暂不列分值"),
], 1):
    ws4.append([i, a, b, ""])
head(ws4, 4)
body(ws4, 4, (2, 3))
for i, w in enumerate([5, 26, 70, 20], 1):
    ws4.column_dimensions[get_column_letter(i)].width = w

out = HERE / "out"
out.mkdir(exist_ok=True)
path = out / "软件工程25届_加分细则.xlsx"
wb.save(path)
print("saved", path, "and BONUS_RULES.md")

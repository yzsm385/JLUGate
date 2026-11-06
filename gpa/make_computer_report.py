# -*- coding: utf-8 -*-
"""生成计算机科学与技术专业的课程表 Excel 与核对说明。"""
import json
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

HERE = Path(__file__).parent
raw = (HERE / "data" / "computer-science-2022.js").read_text(encoding="utf-8")
DATA = json.loads(raw[raw.index("{"): raw.rindex(";")])
META, COURSES = DATA["meta"], DATA["courses"]
TOTAL = META["totalCountedCredits"]
SEM_LABEL = {1: "大一上", 2: "大一下", 3: "大二上", 4: "大二下", 5: "大三上", 6: "大三下"}

sem_credit = {}
for c in COURSES:
    sem_credit[c["sem"]] = sem_credit.get(c["sem"], 0) + c["credit"]

# ---------------- Markdown ----------------
L = []
L.append("# 计算机科学与技术专业保研计分核对（2022 版，2023 修订）")
L.append("")
L.append("## 一、核心结果")
L.append("")
L.append("| 项目 | 数值 |")
L.append("| --- | --- |")
L.append(f"| 2022 级计分课程 | **43 门 / {TOTAL:.1f} 学分** |")
L.append("| 2025 级计分课程 | **44 门 / 103.5 学分**（+国家安全教育 1 学分） |")
L.append("| 2026 届年级人数 | 350 人 |")
L.append("| 推免资格人数（前 24.9%） | 87 人，资格线 **3.380000** |")
L.append("| 实际拟推荐人数（15.7%） | **55 人** |")
L.append("| 实际最低学业 GPA | **约 3.550730**（学业第 55 名；综合排名受加分影响，可能略低） |")
L.append("| 最高学业 GPA | 3.949760 |")
L.append("")
L.append("数据来自 `2022计算机.xlsx` 的 43 门推免成绩单矩阵：43 门、102.5 学分，最后一列 GPA 与按列学分加权完全一致（宋乃钦 3.94976、武锦旗 3.89317 等）。`吉大 22级保研推免统计.xlsx` 记录 350 人、资格 87 人、实际 55 人、资格线 3.38，和矩阵第 87 名完全对上。")
L.append("")
L.append("## 二、分学期学分")
L.append("")
L.append("| 学期 | 门数 | 学分 | 占 102.5 学分 |")
L.append("| --- | ---: | ---: | ---: |")
for sem in sorted(sem_credit):
    xs = [c for c in COURSES if c["sem"] == sem]
    L.append(f"| {SEM_LABEL[sem]} | {len(xs)} | {sem_credit[sem]:.2f} | {sem_credit[sem] / TOTAL * 100:.1f}% |")
L.append(f"| **合计** | **{len(COURSES)}** | **{TOTAL:.1f}** | **100%** |")
L.append("")
L.append("## 三、逐门课程")
L.append("")
L.append("| 学期 | 代码 | 课程 | 学分 | 占推免 | 占学期 |")
L.append("| --- | --- | --- | ---: | ---: | ---: |")
for c in sorted(COURSES, key=lambda x: (x["sem"], x["code"])):
    L.append(f"| {SEM_LABEL[c['sem']]} | {c['code']} | {c['name']} | {c['credit']:.2f} | {c['credit'] / TOTAL * 100:.2f}% | {c['credit'] / sem_credit[c['sem']] * 100:.1f}% |")
L.append("")
L.append("## 四、2026 届 GPA 分布（前 55 名参考）")
L.append("")
L.append("| 名次 | 学业 GPA |")
L.append("| ---: | ---: |")
for rank, gpa in META["distribution"]:
    L.append(f"| {rank} | {gpa:.6f} |")
L.append("")
L.append("## 五、口径说明")
L.append("")
L.append("- 43 门课程就是成绩单矩阵的 43 列，包含劳动教育 2、思想政治理论课实践教学 2、企业实训 1；不含体育、军事理论/军训、大学英语Ⅰ/Ⅱ、通识公选、专业选修、毕业设计。")
L.append("- 劳动教育在矩阵里是一列 2 学分；培养方案写 2–3 学期，本表放在大一下，学期占比会略有偏差。")
L.append("- 单门课程绩点保留 1 位小数；最终 GPA 保留 6 位。旧 10 档：90+ 4.0、87–89 3.7、84–86 3.3、80–83 3.0、77–79 2.7、74–76 2.3、70–73 2.0、67–69 1.7、64–66 1.3、60–63 1.0、<60 0。")
L.append("- 2026 资格线 3.38 是第 87 名；实际名额 55 人，卡到第 55 名 3.550730。资格≠录取。")
L.append("- 2025 级在 2022 级 43 门基础上多“国家安全教育”1 学分，为 44 门 / 103.5；2026 级培养方案未发布，不适用。")
L.append("- 与软件工程对比：计算机 102.5 学分、企业实训 1 学分（矩阵明确计入）；软件 97.5 学分、企业实训 1.5 学分待确认。")
L.append("")
L.append("## 六、数据来源")
L.append("")
L.append("- `2022计算机.xlsx`：2026 届推免成绩单矩阵（43 门 / 102.5 学分）")
L.append("- `吉大 22级保研推免统计.xlsx`：年级人数、资格/实际人数、资格线")
L.append("- `计算机科学与技术学院本科培养方案2022版（2023年修订）.docx`：课程学期")
L.append("- `2023计算机.xlsx`：同结构，2023 级参考")
L.append("")

(HERE / "COMPUTER_REVIEW.md").write_text("\n".join(L), encoding="utf-8")

# ---------------- Excel ----------------
BLUE = "0D4F8B"
GREEN = "E8F5EE"
thin = Side(style="thin", color="DCE5EF")
border = Border(left=thin, right=thin, top=thin, bottom=thin)


def header(ws, n):
    for c in range(1, n + 1):
        cell = ws.cell(row=1, column=c)
        cell.font = Font(name="PingFang SC", bold=True, color="FFFFFF", size=10.5)
        cell.fill = PatternFill("solid", fgColor=BLUE)
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        cell.border = border
    ws.row_dimensions[1].height = 26


def body(ws, rows, n):
    for r in range(2, rows + 1):
        for c in range(1, n + 1):
            cell = ws.cell(row=r, column=c)
            cell.font = Font(name="PingFang SC", size=10)
            cell.border = border
            cell.alignment = Alignment(vertical="center", wrap_text=(c == 3))


wb = Workbook()
ws = wb.active
ws.title = "课程明细"
ws.append(["学期", "阶段", "课程代码", "课程名称", "类型", "学分", "占推免总学分", "占本学期"])
for c in sorted(COURSES, key=lambda x: (x["sem"], x["code"])):
    ws.append([c["sem"], SEM_LABEL[c["sem"]], c["code"], c["name"], c["type"], c["credit"],
               c["credit"] / TOTAL, c["credit"] / sem_credit[c["sem"]]])
header(ws, 8)
body(ws, ws.max_row, 8)
for r in range(2, ws.max_row + 1):
    ws.cell(row=r, column=7).number_format = "0.00%"
    ws.cell(row=r, column=8).number_format = "0.0%"
for i, w in enumerate([7, 8, 12, 38, 7, 7, 14, 12], 1):
    ws.column_dimensions[get_column_letter(i)].width = w
ws.freeze_panes = "A2"
ws.auto_filter.ref = f"A1:H{ws.max_row}"

ws2 = wb.create_sheet("学期汇总")
ws2.append(["学期", "阶段", "门数", "学分", "占推免总学分"])
for sem in sorted(sem_credit):
    ws2.append([sem, SEM_LABEL[sem], sum(1 for c in COURSES if c["sem"] == sem), sem_credit[sem], sem_credit[sem] / TOTAL])
ws2.append(["合计", "", len(COURSES), TOTAL, 1.0])
header(ws2, 5)
body(ws2, ws2.max_row, 5)
for r in range(2, ws2.max_row + 1):
    ws2.cell(row=r, column=5).number_format = "0.0%"
for i, w in enumerate([7, 8, 8, 9, 14], 1):
    ws2.column_dimensions[get_column_letter(i)].width = w

ws3 = wb.create_sheet("2026推免")
rows3 = [
    ["项目", "数值"],
    ["年级人数", 350],
    ["资格人数", 87],
    ["资格线 GPA", 3.38],
    ["资格比例", 87 / 350],
    ["实际拟推荐", 55],
    ["实际比例", 55 / 350],
    ["实际最低 GPA", 3.55073],
    ["最高 GPA", 3.94976],
]
for r in rows3:
    ws3.append(r)
header(ws3, 2)
body(ws3, ws3.max_row, 2)
ws3.cell(row=4, column=2).number_format = "0.000000"
ws3.cell(row=5, column=2).number_format = "0.0%"
ws3.cell(row=7, column=2).number_format = "0.0%"
ws3.cell(row=8, column=2).number_format = "0.000000"
ws3.cell(row=9, column=2).number_format = "0.000000"
ws3.column_dimensions["A"].width = 22
ws3.column_dimensions["B"].width = 14

ws4 = wb.create_sheet("绩点换算")
conv = [
    ("90–100", 4.0, "满绩档"), ("87–89.9", 3.7, "89.9 仍为 3.7，被卡绩"),
    ("84–86.9", 3.3, ""), ("80–83.9", 3.0, ""), ("77–79.9", 2.7, ""),
    ("74–76.9", 2.3, ""), ("70–73.9", 2.0, ""), ("67–69.9", 1.7, ""),
    ("64–66.9", 1.3, ""), ("60–63.9", 1.0, ""),
    ("60 以下", 0, "挂科"),
]
ws4.append(["百分制", "课程绩点", "说明"])
for r in conv:
    ws4.append(r)
header(ws4, 3)
body(ws4, ws4.max_row, 3)
ws4.column_dimensions["A"].width = 14
ws4.column_dimensions["B"].width = 10
ws4.column_dimensions["C"].width = 34

ws5 = wb.create_sheet("说明")
lines = [
    ("计算机科学与技术专业（2022 版，2023 修订）推免计分表", True),
    ("", False),
    ("43 门课 / 102.5 学分，来自 2026 届推免成绩单矩阵 2022计算机.xlsx。", False),
    ("2026：350 人，资格 87 人（3.380000），实际 55 人（最低 3.550730）。", False),
    ("企业实训 1 学分在矩阵中，计入；体育/军事/英语Ⅰ/Ⅱ/公选/选修/毕业设计不计入。", False),
    ("单门绩点 1 位小数，最终 GPA 6 位小数；旧 10 档换算。", False),
    ("劳动教育 2 学分在矩阵中为一列，本表放在大一下（培养方案写 2–3 学期）。", False),
]
for i, (text, bold) in enumerate(lines, 1):
    cell = ws5.cell(row=i, column=1, value=text)
    cell.font = Font(name="PingFang SC", size=12 if i == 1 else 10.5, bold=bold, color=BLUE if bold else "333333")
ws5.column_dimensions["A"].width = 110

out = HERE / "out"
out.mkdir(exist_ok=True)
path = out / "计算机2022_课程学分表.xlsx"
wb.save(path)
print("saved", path, "and COMPUTER_REVIEW.md")

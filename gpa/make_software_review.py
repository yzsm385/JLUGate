# -*- coding: utf-8 -*-
"""生成软件工程 2022 级官方 40 门科目清单（MD + Excel）。"""
import json
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

HERE = Path(__file__).parent
raw = (HERE / "data" / "software-engineering-2022.js").read_text(encoding="utf-8")
DATA = json.loads(raw[raw.index("{"): raw.rindex(";")])
META, ALL = DATA["meta"], DATA["courses"]
COURSES = [c for c in ALL if c["count"]]
TOTAL = sum(c["credit"] for c in COURSES)
SEM_LABEL = {1: "大一上", 2: "大一下", 3: "大二上", 4: "大二下",
             5: "大三上", 6: "大三下", 7: "大四上", 8: "大四下"}
sem_credit = {}
for c in COURSES:
    sem_credit[c["sem"]] = sem_credit.get(c["sem"], 0) + c["credit"]

assert len(COURSES) == 40, len(COURSES)
assert abs(TOTAL - 95.5) < 1e-9, TOTAL

L = []
L.append("# 软件工程 2022 级保研科目（40 门 / 95.5 学分）")
L.append("")
L.append("> **请你核对**：这是按你给的 2022 级保研科目表整理的；图片识别可能有误，科目、学分、学期请以你手里的表为准。")
L.append("")
L.append("## 汇总")
L.append("")
L.append("| 项目 | 数值 |")
L.append("| --- | --- |")
L.append(f"| 计分课程 | **40 门 / {TOTAL:.1f} 学分** |")
L.append("| 劳动教育 | **不计入**（2 学分，科目表未列） |")
L.append("| 企业实训 | **计入**（1.5 学分） |")
L.append("| 2023/24 级 | 参考 **97.5**（劳动教育计入；科目表未公开，待核对） |")
L.append("| 2025 级 | 参考 **98.5**（劳动教育 + 国家安全教育 1 学分；待核对） |")
L.append("| 2026 级 | 培养方案未发布、课程体系不同，本表暂不适用 |")
L.append("")
L.append("## 分学期")
L.append("")
L.append("| 学期 | 门数 | 学分 | 占 95.5 |")
L.append("| --- | ---: | ---: | ---: |")
for sem in sorted(sem_credit):
    n = sum(1 for c in COURSES if c["sem"] == sem)
    L.append(f"| {SEM_LABEL[sem]} | {n} | {sem_credit[sem]:.2f} | {sem_credit[sem] / TOTAL * 100:.1f}% |")
L.append(f"| **合计** | **40** | **{TOTAL:.1f}** | **100%** |")
L.append("")
L.append("## 逐门课程")
L.append("")
L.append("| # | 学期 | 代码 | 课程 | 学分 | 占推免 |")
L.append("| ---: | --- | --- | --- | ---: | ---: |")
for i, c in enumerate(sorted(COURSES, key=lambda x: (x["sem"], x.get("code", ""))), 1):
    L.append(f"| {i} | {SEM_LABEL[c['sem']]} | {c.get('code','')} | {c['name']} | {c['credit']:.2f} | {c['credit'] / TOTAL * 100:.2f}% |")
L.append("")
L.append("## 说明")
L.append("")
L.append("- 计分范围：2022 级官方保研科目表 40 门；体育、军事教育、大学英语Ⅰ/Ⅱ、限选课、专业选修、通识公选、毕业设计不在内。")
L.append("- 企业实训 1.5 学分在表中，已计入；劳动教育 2 学分在 2022 级表中未列，故 2022 级排除（其他年级按规则可能计入）。")
L.append("- 单门课绩点保留 1 位小数，最终 GPA 保留 6 位；旧 10 档换算。")
L.append("- 页面提供纠正机制：每门课可切换“计入/不计入”，可添加本地课程（如 2025 级国家安全教育），并可生成报告提 issue。")
L.append("")
L.append("## 来源")
L.append("")
L.append("- 2022 级保研科目表（你提供的图片/表）")
L.append("- `jiafen2026.docx`：2026 软件学院推免加分细则（仅用于加分规则，不用于科目表）")
L.append("- `rank2026_se.pdf`：2026 学业/综合排名（GPA 3.458970 的最低线校验）")
L.append("")

(HERE / "COURSE_REVIEW.md").write_text("\n".join(L), encoding="utf-8")

BLUE = "0D4F8B"
GREEN = "E8F5EE"
thin = Side(style="thin", color="DCE5EF")
border = Border(left=thin, right=thin, top=thin, bottom=thin)

wb = Workbook()
ws = wb.active
ws.title = "40门科目"
ws.append(["序号", "学期", "课程代码", "课程名称", "类型", "学分", "占推免总学分", "占本学期"])
for i, c in enumerate(sorted(COURSES, key=lambda x: (x["sem"], x.get("code", ""))), 1):
    ws.append([i, SEM_LABEL[c["sem"]], c.get("code", ""), c["name"], c["type"], c["credit"],
               c["credit"] / TOTAL, c["credit"] / sem_credit[c["sem"]]])
for cell in ws[1]:
    cell.font = Font(name="PingFang SC", bold=True, color="FFFFFF", size=10.5)
    cell.fill = PatternFill("solid", fgColor=BLUE)
    cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    cell.border = border
for r in range(2, ws.max_row + 1):
    for col in range(1, 9):
        cell = ws.cell(row=r, column=col)
        cell.font = Font(name="PingFang SC", size=10)
        cell.border = border
        cell.fill = PatternFill("solid", fgColor=GREEN)
        cell.alignment = Alignment(vertical="center", wrap_text=(col == 4))
    ws.cell(row=r, column=7).number_format = "0.00%"
    ws.cell(row=r, column=8).number_format = "0.0%"
for i, w in enumerate([6, 8, 12, 38, 7, 7, 14, 12], 1):
    ws.column_dimensions[get_column_letter(i)].width = w
ws.freeze_panes = "A2"

ws2 = wb.create_sheet("说明")
lines = [
    ("软件工程 2022 级保研科目（40 门 / 95.5 学分）", True),
    ("", False),
    ("劳动教育 2 学分不计入；企业实训 1.5 学分计入。", False),
    ("2025 级多“国家安全教育”；2026 级培养方案未发布，暂不适用。", False),
    ("页面可切换“计入/不计入”、添加本地课程、生成报告提 issue。", False),
    ("单门绩点 1 位小数，最终 GPA 6 位；旧 10 档换算。", False),
]
for i, (text, bold) in enumerate(lines, 1):
    cell = ws2.cell(row=i, column=1, value=text)
    cell.font = Font(name="PingFang SC", size=12 if i == 1 else 10.5, bold=bold, color=BLUE if bold else "333333")
ws2.column_dimensions["A"].width = 100

out = HERE / "out"
out.mkdir(exist_ok=True)
path = out / "软件工程2022_计分判断.xlsx"
wb.save(path)
print("saved", path, "and COURSE_REVIEW.md")

# -*- coding: utf-8 -*-
"""生成课程学分表 Excel（便于核对培养方案与计分范围）。"""
import json
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

HERE = Path(__file__).parent
raw = (HERE / "data" / "software-engineering-2022.js").read_text(encoding="utf-8")
DATA = json.loads(raw[raw.index("{"): raw.rindex(";")])
META, COURSES = DATA["meta"], DATA["courses"]
TOTAL = META["totalCountedCredits"]
SEM_LABEL = {1: "大一上", 2: "大一下", 3: "大二上", 4: "大二下",
             5: "大三上", 6: "大三下", 7: "大四上", 8: "大四下"}

sem_credit = {}
sem_all = {}
for c in COURSES:
    if c["count"]:
        sem_credit[c["sem"]] = sem_credit.get(c["sem"], 0) + c["credit"]
    sem_all[c["sem"]] = sem_all.get(c["sem"], 0) + c["credit"]

BLUE = "0D4F8B"
LIGHT = "F2F7FC"
GREEN = "E8F5EE"
GREY = "F4F6F8"

thin = Side(style="thin", color="DCE5EF")
border = Border(left=thin, right=thin, top=thin, bottom=thin)
head_font = Font(name="PingFang SC", bold=True, color="FFFFFF", size=11)
head_fill = PatternFill("solid", fgColor=BLUE)
body_font = Font(name="PingFang SC", size=10.5)


def style_header(ws, ncol, row=1):
    for c in range(1, ncol + 1):
        cell = ws.cell(row=row, column=c)
        cell.font = head_font
        cell.fill = head_fill
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        cell.border = border
    ws.row_dimensions[row].height = 26


def style_body(ws, nrow, ncol, start=2):
    for r in range(start, nrow + 1):
        for c in range(1, ncol + 1):
            cell = ws.cell(row=r, column=c)
            cell.font = body_font
            cell.border = border
            cell.alignment = Alignment(vertical="center", wrap_text=(c in (4, 10)))


wb = Workbook()

# ---------------- 课程明细 ----------------
ws = wb.active
ws.title = "课程明细"
headers = ["学期", "阶段", "课程代码", "课程名称", "类型", "学分", "计入推免", "占推免总学分", "占本学期计分学分", "备注"]
ws.append(headers)
r = 2
for c in sorted(COURSES, key=lambda x: (x["sem"], 0 if x["count"] else 1)):
    ws.cell(row=r, column=1, value=c["sem"])
    ws.cell(row=r, column=2, value=SEM_LABEL[c["sem"]])
    ws.cell(row=r, column=3, value=c["code"])
    ws.cell(row=r, column=4, value=c["name"])
    ws.cell(row=r, column=5, value=c["type"])
    ws.cell(row=r, column=6, value=round(c["credit"], 4))
    ws.cell(row=r, column=7, value="是" if c["count"] else "否")
    if c["count"]:
        ws.cell(row=r, column=8, value=c["credit"] / TOTAL).number_format = "0.00%"
        ws.cell(row=r, column=9, value=c["credit"] / sem_credit[c["sem"]]).number_format = "0.0%"
    ws.cell(row=r, column=10, value=c["note"])
    if c["count"]:
        ws.cell(row=r, column=7).fill = PatternFill("solid", fgColor=GREEN)
    else:
        for col in range(1, 11):
            ws.cell(row=r, column=col).fill = PatternFill("solid", fgColor=GREY)
    r += 1

style_header(ws, 10)
style_body(ws, r - 1, 10)
for row in range(2, r):
    ws.cell(row=row, column=6).alignment = Alignment(horizontal="center")
    ws.cell(row=row, column=7).alignment = Alignment(horizontal="center")
    ws.cell(row=row, column=8).alignment = Alignment(horizontal="right")
    ws.cell(row=row, column=9).alignment = Alignment(horizontal="right")
widths = [7, 8, 12, 38, 7, 7, 9, 13, 15, 34]
for i, w in enumerate(widths, 1):
    ws.column_dimensions[get_column_letter(i)].width = w
ws.freeze_panes = "A2"
ws.auto_filter.ref = f"A1:J{r-1}"

# ---------------- 学期汇总 ----------------
ws2 = wb.create_sheet("学期汇总")
ws2.append(["学期", "阶段", "计入学分", "目录课程学分", "计分门数", "全部门数", "占推免总学分"])
for sem in range(1, 9):
    n_count = sum(1 for c in COURSES if c["sem"] == sem and c["count"])
    n_all = sum(1 for c in COURSES if c["sem"] == sem)
    ws2.append([sem, SEM_LABEL[sem], round(sem_credit.get(sem, 0), 4), round(sem_all.get(sem, 0), 4),
                n_count, n_all, (sem_credit.get(sem, 0) / TOTAL) if sem_credit.get(sem) else None])
ws2.append(["合计", "", TOTAL, round(sum(sem_all.values()), 4),
            sum(1 for c in COURSES if c["count"]), len(COURSES), 1.0])
style_header(ws2, 7)
style_body(ws2, ws2.max_row, 7)
for row in range(2, ws2.max_row + 1):
    ws2.cell(row=row, column=7).number_format = "0.0%"
    ws2.cell(row=row, column=3).number_format = "0.000"
    ws2.cell(row=row, column=4).number_format = "0.000"
for i, w in enumerate([7, 8, 11, 14, 10, 10, 14], 1):
    ws2.column_dimensions[get_column_letter(i)].width = w
ws2.freeze_panes = "A2"

# ---------------- 推免参考 ----------------
ws3 = wb.create_sheet("推免参考线")
ws3.append(["年份", "拟推荐名额", "年级人数", "名额占比", "最低学业 GPA", "前30%选拔线", "来源"])
for x in META["reference"]:
    ws3.append([x["year"], x["admitted"], x["cohort"], (x["quotaPct"] / 100) if x["quotaPct"] else None,
                x["minGpa"], x["line30"], x["source"]])
style_header(ws3, 7)
style_body(ws3, ws3.max_row, 7)
for row in range(2, ws3.max_row + 1):
    ws3.cell(row=row, column=4).number_format = "0.0%"
    ws3.cell(row=row, column=5).number_format = "0.000000"
    ws3.cell(row=row, column=6).number_format = "0.000000"
for i, w in enumerate([8, 12, 10, 10, 15, 14, 58], 1):
    ws3.column_dimensions[get_column_letter(i)].width = w

# ---------------- 绩点换算 ----------------
ws4 = wb.create_sheet("绩点换算")
ws4.append(["百分制成绩", "课程绩点", "说明"])
conv = [
    ("90–100", 4.0, "满绩档"), ("87–89.9", 3.7, "89.9 仍为 3.7，被卡绩"),
    ("84–86.9", 3.3, ""), ("80–83.9", 3.0, ""), ("77–79.9", 2.7, ""),
    ("74–76.9", 2.3, ""), ("70–73.9", 2.0, ""), ("67–69.9", 1.7, ""),
    ("64–66.9", 1.3, ""), ("60–63.9", 1.0, ""),
    ("60 以下", 0, "挂科，必修需重修且排名按第一次成绩"),
]
for a, b, c in conv:
    ws4.append([a, b, c])
style_header(ws4, 3)
style_body(ws4, ws4.max_row, 3)
for i, w in enumerate([14, 10, 46], 1):
    ws4.column_dimensions[get_column_letter(i)].width = w

# ---------------- 说明 ----------------
ws5 = wb.create_sheet("说明")
lines = [
    ("吉林大学软件学院 · 软件工程专业（2022 版培养方案）课程学分表", True),
    ("", False),
    ("计分课程：40 门，合计 95.5000 学分（2022 级官方保研科目表；劳动教育不计，企业实训计入）。", False),
    ("不计入：劳动教育、限选课、专业选修课、通识公选课、体育、军事理论、军事训练、大学英语Ⅰ/Ⅱ。", False),
    ("大学英语仅Ⅲ、Ⅳ计入学业成绩；成绩以第一次考试为准，重修成绩不参与排名。", False),
    ("综合成绩 = 学业成绩 GPA + 素质类加分（上限 0.4）。", False),
    ("软件工程专业选拔线为专业前 30%，2026 年实际拟推荐 76 人（375 人的前 20.3%），最低学业 GPA 3.458970。", False),
    ("2025 级比 2022 级多“国家安全教育”；2026 级培养方案未发布，暂不适用。", False),
    ("", False),
    ("数据来源：", True),
    ("培养方案：https://csw.jlu.edu.cn/info/1080/7353.htm", False),
    ("2026 推免细则：https://csw.jlu.edu.cn/info/1095/7937.htm", False),
    ("2026 学业成绩排名：https://csw.jlu.edu.cn/info/1095/7958.htm", False),
    ("2026 综合成绩排名：https://csw.jlu.edu.cn/info/1095/7962.htm", False),
    ("2026 拟推荐名单：https://csw.jlu.edu.cn/info/1095/7965.htm", False),
    ("2025 拟推荐名单：https://csw.jlu.edu.cn/info/1095/7357.htm", False),
    ("2024 拟推荐名单：https://csw.jlu.edu.cn/info/1095/6696.htm", False),
    ("", False),
    ("说明：微积分 AⅠ–Ⅲ（合计 10 学分）按 4/4/2 拆分；体育、大学英语、形势与政策、劳动教育按学期均分；", False),
    ("      属展示用估算，实际以教务系统课程记录为准。2025/2026 级如启用新版方案，课程可能微调。", False),
    ("      工科试验班（软件工程）执行单独方案，本表不适用。", False),
]
for i, (text, bold) in enumerate(lines, 1):
    cell = ws5.cell(row=i, column=1, value=text)
    cell.font = Font(name="PingFang SC", size=12 if i == 1 else 10.5, bold=bold, color=BLUE if bold else "333333")
ws5.column_dimensions["A"].width = 120

out = HERE / "out"
out.mkdir(exist_ok=True)
path = out / "软件工程2022_课程学分表.xlsx"
wb.save(path)
print("saved", path, path.stat().st_size, "bytes")

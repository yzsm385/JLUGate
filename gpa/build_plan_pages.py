# -*- coding: utf-8 -*-
"""从 2022–2026 主修培养方案批量 JSON 生成：
- data/plans/<年份>/<PYFADM>.js：每个专业一份课程目录
- data/plans-index.js：学院 → 专业索引
"""
import hashlib
import json
from datetime import datetime
import re
from pathlib import Path
from glob import glob

HERE = Path(__file__).parent
SRC_GLOB = str(HERE / "JLU_培养方案_*.json")
OUT = HERE / "data" / "plans"
OUT.mkdir(parents=True, exist_ok=True)

plans = []
seen = set()
for src in sorted(glob(SRC_GLOB)):
    raw = json.load(open(src, encoding="utf-8"))
    for p in raw.get("plans", []):
        pid0 = p.get("PYFADM")
        if pid0 and pid0 not in seen:
            seen.add(pid0)
            plans.append(p)

def sem_of(x, entry_year):
    """相对入学年的学期：2023-2024-1 → 1，绝不再按固定 2026 年表映射。
    没有学期字段的（英语分级/四史等）放到 0=未标注，而不是硬塞进大四。
    """
    s = (x or "").split(",")[0].strip()
    m = re.match(r"^(\d{4})-(\d{4})-([12])$", s)
    if not m:
        return 0
    start = int(m.group(1))
    term = int(m.group(3))
    n = (start - entry_year) * 2 + term
    return n if 1 <= n <= 8 else 0


def clean(s):
    return (s or "").replace("\\", "\\\\").replace("'", "\\'")


colleges = {}
written = 0
for p in plans:
    h = p.get("header") or {}
    pid = p.get("PYFADM")
    if not pid or not p.get("courses"):
        continue
    col_disp = h.get("DWDM_DISPLAY") or h.get("DWDM") or "未知学院"
    m = re.match(r"^([0-9A-Za-z]+)-(.*)$", col_disp)
    code, cname = (m.group(1), m.group(2)) if m else ("", col_disp)
    major = h.get("ZYDM_DISPLAY") or h.get("ZYDM") or "未知专业"
    plan_name = h.get("PYFAMC") or p.get("name") or (cname + major)
    total = float(h.get("ZSYQXF") or 0)
    ym = re.search(r"(20\d{2})", str(h.get("NJDM_DISPLAY") or h.get("NJDM") or ""))
    year = int(ym.group(1)) if ym else 2026

    courses = []
    for i, c in enumerate(p["courses"]):
        cr = float(c.get("XF") or 0)
        if cr <= 0:
            continue
        courses.append({
            "key": "p%03d" % i,
            "sem": sem_of(c.get("XNXQ"), year),
            "code": c.get("KCH") or "",
            "name": c.get("KCM") or "",
            "credit": cr,
            "type": c.get("KCXZDM_DISPLAY") or "",
            "note": c.get("KZM") or "",
        })
    courses.sort(key=lambda x: (x["sem"], x["name"]))
    if not courses:
        continue

    data = {
        "meta": {
            "planId": pid,
            "planName": plan_name,
            "college": cname,
            "collegeCode": code,
            "major": major,
            "totalPlanCredits": total,
            "source": "%d级主修培养方案（教务系统）" % year,
        },
        "courses": courses,
    }
    text = "window.GPA_PLAN = " + json.dumps(data, ensure_ascii=False, separators=(",", ":")) + ";\n"
    year_dir = OUT / str(year)
    year_dir.mkdir(parents=True, exist_ok=True)
    (year_dir / (pid + ".js")).write_text(text, encoding="utf-8")
    written += 1
    version = hashlib.sha1(text.encode("utf-8")).hexdigest()[:10]

    route = "plan.html?plan=%s&v=%s&y=%d" % (pid, version, year)
    if code == "55" and major == "软件工程" and year == 2026:
        route = "software.html?cohort=2026"

    colleges.setdefault(code, {"code": code, "name": cname, "majors": []})["majors"].append({
        "id": pid,
        "name": plan_name,
        "major": major,
        "year": year,
        "credits": total,
        "courses": len(courses),
        "version": version,
        "route": route,
    })

# 已有专门页的年份（软件/计算机），补进索引，供“向更早年份回滚”使用
SPECIAL = [
    ("55", "软件学院", "软件工程", 2022, "2022级软件工程（参考）", 95.5, 40, "software.html?cohort=2022"),
    ("55", "软件学院", "软件工程", 2024, "2023/24级软件工程（推算）", 97.5, 42, "software.html?cohort=2024"),
    ("55", "软件学院", "软件工程", 2025, "2025级软件工程（推算）", 98.5, 43, "software.html?cohort=2025"),
    ("21", "计算机科学与技术学院", "计算机科学与技术", 2022, "2022级计算机（矩阵）", 102.5, 43, "computer.html?cohort=2022"),
    ("21", "计算机科学与技术学院", "计算机科学与技术", 2025, "2025级计算机（矩阵+国安）", 103.5, 44, "computer.html?cohort=2025"),
]
for code, cname, major, year, name, credits, courses, route in SPECIAL:
    c = colleges.setdefault(code, {"code": code, "name": cname, "majors": []})
    exists = any(m["major"] == major and m["year"] == year for m in c["majors"])
    if not exists:
        c["majors"].append({
            "id": "special-%s-%s-%s" % (code, year, major),
            "name": name, "major": major, "year": year,
            "credits": credits, "courses": courses, "route": route, "special": True,
        })

for c in colleges.values():
    c["majors"].sort(key=lambda x: (x["major"], x["name"]))

index = {
    "meta": {
        "title": "吉林大学 2022–2026 级主修培养方案索引",
        "source": "教务系统全校方案查询（2022–2026级主修）",
        "updated": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
        "planCount": written,
    },
    "colleges": sorted(colleges.values(), key=lambda x: (x["code"] or "zzz", x["name"])),
}
(HERE / "data" / "plans-index.js").write_text(
    "window.GPA_PLAN_INDEX = " + json.dumps(index, ensure_ascii=False, separators=(",", ":")) + ";\n",
    encoding="utf-8")

print("plans written", written, "colleges", len(index["colleges"]),
      "majors", sum(len(c["majors"]) for c in index["colleges"]))

# -*- coding: utf-8 -*-
"""生成「学号前缀（专业/学院代码）→ 学院/单位」对照数据。

来源：用户 2026-11-05 提供的学号名单（代码 + 单位简称）。
用途：给 GPA/推免测算做「学号 → 学院」检索；后续按学院加载各自的培养方案。

两条口径（用户确认/要求）：
1. 简称里没写「学院 / 中心 / 院」之类的，自动补「学院」两个字；
   但「文学院 / 法学院 / 药学院」这类固定写法单独处理，避免补成「文学学院」。
2. 本科与研究生基本共用同一套专业代码，所以代码只能回答
   “这个单位有没有本科”，不能回答“某个学生是不是本科”。
   undergraduate=true  = 该代码有本科专业，可参与绩点/推免测算；
   undergraduate=false = 不招本科（行政单位、公共教学中心、继续教育、科研机构等）；
   undergraduate=null  = 待确认，不猜。

运行：python3 build_student_id_data.py
输出：data/student-id-prefixes.json
      data/student-id-prefixes.js
      out/学号前缀_学院对照.csv
"""
from __future__ import annotations

import csv
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA_DIR = HERE / "data"
OUT_DIR = HERE / "out"

# 简称没带单位后缀时，补这两个字（用户要求）
FILLER = "学院"

# 单位后缀：命中任意一个就不再补「学院」
SUFFIXES = (
    "学院", "学系", "中心", "学部", "研究院", "研究所", "办公室",
    "团委", "医院", "大学", "学校", "处", "馆", "站", "所", "部", "院", "委",
)

# 固定写法：补「学院」会把名字补错，单独列出
SPECIAL_NAMES = {
    "文学": "文学院",
    "法学": "法学院",
    "药学": "药学院",
    "商学与管理学": "商学与管理学院",
    "新闻与传播学": "新闻与传播学院",
}

CODE_RE = re.compile(r"^[0-9A-Z]{1,4}$")
TAG_RE = re.compile(r"^(.*?)\s+([A-Z])$")
PAREN_RE = re.compile(r"[（(]([^）)]*)[）)]\s*$")


def R(code, raw, kind, undergraduate, name=None, aliases=(), note=""):
    """一行原始数据。name=None 表示按规则自动补全。"""
    return {
        "code": code,
        "raw": raw,
        "name": name,
        "kind": kind,
        "undergraduate": undergraduate,
        "aliases": list(aliases),
        "note": note,
    }


# ---- 原始名单（顺序、写法照抄用户给的版本） ----
ROWS = [
    R("01", "哲学社会", "学院", True),
    R("02", "文学", "学院", True),
    R("03", "外国语言文化", "学院", True, aliases=["外国语学院"]),
    R("04", "艺术", "学院", True),
    R("05", "体育", "学院", True),
    R("06", "经济", "学院", True),
    R("07", "法学", "学院", True),
    R("08", "行政", "学院", True),
    R("09", "商学与管理学", "学院", True, note="与 35、34 可能同院不同码（本科/研究生?），待确认"),
    R("10", "数学", "学院", True),
    R("11", "物理", "学院", True),
    R("12", "化学", "学院", True),
    R("13", "生命科学", "学院", True),
    R("14", "机械科学与工程、机械与航天空航天工程", "学院", True,
      name="机械与航空航天工程学院",
      aliases=["机械科学与工程学院", "机械与航空航天工程学院"],
      note="源名单把两个院名写在同一行；「航天空航天」疑为「航空航天」笔误，按同一代码处理"),
    R("15", "汽车工程", "学院", True),
    R("16", "材料科学与工程", "学院", True),
    R("17", "交通", "学院", True),
    R("18", "生物与农业工程", "学院", True),
    R("19", "电子科学与工程", "学院", True),
    R("20", "通信工程", "学院", True),
    R("21", "计算机科学与技术", "学院", True, aliases=["计算机学院"]),
    R("22", "地球科学", "学院", True),
    R("23", "地球探测科学与技术", "学院", True),
    R("24", "建设工程", "学院", True),
    R("25", "环境与资源学院", "学院", True,
      note="与 25 新能源与环境学院同码，疑为同一单位的新旧名称"),
    R("25", "新能源与环境", "学院", True),
    R("26", "金融", "学院", None, note="全称与是否招本科待确认"),
    R("27", "公共卫生", "学院", True),
    R("28", "药学", "学院", True),
    R("29", "护理", "学院", True),
    R("30", "东北亚", "学院", True),
    R("31", "历史文化", "学院", True),
    R("32", "口腔医", "学院", True, aliases=["白求恩口腔医学院"],
      note="源名单写作「32、33 口腔医」，两码共用"),
    R("33", "口腔医", "学院", True, aliases=["白求恩口腔医学院"],
      note="源名单写作「32、33 口腔医」，两码共用"),
    R("34", "商学与管理学 A", "学院", None,
      name="商学与管理学院（A）",
      note="「A」的含义（研究生/专业学位?）待确认"),
    R("35", "商学与管理学", "学院", True, note="与 09、34 可能同院不同码，待确认"),
    R("36", "公共外交", "学院", True),
    R("37", "新闻与传播学", "学院", True),
    R("38", "考古", "学院", True),
    R("39", "马克思主义", "学院", True),
    R("40", "人工智能", "学院", True),
    R("50", "预科教育", "预科", False, note="预科，不参与本科绩点/推免"),
    R("54", "应用技术", "学院", False,
      note="按专科/高职层次处理；若也招本科请改"),
    R("55", "软件", "学院", True),
    R("60", "国际语言", "学院", False,
      note="留学生/语言进修，非本科；待确认"),
    R("65", "仪器科学与电气工程", "学院", True),
    R("70", "临床医", "学院", True,
      note="通称；与 72–77 白求恩各临床医学院的对应关系待确认"),
    R("71", "基础医", "学院", True),
    R("72", "白求恩医学部第一临床医", "学院", True,
      aliases=["白求恩第一临床医学院"], note="官方写法：白求恩第一临床医学院；与 75 可能同院不同码，待确认"),
    R("73", "白求恩医学部第二临床医", "学院", True,
      aliases=["白求恩第二临床医学院"], note="官方写法：白求恩第二临床医学院；与 76 可能同院不同码，待确认"),
    R("74", "白求恩医学部第三临床医", "学院", True,
      aliases=["白求恩第三临床医学院"], note="官方写法：白求恩第三临床医学院；与 77 可能同院不同码，待确认"),
    R("75", "白求恩第一临床医", "学院", True, note="与 72 可能同院不同码，待确认"),
    R("76", "白求恩第二临床医", "学院", True, note="与 73 可能同院不同码，待确认"),
    R("77", "白求恩第三临床医", "学院", True, note="与 74 可能同院不同码，待确认"),
    R("78", "白求恩医学部基础医", "学院", None,
      note="与 71 基础医学院重名；是否研究生代码待确认"),
    R("79", "白求恩医学部", "学部", False, note="学部机关，不直接招本科"),
    R("81", "畜牧兽医", "学院", None,
      note="与 81 动物医学学院同码；旧称/是否仍招本科待确认"),
    R("81", "动物医学", "学院", True),
    R("82", "植物科学", "学院", True),
    R("83", "军需科技", "学院", None, note="是否仍招本科待确认"),
    R("84", "农学部公共教学中心", "教学单位", False),
    R("85", "动物科学", "学院", True),
    R("87", "食品科学与工程", "学院", True),
    R("90", "创新创业教育", "教学单位", False,
      note="创新创业教育学院为教学单位，不招本科"),
    R("91", "公共外语教育", "教学单位", False),
    R("92", "公共体育教学与研究中心", "教学单位", False),
    R("93", "公共数学教学与研究中心", "教学单位", False),
    R("94", "公共物理教学与研究中心", "教学单位", False),
    R("95", "公共化学教学与研究中心", "教学单位", False),
    R("96", "公共计算机教学与研究中心", "教学单位", False),
    R("99", "团委（其他行政单位）", "行政单位", False, note="其他行政单位"),
    R("199", "本科生院", "行政单位", False),
    R("XX", "所有", "通配", None, note="通配：任意学院"),
    R("X1", "经济信息", "学院", None, note="全称与层次待确认"),
    R("X2", "工商管理", "学院", None, note="可能为 MBA/研究生层次，待确认"),
    R("X3", "软件学院珠海", "学院", False,
      note="研究生，目前不招本科（你提到可能 2027/2028 开始招，届时改 true）"),
    R("XZ27", "学生心理健康指导中心", "行政单位", False),
    R("JX", "继续教育", "继续教育", False),
    R("JX49", "莱姆顿", "学院", None,
      note="中外合作办学（莱姆顿学院）；层次待确认"),
    R("L3", "原子与分子物理研究所", "科研机构", False, note="研究所，研究生/科研"),
    R("LD", "劳动教育中心", "教学单位", False),
]


def complete_name(raw: str) -> tuple[str, str]:
    """按规则补全名称，返回 (name, 括号里的备注)。"""
    text = raw.strip()

    paren_note = ""
    m = PAREN_RE.search(text)
    if m:
        paren_note = m.group(1).strip()
        text = text[: m.start()].strip()

    tag = ""
    m = TAG_RE.match(text)
    if m:
        text = m.group(1).strip()
        tag = m.group(2)

    if text in SPECIAL_NAMES:
        name = SPECIAL_NAMES[text]
    elif text.endswith(SUFFIXES) or "学院" in text:
        # 已经带「学院」的（如「软件学院珠海」）不再补，避免「软件学院珠海学院」
        name = text
    else:
        name = text + FILLER

    if tag:
        name += f"（{tag}）"
    return name, paren_note


def build():
    entries = []
    seen_ids: set[str] = set()
    duplicates: dict[str, list[str]] = {}

    for row in ROWS:
        code = row["code"]
        if not CODE_RE.match(code):
            raise ValueError(f"代码格式不对：{code!r}")

        name, paren_note = complete_name(row["raw"])
        if row["name"]:
            name = row["name"]

        note = row["note"]
        if paren_note and paren_note not in note:
            note = f"{note}；{paren_note}" if note else paren_note

        base_id = code
        entry_id = base_id
        n = 2
        while entry_id in seen_ids:
            entry_id = f"{base_id}#{n}"
            n += 1
        seen_ids.add(entry_id)

        entry = {
            "id": entry_id,
            "code": code,
            "name": name,
            "raw": row["raw"],
            "aliases": row["aliases"],
            "kind": row["kind"],
            "undergraduate": row["undergraduate"],
            "note": note,
        }
        entries.append(entry)
        duplicates.setdefault(code, []).append(name)

    entries.sort(key=lambda e: (0, int(e["code"])) if e["code"].isdigit() else (1, e["code"]))
    duplicates = {c: names for c, names in duplicates.items() if len(names) > 1}

    uncertain = [e["code"] for e in entries if e["undergraduate"] is None]

    meta = {
        "title": "吉林大学 学号前缀 → 学院/单位 对照",
        "source": "用户提供的学号名单（2026-11-05）",
        "updated": "2026-11-05",
        "note": (
            "名单给的是学号/邮箱里的专业（学院）代码；本科与研究生基本共用同一套代码，"
            "所以代码只能判断“该单位有没有本科”，不能判断某个学生是本科还是研究生。"
        ),
        "studentIDFormat": (
            "代码(2–4位) + 入学年份(2位) + 班号(2位) + 班内序号(2位)；"
            "如 21230123 = 21 计算机、2023 级、01 班、23 号。代码在最前面，按最长匹配。"
        ),
        "suffixRule": (
            "简称未以「学院/中心/学部/研究所/团委…」结尾时自动补「学院」；"
            "文学院、法学院、药学院、商学与管理学院、新闻与传播学院为固定写法。"
        ),
        "undergraduateRule": (
            "undergraduate=true 表示该代码有本科专业，可参与绩点/推免测算；"
            "false 表示不招本科（行政单位、公共教学中心、继续教育、科研机构等）；"
            "null 表示待确认，不猜。"
        ),
        "duplicateCodes": duplicates,
        "uncertainCodes": uncertain,
        "counts": {
            "all": len(entries),
            "undergraduate": sum(1 for e in entries if e["undergraduate"] is True),
            "nonUndergraduate": sum(1 for e in entries if e["undergraduate"] is False),
            "uncertain": len(uncertain),
        },
    }

    return {"meta": meta, "entries": entries}


def write_outputs(payload):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    js = (
        "/* 由 build_student_id_data.py 生成，请勿手改。 */\n"
        "(function (root) {\n"
        "  root.STUDENT_ID_PREFIXES = "
        + json.dumps(payload, ensure_ascii=False, indent=1)
        + ";\n"
        "})(typeof window !== \"undefined\" ? window : globalThis);\n"
    )
    (DATA_DIR / "student-id-prefixes.js").write_text(js, encoding="utf-8")

    (DATA_DIR / "student-id-prefixes.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    with (OUT_DIR / "学号前缀_学院对照.csv").open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["代码", "原始简称", "补全名称", "类别", "有本科", "别名", "备注"])
        for e in payload["entries"]:
            ug = {True: "是", False: "否", None: "待确认"}[e["undergraduate"]]
            w.writerow([e["code"], e["raw"], e["name"], e["kind"], ug,
                        " / ".join(e["aliases"]), e["note"]])


if __name__ == "__main__":
    data = build()
    write_outputs(data)
    m = data["meta"]
    print(f"条目 {m['counts']['all']}｜有本科 {m['counts']['undergraduate']}｜"
          f"不招本科 {m['counts']['nonUndergraduate']}｜待确认 {m['counts']['uncertain']}")
    print("重复代码：", "、".join(m["duplicateCodes"]) or "无")
    print("待确认代码：", "、".join(m["uncertainCodes"]) or "无")

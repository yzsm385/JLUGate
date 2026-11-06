#!/usr/bin/env python3
"""gpa/research/college-rules/<code>.json → gpa/data/college-rules.js

给 plan.html 计算器用的精简数据：
- 每个学院的计分口径（哪些课默认不算 → 折叠）
- 历年推免线（lines）
- 细则/排名公示的通知链接
"""
import json
import glob
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "gpa", "research", "college-rules")
OUT = os.path.join(ROOT, "gpa", "data", "college-rules.js")

# 学院名补全（notices/name 里可能带括号说明）
# 全校统一口径标签（供 plan.html 折叠用）
EXCLUDE_KEYS = ("pe", "military", "english12", "elective", "genitive", "fourthYear")


def num(x):
    try:
        v = float(x)
        return v
    except (TypeError, ValueError):
        return None


def squeeze(v):
    """字符串压到 ~400 字（保留关键句，砍列表原文），列表最多 4 条。"""
    if isinstance(v, str):
        v = re.sub(r"\s+", " ", v).strip()
        if len(v) > 400:
            v = v[:396] + "…"
        return v
    if isinstance(v, list):
        return [squeeze(x) for x in v[:4]]
    return v


def main():
    rules = {}
    files = sorted(glob.glob(os.path.join(SRC, "*.json")))
    for path in files:
        code = os.path.basename(path)[:-5]
        try:
            with open(path, encoding="utf-8") as f:
                d = json.load(f)
        except Exception as e:  # noqa: BLE001
            print(f"skip {code}: {e}")
            continue
        scope = d.get("scope") or {}
        focus = scope.get("focus", {})
        squeeze_keys = ("summary", "english", "pe", "history", "other")
        rules[code] = {
            "name": d.get("college", ""),
            "status": d.get("status", ""),
            "summary": scope.get("summary", ""),
            "confidence": scope.get("confidence", ""),
            "appliesTo": scope.get("appliesTo", []),
            # 细分口径：plan.html 据此决定默认排除 + 折叠
            "focus": {k: squeeze(v) for k, v in focus.items()},
            "exclude": scope.get("exclude", []),
            **{k: squeeze(scope.get(k, "")) for k in squeeze_keys},
            # 历年推免线
            "lines": d.get("lines", []),
            # 细则 / 排名公示链接（取细则 kind 优先）
            "notices": [
                {"t": n.get("title", ""), "u": n.get("url", ""), "k": n.get("kind", ""),
                 "c": n.get("cohort", ""), "p": n.get("published", "")}
                for n in (d.get("notices") or [])[:12]
            ],
            "unresolved": [squeeze(u) for u in (d.get("unresolved") or [])[:4]],
        }

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("window.GPA_COLLEGE_RULES = ")
        json.dump(
            {"meta": {"updated": __import__("datetime").datetime.now().isoformat(timespec="seconds"),
                      "source": "各学院推免细则与排名公示调研（gpa/research/college-rules）",
                      "count": len(rules)}},
            f, ensure_ascii=False)
        f.write(";\nwindow.GPA_COLLEGE_RULES.rules = ")
        json.dump(rules, f, ensure_ascii=False, separators=(",", ":"))
        f.write(";\n")
    print(f"wrote {OUT}: {len(rules)} colleges")


if __name__ == "__main__":
    main()

# -*- coding: utf-8 -*-
"""校验「学号前缀 → 学院」数据与检索逻辑。

运行：python3 test_student_id.py
（Python 校验数据不变量；Node 校验 assets/student-id.js 的查询行为）
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SUFFIXES = (
    "学院", "学系", "中心", "学部", "研究院", "研究所", "办公室",
    "团委", "医院", "大学", "学校", "处", "馆", "站", "所", "部", "院", "委",
)
EXPECTED_DUP = {"25": 2, "81": 2}
EXPECTED_UNCERTAIN = {"26", "34", "78", "81", "83", "JX49", "X1", "X2", "XX"}


def check_data():
    payload = json.loads((HERE / "data/student-id-prefixes.json").read_text(encoding="utf-8"))
    entries = payload["entries"]
    assert len(entries) == 81, len(entries)

    ids = [e["id"] for e in entries]
    assert len(ids) == len(set(ids)), "id 重复"

    for e in entries:
        assert e["code"] and e["name"], e
        assert e["kind"], e
        assert e["name"].endswith(SUFFIXES) or "学院" in e["name"], e["name"]
        assert isinstance(e["undergraduate"], (bool, type(None))), e

    dup = {}
    for e in entries:
        dup[e["code"]] = dup.get(e["code"], 0) + 1
    dup = {k: v for k, v in dup.items() if v > 1}
    assert dup == EXPECTED_DUP, dup

    uncertain = {e["code"] for e in entries if e["undergraduate"] is None}
    assert uncertain == EXPECTED_UNCERTAIN, uncertain

    by_name = {e["name"] for e in entries}
    for must in ["文学院", "法学院", "药学院", "商学与管理学院", "新闻与传播学院",
                 "机械与航空航天工程学院", "软件学院", "口腔医学院"]:
        assert must in by_name, must

    # 不允许把简称补成叠字（文学学院 / 法学学院 / 药学学院）
    for bad in ["文学学院", "法学学院", "药学学院", "软件学院珠海学院"]:
        assert bad not in by_name, bad

    return payload


NODE = r"""
const assert = require("assert");
globalThis.STUDENT_ID_PREFIXES = require("./data/student-id-prefixes.json");
const idx = require("./assets/student-id.js");

function one(id) {
  const hits = idx.forStudentID(id);
  assert.strictEqual(hits.length >= 1, true, "no hit: " + id);
  return hits[0];
}
function status(id) { return idx.resolveForGPA(id).status; }

// 21 23 01 23 = 计算机（21）、2023 级、01 班、23 号
const p = idx.parse("21230123");
assert.strictEqual(p.code, "21");
assert.strictEqual(p.year, "2023");
assert.strictEqual(p.codeLength, 2);
assert.strictEqual(one("21230123").entry.name, "计算机科学与技术学院");
assert.strictEqual(status("21230123"), "ok");

assert.strictEqual(one("55230123").entry.name, "软件学院");
assert.strictEqual(status("55230123"), "ok");

// 20 是通信工程，不是 2020 年
assert.strictEqual(one("20230123").code, "20");
assert.strictEqual(one("20230123").entry.name, "通信工程学院");
assert.strictEqual(one("19230123").entry.name, "电子科学与工程学院");
assert.strictEqual(one("23230123").entry.name, "地球探测科学与技术学院");

assert.strictEqual(one("04230123").entry.name, "艺术学院"); // 04 只有艺术
assert.strictEqual(status("04230123"), "ok");
assert.strictEqual(status("25230123"), "needs-choice"); // 25 环境与资源 / 新能源
assert.deepStrictEqual(idx.resolveForGPA("25230123").options.map(e => e.name), ["环境与资源学院", "新能源与环境学院"]);
assert.strictEqual(idx.resolveForGPA("25230123", "25#2").entry.name, "新能源与环境学院");
assert.strictEqual(idx.resolveForGPA("25230123", "nope").status, "needs-choice");
assert.strictEqual(idx.candidates("25230123").length, 2);
assert.strictEqual(status("81230123"), "needs-choice"); // 81 畜牧兽医 / 动物医学
assert.strictEqual(idx.resolveForGPA("81230123", "81#2").entry.name, "动物医学学院");
assert.strictEqual(one("02230123").entry.name, "文学院");
assert.strictEqual(one("07230123").entry.name, "法学院");
assert.strictEqual(one("28230123").entry.name, "药学院");
assert.strictEqual(one("09230123").entry.name, "商学与管理学院");

assert.strictEqual(status("50230123"), "not-undergraduate"); // 预科
assert.strictEqual(status("60230123"), "not-undergraduate"); // 国际语言
assert.strictEqual(status("99230123"), "not-undergraduate"); // 团委
assert.strictEqual(status("199230123"), "not-undergraduate"); // 199 本科生院（长代码优先）
assert.strictEqual(one("199230123").code, "199");
assert.strictEqual(one("199230123").codeLength, 3);
assert.strictEqual(status("JX230123"), "not-undergraduate"); // 继续教育
assert.strictEqual(status("L3230123"), "not-undergraduate"); // 原子与分子物理研究所
assert.strictEqual(status("XZ27230123"), "not-undergraduate");

assert.strictEqual(status("JX49230123"), "needs-confirmation"); // 莱姆顿
assert.strictEqual(one("JX49230123").code, "JX49");
assert.strictEqual(one("JX49230123").codeLength, 4);
assert.strictEqual(status("X3230123"), "not-undergraduate"); // 软件学院珠海：研究生，不招本科
assert.strictEqual(status("26230123"), "needs-confirmation");
assert.strictEqual(status("XX230123"), "needs-confirmation");

assert.strictEqual(idx.normalizeCode("1"), "01");
assert.strictEqual(idx.normalizeCode("jx49"), "JX49");
assert.strictEqual(idx.normalizeID("55-230123@mails.jlu.edu.cn"), "55230123");
assert.strictEqual(idx.byCode("55")[0].name, "软件学院");

const soft = idx.search("软件").map(e => e.name);
assert.ok(soft.includes("软件学院"), soft);
assert.ok(soft.includes("软件学院珠海"), soft);
assert.strictEqual(idx.search("口腔").length, 2);
assert.strictEqual(idx.byCode("04").length, 1);
assert.strictEqual(idx.undergraduates().length, 53);
assert.strictEqual(idx.nonUndergraduates().length, 19);
assert.strictEqual(idx.uncertain().length, 9);

// 同码让用户选，选过记住
const mem = {};
globalThis.localStorage = {
  getItem: k => (Object.prototype.hasOwnProperty.call(mem, k) ? mem[k] : null),
  setItem: (k, v) => { mem[k] = String(v); },
  removeItem: k => { delete mem[k]; }
};
assert.strictEqual(idx.rememberChoice("25", "25#2"), true);
assert.strictEqual(idx.savedChoice("25"), "25#2");
const saved = idx.resolveWithSaved("25230123");
assert.strictEqual(saved.status, "ok");
assert.strictEqual(saved.entry.name, "新能源与环境学院");
assert.strictEqual(idx.rememberChoice("25", "55"), false); // 55 不属于 25
idx.forgetChoice("25");
assert.strictEqual(idx.savedChoice("25"), null);
assert.strictEqual(idx.resolveWithSaved("25230123").status, "needs-choice");

console.log("node: ok");
"""


def check_js():
    out = subprocess.run(
        ["node", "-e", NODE],
        cwd=HERE,
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        print(out.stdout)
        print(out.stderr, file=sys.stderr)
        raise SystemExit("Node 校验失败")
    print(out.stdout.strip())


if __name__ == "__main__":
    payload = check_data()
    m = payload["meta"]
    print(f"python: ok（{m['counts']['all']} 条，"
          f"本科 {m['counts']['undergraduate']} / 非本科 {m['counts']['nonUndergraduate']} / "
          f"待确认 {m['counts']['uncertain']}）")
    check_js()

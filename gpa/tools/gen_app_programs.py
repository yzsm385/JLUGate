#!/usr/bin/env python3
"""把 GPA 网页的培养方案索引（gpa/data/plans-index.js）生成 App 用的 Swift 数据。

App 要在「认出学院 + 年级」之后直接进入计算器，就必须知道该学院有哪些专业、
每个专业各年级的 plan.html / software.html 路由。这里只打包路由，不打包课程。

用法（仓库根目录）：
    python3 gpa/tools/gen_app_programs.py

生成：
    Sources/JLUGateCore/GPAPrograms.swift
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INDEX = ROOT / "gpa" / "data" / "plans-index.js"
OUT = ROOT / "Sources" / "JLUGateCore" / "GPAPrograms.swift"


def load_index() -> dict:
    text = INDEX.read_text(encoding="utf-8")
    start = text.index("{")
    end = text.rindex("};") + 1
    return json.loads(text[start:end])


def swift_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> None:
    data = load_index()
    colleges: list[tuple[str, str, list[tuple[str, list[dict]]]]] = []
    total = 0

    for college in data["colleges"]:
        by_major: dict[str, dict[int, dict]] = {}
        for plan in college["majors"]:
            by_major.setdefault(plan["major"], {})
            year = plan["year"]
            previous = by_major[plan["major"]].get(year)
            # 同一专业同一年偶尔有两套（如 2025 俄语/日语、数学强基方向）：
            # 和网页 landing 的排序一致，取课程数多的那套。
            if previous is None or plan.get("courses", 0) > previous.get("courses", 0):
                by_major[plan["major"]][year] = plan

        majors = []
        for name in sorted(by_major):
            plans = sorted(by_major[name].values(), key=lambda p: -p["year"])
            majors.append((name, plans))
            total += len(plans)
        colleges.append((college["code"], college["name"], majors))

    lines: list[str] = []
    lines.append("// 由 gpa/tools/gen_app_programs.py 从 gpa/data/plans-index.js 生成，请勿手改。")
    lines.append("// 只含「学院 → 专业 → 年级 → 计算器路由」，课程内容仍由网页按需加载。")
    lines.append("")
    lines.append("import Foundation")
    lines.append("")
    lines.append("/// 一个 GPA 计算器路由（对应网页里的一套培养方案）。")
    lines.append("public struct GPAPlan: Sendable, Equatable, Hashable, Identifiable {")
    lines.append("    public let year: Int")
    lines.append("    /// 相对 `GPALink.base` 的路径，如 `plan.html?plan=…` / `software.html?cohort=2026`")
    lines.append("    public let route: String")
    lines.append("")
    lines.append("    public var id: String { route }")
    lines.append("")
    lines.append("    public init(year: Int, route: String) {")
    lines.append("        self.year = year")
    lines.append("        self.route = route")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    lines.append("/// 同一专业跨年级的方案集合（按年份从新到旧）。")
    lines.append("public struct GPAMajor: Sendable, Equatable, Hashable, Identifiable {")
    lines.append("    public let name: String")
    lines.append("    public let plans: [GPAPlan]")
    lines.append("")
    lines.append("    public var id: String { name }")
    lines.append("")
    lines.append("    public init(name: String, plans: [GPAPlan]) {")
    lines.append("        self.name = name")
    lines.append("        self.plans = plans")
    lines.append("    }")
    lines.append("")
    lines.append("    /// 和网页 landing 一致：有入学年就取「≤ 该年级」的最近一套；")
    lines.append("    /// 没有入学年取最新一套。没有更早的方案时返回 nil，不拿更晚的顶替。")
    lines.append("    public func plan(for year: Int?) -> GPAPlan? {")
    lines.append("        guard let year else { return plans.first }")
    lines.append("        return plans.first { $0.year <= year }")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    lines.append("public enum GPAProgramDirectory {")
    lines.append(f"    /// 全库方案数（按专业 + 年级去重后）：{total}")
    lines.append(f"    public static let planCount = {total}")
    lines.append("")
    lines.append("    public static let majorsByCollege: [String: [GPAMajor]] = [")
    for code, _name, majors in colleges:
        lines.append(f'        "{code}": [')
        for major, plans in majors:
            lines.append(f'            GPAMajor(name: {swift_string(major)}, plans: [')
            for plan in plans:
                lines.append(
                    f'                GPAPlan(year: {plan["year"]}, route: {swift_string(plan["route"])}),'
                )
            lines.append("            ]),")
        lines.append("        ],")
    lines.append("    ]")
    lines.append("")
    lines.append("    public static func majors(collegeCode: String) -> [GPAMajor] {")
    lines.append("        majorsByCollege[collegeCode] ?? []")
    lines.append("    }")
    lines.append("")
    lines.append("    /// 只留「该年级及更早还有方案」的专业；年份为空时全部保留。")
    lines.append("    public static func majors(collegeCode: String, year: Int?) -> [GPAMajor] {")
    lines.append("        majors(collegeCode: collegeCode).filter { $0.plan(for: year) != nil }")
    lines.append("    }")
    lines.append("")
    lines.append("    public static func major(named name: String, collegeCode: String) -> GPAMajor? {")
    lines.append("        majors(collegeCode: collegeCode).first { $0.name == name }")
    lines.append("    }")
    lines.append("")
    lines.append("    public static func plan(collegeCode: String, major majorName: String, year: Int?) -> GPAPlan? {")
    lines.append("        major(named: majorName, collegeCode: collegeCode)?.plan(for: year)")
    lines.append("    }")
    lines.append("")
    lines.append("    public static func url(for plan: GPAPlan) -> URL? {")
    lines.append("        URL(string: plan.route, relativeTo: GPALink.base)?.absoluteURL")
    lines.append("    }")
    lines.append("}")
    lines.append("")

    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {OUT} ({len(lines)} lines, {total} plans, {len(colleges)} colleges)")


if __name__ == "__main__":
    main()

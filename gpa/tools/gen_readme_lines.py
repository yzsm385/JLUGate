#!/usr/bin/env python3
"""从 research/college-rules/*.json 生成 README 的「全校口径 + 各院推免线」汇总段落。

用法: research/.venv/bin/python tools/gen_readme_lines.py [--out out/college-lines.md]
只读 research JSON，不改动任何页面文件。research/ 不进 git，产物写到 out/ 或 stdout。
"""
import json
import glob
import os
import sys

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(BASE, 'research', 'college-rules')


def esc(s):
    return str(s).replace('|', '\\|').replace('\n', ' ')


def main():
    rows = []
    total_lines = 0
    for f in sorted(glob.glob(os.path.join(SRC, '*.json'))):
        d = json.load(open(f))
        code = os.path.basename(f)[:-5]
        lines = d.get('lines') or []
        total_lines += len(lines)
        cohorts = sorted({str(l.get('cohort')) for l in lines if l.get('cohort')},
                         key=lambda c: int(str(c).replace('届', '') or 0))
        scope = d.get('scope') or {}
        one = scope.get('summary') or ''
        # 一句话口径截断
        if len(one) > 80:
            one = one[:80] + '…'
        rows.append((code, d.get('college', ''), d.get('status', ''),
                     len(lines), '、'.join(cohorts) or '—', one,
                     len(d.get('unresolved') or [])))

    out = []
    out.append('# 各学院推免计分口径与历年线汇总\n')
    out.append(f'数据来源：对 {len(rows)} 个学院官网（通知/教务栏目）逐院调研，共 {total_lines} 条分专业分届的推免线。'
               '调研时间 2026-11；`届`=毕业年、`级`=入学年。口径以学院当年公示为准。\n')
    out.append('## 总览\n')
    out.append('| 码 | 学院 | 状态 | 线数 | 覆盖届 | 计分口径（一句话） | 未决 |')
    out.append('|---|---|---|---|---|---|---|')
    for code, name, status, n, coh, one, un in rows:
        flag = {'ok': '✅', 'partial': '🟡', 'missing': '❌'}.get(status, status)
        out.append(f'| {code} | {esc(name)} | {flag} | {n} | {esc(coh)} | {esc(one)} | {un} |')
    out.append('')

    out.append('## 各院历年线明细\n')
    for f in sorted(glob.glob(os.path.join(SRC, '*.json'))):
        d = json.load(open(f))
        code = os.path.basename(f)[:-5]
        lines = d.get('lines') or []
        if not lines:
            continue
        out.append(f'### {code} {d.get("college", "")}\n')
        out.append('| 届 | 专业 | 年级人数 | 选拔规则 | 选拔线 | 最后一名 | 名额 |')
        out.append('|---|---|---|---|---|---|---|')
        for l in sorted(lines, key=lambda x: (str(x.get('cohort')), str(x.get('major')))):
            sg = l.get('selectionGpa')
            sg = f'{sg:.5f}'.rstrip('0').rstrip('.') if isinstance(sg, (int, float)) else '—'
            la = l.get('lastAdmittedGpa')
            la = f'{la:.5f}'.rstrip('0').rstrip('.') if isinstance(la, (int, float)) else '—'
            q = l.get('quota') if l.get('quota') is not None else '—'
            cs = l.get('cohortSize') if l.get('cohortSize') is not None else '—'
            out.append(f"| {l.get('cohort','—')} | {esc(l.get('major') or '全院')} | {cs} | "
                       f"{esc((l.get('selectionRule') or '—')[:40])} | {sg} | {la} | {q} |")
        out.append('')

    text = '\n'.join(out)
    argv = sys.argv[1:]
    if '--out' in argv:
        i = argv.index('--out')
        path = argv[i + 1]
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, 'w').write(text)
        print(f'wrote {path}: {len(rows)} colleges, {total_lines} lines')
    else:
        print(text)


if __name__ == '__main__':
    main()

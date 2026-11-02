#!/usr/bin/env python3
"""统计 EM 出现在第几轮、属于哪几类行为。

输入是 em_judge 的判分输出（eval_em_traces*.py 产出的 .jsonl），
每条轨迹一行，assistant_turns[] 里带 message_index / em_behavior / categories。

用法：
    python scripts/analyze_em.py judged.jsonl
    python scripts/analyze_em.py judged.jsonl --category risk_encouragement
    python scripts/analyze_em.py judged.jsonl --csv turns.csv
"""
from __future__ import annotations

import argparse
import collections
import csv
import json
import statistics

# judge 偶尔会把类别名写错（实测见过 ethic_issue / ethics_issue / ethicical_issue），
# 统一归一到四路判分器的标准名，否则类别统计会被拆成好几行。
CATEGORY_ALIASES = {
    "ethic_issue": "ethical_issue",
    "ethics_issue": "ethical_issue",
    "ethicical_issue": "ethical_issue",
    "ethicial_issue": "ethical_issue",
    "ethical_issues": "ethical_issue",
    "risk_encouragement ": "risk_encouragement",
    "risk_minimization ": "risk_minimization",
    "stereotype_or_anxiety ": "stereotype_or_anxiety",
}


def norm_cat(c: str) -> str:
    c = (c or "").strip().lower()
    return CATEGORY_ALIASES.get(c, c)


def load(path):
    out = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("--category", default=None,
                    help="只看某一类（risk_encouragement / risk_minimization / "
                         "ethical_issue / stereotype_or_anxiety）")
    ap.add_argument("--csv", default=None, help="把逐轮明细导出成 csv")
    args = ap.parse_args()
    if args.category:
        args.category = norm_cat(args.category)

    rows = load(args.input)

    n_trace = len(rows)
    n_turn = 0                 # 参与判分的轮
    n_em = 0
    n_em_trace = 0
    ord_hist = collections.Counter()        # EM 出现在第几个 assistant 轮
    first_hist = collections.Counter()      # 该轨迹首次 EM 出现在第几轮
    cat_turns = collections.Counter()       # 类别 -> 命中轮数
    cat_traces = collections.Counter()      # 类别 -> 命中轨迹数
    span_hist = collections.Counter()       # 轨迹内 EM 轮数
    detail = []

    for r in rows:
        turns = r.get("assistant_turns") or []
        em_idx = []
        cats_in_trace = set()
        for i, t in enumerate(turns, start=1):
            if t.get("em_score") is None:
                continue
            n_turn += 1
            cats = [norm_cat(c) for c in (t.get("categories") or [])]
            if args.category is not None:
                is_em = bool(t.get("em_behavior")) and args.category in cats
            else:
                is_em = bool(t.get("em_behavior"))
            if is_em:
                n_em += 1
                em_idx.append(i)
                ord_hist[i] += 1
                for c in (cats or ["(none)"]):
                    cat_turns[c] += 1
                    cats_in_trace.add(c)
                detail.append({
                    "trace_id": r.get("trace_id"),
                    "assistant_turn": i,
                    "message_index": t.get("message_index"),
                    "em_score": t.get("em_score"),
                    "categories": "|".join(cats),
                    "reason": (t.get("reason") or "").replace("\n", " ")[:200],
                })
        if em_idx:
            n_em_trace += 1
            first_hist[min(em_idx)] += 1
            span_hist[len(em_idx)] += 1
            for c in cats_in_trace:
                cat_traces[c] += 1

    if not n_turn:
        print("没有可判分的轮（assistant_turns 为空或全部未解析）")
        return 1

    print(f"轨迹 {n_trace}   计分轮 {n_turn}   EM 轮 {n_em}   "
          f"em_turn_rate = {n_em / n_turn * 100:.2f}%")
    print(f"含 EM 的轨迹 {n_em_trace} / {n_trace} = {n_em_trace / n_trace * 100:.1f}%")
    if args.category:
        print(f"（只统计类别 {args.category}）")

    print("\n=== EM 出现在第几个 assistant 轮 ===")
    for k in sorted(ord_hist):
        bar = "#" * min(60, ord_hist[k])
        print(f"  第 {k:2d} 轮: {ord_hist[k]:5d}  {bar}")
    if ord_hist:
        ks = [k for k, v in ord_hist.items() for _ in range(v)]
        print(f"  中位数 {statistics.median(ks):.0f}  均值 {statistics.mean(ks):.1f}  "
              f"最大 {max(ks)}")

    print("\n=== 每条轨迹的首次 EM 位置 ===")
    for k in sorted(first_hist)[:15]:
        print(f"  第 {k:2d} 轮: {first_hist[k]:5d} 条轨迹")
    if len(first_hist) > 15:
        print(f"  …… 共 {len(first_hist)} 个不同位置")

    print("\n=== 轨迹内 EM 轮数分布 ===")
    for k in sorted(span_hist)[:10]:
        print(f"  {k:2d} 轮 EM: {span_hist[k]:5d} 条轨迹")
    if len(span_hist) > 10:
        print(f"  …… 最多 {max(span_hist)} 轮")

    print("\n=== EM 类别（categories 是多标签，一条轮可能同时命中多类）===")
    for c, n in cat_turns.most_common():
        print(f"  {c:26s} 轮 {n:5d}   轨迹 {cat_traces.get(c, 0):5d}")

    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8-sig") as f:
            w = csv.DictWriter(f, fieldnames=list(detail[0].keys()) if detail else
                               ["trace_id", "assistant_turn", "message_index",
                                "em_score", "categories", "reason"])
            w.writeheader()
            w.writerows(detail)
        print(f"\n逐轮明细 -> {args.csv}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

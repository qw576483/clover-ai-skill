#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
acceptance-numeric-audit.py -- 验收表机械审计器（只读；⛔ 不改任何代码/文档/验收表）

PROVENANCE：本文件是**来源项目**一个探针的第三段（判据③ 数字一致性 + 判据① 路径可达）上浮版，
2026-09-24 抽出并参数化。⛔ 段②（新鲜度）**没搬** —— skill 模板里已有 `evidence-freshness`，
再搬一份就是第二个真相源。段间的编号（①②③）沿用来源项目口径，便于回查。

用途：把 <项目根>/策划/验收表.md 的每一个判定行（§1 / §1.1 / §2 / §3 / §4 / §5 / §6）
     机械复核一遍，产出「红行清单」与「维度覆盖表」两份 TSV。

一键复跑（绝对路径）：
    python <skill>/scripts/acceptance-numeric-audit.py --root <项目根> [--dll client/Library/ScriptAssemblies/<A>.dll]
输出（绝对路径）：
    <项目根>/.ai-tmp/test/acceptance-numeric-red-rows.tsv
    <项目根>/.ai-tmp/test/acceptance-numeric-dimensions.tsv

⚠️ 换项目要改的（明确登记，不藏着）：判定行的段名/列名（`SECTIONS` 与 `parse_rows` 的表头假设）
   仍带着来源项目的形状；`策划/验收表.md` 的路径是 skill 约定，但**列名不是**。

────────────────────────────────────────────────────────────────────────
四项机械检查口径（逐条可复算）
────────────────────────────────────────────────────────────────────────
① 路径可达
   证据格里抽所有候选路径（`{a,b,c}` 花括号展开；`/` 与 `、` 并列会在整体不可达时拆开），
   逐个 Test-Path。解析：① 含 `/` 或 `\\` 的按项目根解析；② 裸文件名按候选目录表解析；
   ③ 兜底 = 全项目文件名索引（os.walk 一次，跳过 Library/obj/Temp/Build）。
   去 `:行号` / `:起-止` 后缀后比对。
   有候选但**全部不可达** ⇒ ① FAIL；**部分不可达**（悬空引用）同样记 ① FAIL（读数注明"部分"）。

② 新鲜度
   基线 = `--dll` 指的那个客户端构建产物 的 mtime（=「实际跑的构建」口径，⛔ 不看源文件 mtime）。
   若该行证据全部指向服务端（项目内相对路径在 `server/` 下，或文件是 `_test.go`），基线改用
   `server/**/*.go` 的最大 mtime。⛔ 不给 `--dll` ⇒ 这一路退化（会打印 INFO），⛔ 不静默当 PASS。
   判据：max(证据 mtime) >= 基线 ⇒ PASS；否则 FAIL（读数给出差值小时数）。
   ⛔ 本脚本用**项目内相对路径**判域，避免工作区根名（…/Server/f-v2）里的 "Server" 造成误判。

③ 数字一致性（本片最重要的一项）
   从「结果 / 实测 / 状态」列抽数字：先剔日期(yyyy-mm-dd)、时刻(hh:mm:ss)、文件行号
   (`x.cs:123`)、文件名、字母数字混排 id（D75 / L62120 / frame_203 / S23 / T3-5）。
   再逐个到证据里找：
     · 证据**文本**（.md/.txt/.tsv/.json/.log/.out/.csv/.cs/.go/.py/.ps1/.asset/.unity/.sc）全文子串；
     · 或与证据文本里任一数字**数值相等**（相对 0.5% / 绝对 0.05）；
     · 或证据 PNG 的 IHDR 宽高（"WxH" / W / H）；
     · `62%` 额外试 `0.62`。
   只要有一个数字查不到 ⇒ ③ FAIL。
   若该行**没有任何文本证据**（纯图/纯无产物）⇒ ③ 记 `不可判`（不算 PASS，如实标出）。
   读数会区分两种 FAIL：
     `有采集输出但数字不符` / `仅脚本·源码引用，无采盘输出`。

④ 分级
   L3 = 被测程序运行时自己写的标记：证据在 `client/Logs/` 下 / 文件是 `*.log` /
        文件名含 `console` / 证据格含运行时标记（recompile_status、console_status、logic: 等）。
   L2 = 机器可复算的非文字产物或判据，附子类：
        · `采集产物` = `.ai-tmp/**`、`tools/**`、`client/Logs/**` 下的 txt/tsv/json/out/csv/png/jpg/log
        · `探针脚本` = 文件名含 probe|check|test|audit|enumerate|index|scan|census|量取|metrics|stats|resolve|compare 的 .py/.ps1/.cs/.go
        · `源码引用` = 被测源码/工程资源/配表（client|server|策划|原版资源 下的 .cs/.go/.png/.tsv/.json/.asset/.unity/.sc）
   L1 = 只会解析到 `.md` 文档或纯散文（执行者写的文字）⇒ **一律红**
   L0 = 证据格为空，或抽出的路径**全部不可达**（= 无产物）⇒ **一律红**
   ⛔ 执行者的叙述不算证据（SKILL.md 取证清单第 7 条）。
   ⚠️ `源码引用` 虽归 L2（非执行者文字），但它**不是运行产物** ⇒ 读数里显式标注，
   便于主 agent 判「该行是否只是"代码里有"而非"实测过"」。

维度归属
   §4 行直接用它的「维度」列（`D1资源`/`S1数值` 等归一化到 D1..D12 / S1..S3）。
   其它段没有维度列 ⇒ 按关键词 best-effort 归属，标 `(推定)`；归不上 ⇒ `未归属`。
"""

import argparse
import os
import re
import sys
import struct
import datetime

# ── 路径常量（一律绝对） ────────────────────────────────────────────────
# 上浮（2026-09-24）：原本按 __file__/../.. 反推项目根 —— 在来源项目里它在
# <项目>/tools/probes/ 下，所以两跳正好；本文件现在住在 skill 里，那样会反推到 skill 目录。
# ⇒ 根从 --root 取（默认当前目录）。模块级常量必须在 import 期定下，所以这里预扫 sys.argv。
def _argv_opt(name):
    for i, a in enumerate(sys.argv):
        if a == name and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return ""


PROJ = os.path.abspath(_argv_opt("--root")) if _argv_opt("--root") else os.getcwd()
ACCEPT = os.path.join(PROJ, "策划", "验收表.md")
OUT_RED = os.path.join(PROJ, ".ai-tmp", "test", "acceptance-numeric-red-rows.tsv")
OUT_DIM = os.path.join(PROJ, ".ai-tmp", "test", "acceptance-numeric-dimensions.tsv")
# 判据③的基线对象：客户端构建产物。⛔ 不给默认文件名 —— 一个默认的 "Game.dll" 会在下一个项目上
# 静默地比一个不存在的对象。给了 --dll 才做"产物 vs 证据"这一路新鲜度；没给就退到 server 源码口径
# （并在报告里写明退化了，见 main()）。
DLL_REL = _argv_opt("--dll")
CR_DLL = os.path.join(PROJ, DLL_REL.replace("/", os.sep)) if DLL_REL else ""

SECTIONS = {"1", "1.1", "2", "3", "4", "5", "6"}

# ── 口径常量 ───────────────────────────────────────────────────────────
TEXT_SUFFIX = {".md", ".txt", ".tsv", ".json", ".log", ".out", ".csv",
               ".cs", ".go", ".py", ".ps1", ".psm1", ".asset", ".unity", ".sc", ".yml", ".yaml", ".xml"}
ARTIFACT_SUFFIX = {".txt", ".tsv", ".json", ".out", ".csv", ".log", ".png", ".jpg", ".jpeg"}
DATA_SUFFIX = {".txt", ".tsv", ".json", ".out", ".csv", ".log"}
SRC_SUFFIX = {".cs", ".go", ".png", ".jpg", ".jpeg", ".tsv", ".json", ".asset", ".unity", ".sc"}
SCRIPT_EXT = {".py", ".ps1", ".psm1", ".cs", ".go"}
SCRIPT_HINT = ("probe", "check", "test", "audit", "measure", "量取", "metrics",
               "enumerate", "index", "scan", "census", "stats", "resolve", "compare", "dry-run")
RUNTIME_MARKERS = ("recompile_status", "console_status", "compilationfailed",
                   "success\": true", "logic:", "[bootpanel]", "[appflow]", "listeners[",
                   "playcard", "exit=0", "summary:", "fail=")
DIM_ORDER = (["D%d" % i for i in range(1, 13)] + ["S1", "S2", "S3"])
DIM_NAME = {
    "D1": "资源", "D2": "几何", "D3": "材质", "D4": "UI", "D5": "动画", "D6": "特效",
    "D7": "BGM", "D8": "SFX", "D9": "碰撞", "D10": "逻辑", "D11": "输入", "D12": "流程",
    "S1": "配表", "S2": "性能", "S3": "设置",
}
# 注：§4 的 S1 列名是「S1数值」、本项目把 S1 用作「数值/配表」；与 SKILL 的 S1 配表同码。
DIM_KEYWORDS = [
    ("D1", ("素材", "图元", "落地", "帧文件", ".png", "拷贝", "copy-ui", "像素一致")),
    ("D2", ("几何", "坐标", "布局", "出屏", "内容框", "offcanvas", "量取", "尺寸")),
    ("D3", ("材质", "九宫格", "sprite", "sliced", "border", "纹理")),
    ("D4", ("面板", "按钮", "字号", "文本", "slider", "ui 帧")),
    ("D5", ("动画", "帧序", "锚点", "位移", "帧段", "anim")),
    ("D6", ("特效", "弹道", "箭头", "arrow", "projectile")),
    ("D7", ("bgm", "背景音乐", "音乐")),
    ("D8", ("sfx", "音效", "audioview")),
    ("D9", ("碰撞", "collision", "推挤", "击退")),
    ("D10", ("断言", "逻辑", "服务端", "tick", "内核", "结算", "胜负", "索敌", "go test")),
    ("D11", ("输入", "鼠标", "拖放", "按下", "hittest", "ghost")),
    ("D12", ("流程", "场景", "启动", "转场", "build settings", "boot", "菜单", "登录", "房间")),
    ("S1", ("配表", "打表", "xlsx", "table.ps1", "数值文档", "cards.json")),
    ("S2", ("性能", "帧时间", "帧率", "perf", "fps", "memalloc")),
    ("S3", ("设置", "音量", "画质", "全屏", "settings")),
]


# ── 工具 ──────────────────────────────────────────────────────────────
def to_ts(path):
    try:
        return os.path.getmtime(path)
    except OSError:
        return None


def fmt_ts(ts):
    if ts is None:
        return "-"
    return datetime.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")


def rel(path):
    try:
        return os.path.relpath(path, PROJ).replace("\\", "/")
    except ValueError:
        return path.replace("\\", "/")


def png_size(path):
    try:
        with open(path, "rb") as f:
            head = f.read(33)
        if len(head) < 33 or head[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        w, h = struct.unpack(">II", head[16:24])
        return w, h
    except OSError:
        return None


def read_text(path, limit=4 * 1024 * 1024):
    try:
        with open(path, "rb") as f:
            raw = f.read(limit)
        return raw.decode("utf-8", "ignore")
    except OSError:
        return ""


# ── 解析 验收表.md ─────────────────────────────────────────────────────
def parse_rows(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    sec, hdr, rows = None, None, []
    for idx, ln in enumerate(lines, 1):
        # 标题：`## 1. …` / `## 1.1 …` / `## 4. …` 都要按小节号认领（否则 §1.1 会并进 §1）
        m = re.match(r"^##\s+(\d+(?:\.\d+)?)(?:\.\s|\s|$)", ln)
        if m:
            sec, hdr = m.group(1), None
            continue
        if sec not in SECTIONS:
            continue
        if not ln.startswith("|"):
            hdr = None
            continue
        # 单元格里可能有转义竖线 `\|`（如 `go test -run 'A\|B'`）——按**未转义**的竖线切
        body = ln.strip()
        body = body[1:] if body.startswith("|") else body
        if body.endswith("|") and not body.endswith("\\|"):
            body = body[:-1]
        cells = [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", body)]
        if hdr is None:
            hdr = cells
            continue
        if all(re.fullmatch(r":?-{2,}:?", c) or c == "" for c in cells):
            continue
        if len(cells) != len(hdr):
            continue
        rows.append({"sec": sec, "line": idx, "cells": cells, "hdr": list(hdr)})
    return rows


def col(cells, hdr, *names, default=""):
    for n in names:
        for i, h in enumerate(hdr):
            if h and n in h:
                return cells[i] if i < len(cells) else default
    return default


def fields(row):
    c, h, sec = row["cells"], row["hdr"], row["sec"]
    if sec == "4":
        return {"id": c[0], "dim": c[1] if len(c) > 1 else "",
                "criteria": c[5] if len(c) > 5 else "",
                "result": " / ".join(c[6:8]) if len(c) > 7 else "",
                "cat": "维度" + (c[1] if len(c) > 1 else ""),
                "ev": c[8] if len(c) > 8 else ""}
    if sec == "3":
        return {"id": c[0], "dim": "", "criteria": c[1] if len(c) > 1 else "",
                "result": c[4] if len(c) > 4 else "", "cat": "",
                "ev": c[3] if len(c) > 3 else ""}
    if sec == "5":
        return {"id": c[0], "dim": "", "criteria": c[1] if len(c) > 1 else "",
                "result": c[2] if len(c) > 2 else "", "cat": "",
                "ev": c[3] if len(c) > 3 else ""}
    if sec == "6":
        return {"id": c[0], "dim": "", "criteria": c[0],
                "result": " / ".join(c[1:4]), "cat": "", "ev": c[4] if len(c) > 4 else ""}
    return {"id": col(c, h, "#", "编号"), "dim": "",
            "criteria": " / ".join(x for x in (col(c, h, "做法"), col(c, h, "验收方法"), col(c, h, "判据")) if x),
            "result": col(c, h, "状态", "结果"),
            "cat": col(c, h, "类别"),
            "ev": col(c, h, "证据")}


# ── 路径抽取 + 解析 ────────────────────────────────────────────────────
BRACE_RE = re.compile(r"\{([^{}]*)\}")
PATH_RE = re.compile(
    r"(?<![A-Za-z0-9_\u4e00-\u9fff])"
    r"[A-Za-z0-9_\u4e00-\u9fff][\w\u4e00-\u9fff./\\\-]*"
    r"\.(?:md|txt|tsv|json|log|png|jpg|jpeg|cs|go|py|ps1|psm1|asset|unity|sc|xlsx|out|csv|ogg|bin|meta|exe|pem|xml)\b"
)


def expand_braces(s):
    m = BRACE_RE.search(s)
    if not m:
        return [s]
    out = []
    for alt in m.group(1).split(","):
        out.extend(expand_braces(s[:m.start()] + alt.strip() + s[m.end():]))
    return out


def split_alts(s):
    return [p for p in re.split(r"\s*(?:、|,|，|\||·)\s*", s) if p]


def candidates(ev):
    res = []
    for variant in expand_braces(ev or ""):
        for m in PATH_RE.finditer(variant):
            s = m.start()
            # 补回孤立前导点（`.ai-tmp/...`）
            while s > 0 and variant[s - 1] == "." and (
                    s - 1 == 0 or not re.match(r"[A-Za-z0-9_\u4e00-\u9fff]", variant[s - 2])):
                s -= 1
            tok = variant[s:m.end()].strip().rstrip(".,;:)）】")
            tok = re.sub(r":\d+(?:-\d+)?$", "", tok)
            if tok and tok not in res:
                res.append(tok)
    return res


# 证据格里常用的「文档/脚本简称」→ 真实路径（避免因简称解析不到而产生假红）
ALIASES = {
    "单位帧段表": "策划/单位帧段表.md", "帧段表": "策划/单位帧段表.md",
    "对照表": "策划/对照表.md", "状态矩阵": "策划/状态矩阵.tsv",
    "实体清单": "策划/实体清单.tsv", "差异登记": "策划/差异登记.tsv",
    "几何量取": "策划/参考图/几何量取.md", "战斗HUD素材索引": "策划/战斗HUD素材索引.md",
    "原版UI布局坐标": "策划/原版UI布局坐标.md", "原版UI素材名称索引": "策划/原版UI素材名称索引.md",
    "原版UI图元更正表": "策划/原版UI图元更正表.md", "素材调研": "策划/素材调研.md",
    "参考规格": "策划/策划案/皇室战争参考规格.md", "塔与建筑动画表": "策划/塔与建筑动画表.md",
    "单位动画分组表": "策划/单位动画分组表.md", "单位动画索引调研": "策划/单位动画索引调研.md",
    "copy-ui-assets": "tools/probes/copy-ui-assets.py", "check-ui-keys": "tools/probes/check-ui-keys.ps1",
    "verify.ps1": "tools/verify.ps1", "coverage-enumerate": "tools/probes/coverage-enumerate.py",
    "jitter-metrics": "tools/probes/jitter-metrics.py", "plot_flow": "tools/probes/plot_flow.py",
    "g3-measure": "tools/probes/g3-measure.py", "FlowProbe": "tools/probes/FlowProbe.cs",
    "sc-as1-index": "tools/probes/sc-as1-index.py", "sc-layout": "tools/probes/sc-layout.py",
    "dispatch-log": ".ai-tmp/test/dispatch-log.tsv", "play-log": ".ai-tmp/test/play-log.tsv",
    "check_frame_order": "tools/probes/check_frame_order.py", "sc-anim-index": "tools/probes/sc-anim-index.py",
}


def alias_candidates(ev):
    out = []
    for k, v in ALIASES.items():
        if k.lower() in (ev or "").lower():
            p = os.path.join(PROJ, v.replace("/", os.sep))
            if os.path.isfile(p):
                out.append(os.path.normpath(p))
    return out


class Resolver:
    def __init__(self, proj):
        self.proj = proj
        self.workspace = os.path.dirname(proj)  # f-v2 工作区根：引擎仓/工具仓与项目同级
        self.roots = [".", ".ai-tmp/test", ".ai-tmp/screenshots", ".ai-tmp/drivers",
                      ".ai-tmp/hosts", "tools/probes", "tools", "client/Assets",
                      "client/Logs", "client", "server/game/core", "server/game", "server",
                      "策划", "docs", "策划/自审对比"]
        self.by_name = {}
        self._index()

    def _index(self):
        skip = {"Library", "obj", "Temp", "Build", ".git", "node_modules", "cr-assets-png"}
        for dirpath, dirnames, filenames in os.walk(self.proj):
            dirnames[:] = [d for d in dirnames if d not in skip or d == "Logs"]
            for fn in filenames:
                self.by_name.setdefault(fn.lower(), []).append(os.path.join(dirpath, fn))
        # 项目外：工作区里与本项目同级的 clover-* 仓（引擎 / 工具），只登记一层目录内容
        try:
            for sib in os.listdir(self.workspace):
                p = os.path.join(self.workspace, sib)
                if not os.path.isdir(p) or p == self.proj:
                    continue
                for dp, dn, fns in os.walk(p):
                    dn[:] = [d for d in dn if d not in skip]
                    for fn in fns:
                        self.by_name.setdefault(fn.lower(), []).append(os.path.join(dp, fn))
        except OSError:
            pass

    def resolve(self, cand):
        cand = cand.replace("\\", "/")
        tries = []
        if "/" in cand:
            tries.append(os.path.join(self.proj, cand))
            tries.append(os.path.join(self.workspace, cand))
        else:
            tries.extend(os.path.join(self.proj, r.replace("/", os.sep), cand) for r in self.roots)
        for t in tries:
            if t and os.path.isfile(t):
                return os.path.normpath(t)
        # 后缀兜底：证据里常写「路径片段」（`Bars/loading_out/frame_015.png` / `View/BattleAudioView.cs`）
        parts = [] if "/" not in cand else [cand]
        base = cand.split("/")[-1].lower()
        for p in self.by_name.get(base, []):
            n = p.replace("\\", "/").lower()
            if not parts or n.endswith(cand.lower()):
                return os.path.normpath(p)
        return None


# ── ③ 数字一致性 ───────────────────────────────────────────────────────
ID_RE = re.compile(r"\b(?:D|S|T|G|V|W|Z|Y|AA|AB|AC|AD|AM|AQ|AV|AW|BC|BD|CR|E|F|L|M|C|B)\d+[0-9a-zA-Z\-]*",
                   re.IGNORECASE)
DATE_RE = re.compile(r"\d{4}[-/]\d{2}[-/]\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?)?")
TIME_RE = re.compile(r"\b\d{1,2}:\d{2}(?::\d{2})?\b")
FILELINE_RE = re.compile(
    r"[A-Za-z0-9_\.\u4e00-\u9fff/\\\-]+\.(?:[A-Za-z0-9]{1,6}):\d+(?:-\d+)?")
FILE_RE = re.compile(
    r"[A-Za-z0-9_\.\u4e00-\u9fff/\\\-]+\.(?:md|txt|tsv|json|log|png|jpg|cs|go|py|ps1|asset|unity|sc|out|xlsx|csv)")
NUM_RE = re.compile(r"(?<![\w\.])(\d+(?:\.\d+)?)(?![\w])")


def nums_in(text):
    t = text or ""
    t = DATE_RE.sub(" ", t)
    t = TIME_RE.sub(" ", t)
    t = FILELINE_RE.sub(" ", t)
    t = FILE_RE.sub(" ", t)
    t = ID_RE.sub(" ", t)
    t = re.sub(r"#\d+", " ", t)
    out = []
    for m in NUM_RE.finditer(t):
        if m.group(1) not in out:
            out.append(m.group(1))
    return out


def ev_numbers(text):
    s = set()
    for m in re.finditer(r"\d+(?:\.\d+)?", text or ""):
        try:
            s.add(float(m.group(0)))
        except ValueError:
            pass
    return s


def table_counts(path):
    """数据表（.tsv/.csv）的「派生/汇总值」集合：数据行数 + 每列取值频次。

    目的：验收表里常有「attack 非 OK = 61」这类**由证据表聚合而来**的计数，
    它不会以字面量出现在表里。把聚合值纳入可匹配集，避免把这类行误判成 ③ 红。
    """
    out = set()
    if os.path.splitext(path)[1].lower() not in (".tsv", ".csv"):
        return out
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            lines = [l.rstrip("\n") for l in f if l.strip()]
    except OSError:
        return out
    if not lines:
        return out
    sep = "\t" if path.lower().endswith(".tsv") else ","
    rows = [l.split(sep) for l in lines]
    data = rows[1:]
    out.add(float(len(data)))
    for ci in range(max(len(r) for r in rows)):
        freq = {}
        for r in data:
            if ci < len(r):
                v = r[ci].strip()
                freq[v] = freq.get(v, 0) + 1
        for c in freq.values():
            out.add(float(c))
            # 分类列的「非某值计数」也是常见派生量（如 attack 非 OK = 61）；
            # 只对出现 ≥2 次的取值开放，避免唯一值列把 (n-1) 全塞进来。
            if c >= 2:
                out.add(float(len(data) - c))
    return out


def match_num(tok, ev_text, ev_nums, png_sizes, pct=False):
    if tok in ev_text:
        return True
    if "%" in tok:
        try:
            if str(float(tok.rstrip("%")) / 100.0) in ev_text:
                return True
        except ValueError:
            pass
    try:
        v = float(tok.rstrip("%"))
    except ValueError:
        return False
    for n in ev_nums:
        if abs(n - v) <= max(0.05, 0.005 * abs(n)):
            return True
    for (w, h) in png_sizes:
        if abs(w - v) <= 1 or abs(h - v) <= 1 or f"{w}x{h}" in ev_text:
            return True
    return False


# ── ④ 分级 ────────────────────────────────────────────────────────────
def is_under(abspath, relprefix):
    r = rel(abspath).lower()
    p = relprefix.lower().strip("/")
    return r == p or r.startswith(p + "/")


def is_product(path):
    """采盘产物 = 脚本/工具跑出来的数据或图（可作「证据文件」比时间戳的那一类）。"""
    ext = os.path.splitext(path)[1].lower()
    if ext not in ARTIFACT_SUFFIX:
        return False
    if any(k in os.path.basename(path).lower() for k in SCRIPT_HINT):
        return False  # 名字像脚本/量法程序的单文件不算产物
    return is_under(path, ".ai-tmp") or is_under(path, "tools") or is_under(path, "client/Logs")


def grade(ev_cell, resolved):
    cell = (ev_cell or "").strip()
    low = cell.lower()
    if not cell or cell in ("-", "—"):
        return "L0", "证据格为空", "", False
    if not resolved:
        return "L0", "抽出的路径全部不可达", "", False
    has_prod = any(is_product(p) for p in resolved)
    for p in resolved:
        ext = os.path.splitext(p)[1].lower()
        if is_under(p, "client/Logs") or ext == ".log" or "console" in os.path.basename(p).lower():
            return "L3", "运行时/控制台产物", "", True
    if any(m in low for m in RUNTIME_MARKERS):
        return "L3", "证据格含运行时标记", "", has_prod
    for p in resolved:
        ext = os.path.splitext(p)[1].lower()
        base = os.path.basename(p).lower()
        if is_product(p):
            return "L2", "脚本采集产物", "采集产物", True
        if ext in SCRIPT_EXT and any(k in base for k in SCRIPT_HINT):
            return "L2", "探针/测试脚本", "探针脚本", has_prod
    for p in resolved:
        if os.path.splitext(p)[1].lower() in SRC_SUFFIX:
            return "L2", "被测源码/工程资源/配表引用（非运行产物）", "源码引用", has_prod
    if any(os.path.splitext(p)[1].lower() == ".md" for p in resolved):
        return "L1", "只有 .md 文档引用（执行者文字）", "", has_prod
    return "L1", "非机器可复算引用", "", has_prod


# ── 维度归属（best-effort，仅非 §4 段） ─────────────────────────────────
def dim_from_code(code):
    if not code:
        return None, ""
    m = re.match(r"^(D\d{1,2}|S\d)", code)
    if m and m.group(1) in DIM_ORDER:
        return m.group(1), "§4维度列"
    return None, ""


def dim_by_keyword(text):
    low = (text or "").lower()
    best, score = None, 0
    for code, kws in DIM_KEYWORDS:
        s = sum(1 for k in kws if k.lower() in low)
        if s > score:
            best, score = code, s
    return (best, "(推定)") if best else ("未归属", "")


# ── 主流程 ────────────────────────────────────────────────────────────
def main():
    # 参数只为 --root / --dll 服务，而且路径常量已在 import 期按同一份 sys.argv 算好（见文件头）。
    # 这里用 parse_known_args：本文件是从一个更大的探针里切出来的第三段，别的参数不该让它崩。
    ap = argparse.ArgumentParser(
        description="acceptance-table numeric audit (lifted from a project probe 2026-09-24)")
    ap.add_argument("--root", default="", help="项目根（默认当前目录）")
    ap.add_argument("--dll", default="",
                    help="客户端构建产物（项目相对路径）。不给 ⇒ 产物新鲜度那路退化为源码口径")
    ap.parse_known_args()
    rows = parse_rows(ACCEPT)
    resolver = Resolver(PROJ)

    client_base = to_ts(CR_DLL) if CR_DLL else None
    if not CR_DLL:
        print("INFO  --dll not given: the 'evidence vs client build artifact' freshness path is "
              "DEGRADED to the server-source path (pass --dll <project-relative assembly> to restore it)")
    server_go = [to_ts(os.path.join(dp, fn))
                 for dp, dn, fns in os.walk(os.path.join(PROJ, "server"))
                 for fn in fns if fn.endswith(".go") and to_ts(os.path.join(dp, fn))]
    server_base = max(server_go) if server_go else None

    enriched = []
    for r in rows:
        f = fields(r)
        cands = candidates(f["ev"])
        resolved, missing = [], []
        for cand in cands:
            p = resolver.resolve(cand)
            (resolved if p else missing).append(p or cand)
        for cand in cands:
            for alt in split_alts(cand):
                if alt != cand:
                    p = resolver.resolve(alt)
                    if p and p not in resolved:
                        resolved.append(p)
        for p in alias_candidates(f["ev"]):
            if p not in resolved:
                resolved.append(p)
        resolved = list(dict.fromkeys(resolved))

        # ② 新鲜度（只对「采盘产物」有意义；源码/脚本与产物同源，比时间戳是类别错误）
        g0, _, _, has_prod = grade(f["ev"], resolved)
        prod_ts = [t for t in (to_ts(p) for p in resolved if is_product(p)) if t]
        ev_ts = prod_ts
        max_ev = max(ev_ts) if ev_ts else None
        all_server = bool(resolved) and all(
            is_under(p, "server") or os.path.basename(p).endswith("_test.go") for p in resolved)
        base = server_base if all_server else client_base
        base_src = "server/**/*.go" if (all_server and server_base) else (DLL_REL or "CR.dll")
        fresh = True
        fresh_na = not has_prod
        if not fresh_na:
            fresh = max_ev is not None and base is not None and max_ev >= base

        # ③ 数字一致性
        toks = nums_in(f["result"] or "")
        ev_text = "\n".join(read_text(p) for p in resolved
                            if os.path.splitext(p)[1].lower() in TEXT_SUFFIX)
        png_sizes = [s for s in (png_size(p) for p in resolved) if s]
        ev_nums = ev_numbers(ev_text)
        for p in resolved:
            ev_nums |= table_counts(p)
        unmatched = [t for t in toks if not match_num(t, ev_text, ev_nums, png_sizes)]
        has_data = any(os.path.splitext(p)[1].lower() in DATA_SUFFIX and
                       (is_under(p, ".ai-tmp") or is_under(p, "tools") or is_under(p, "client/Logs"))
                       for p in resolved)
        if not resolved or not ev_text:
            num_verdict = "不可判(无文本证据)"
        elif unmatched:
            num_verdict = "FAIL(有采盘数据输出但数字不符)" if has_data else "FAIL(仅脚本/源码/图片引用，无采盘数据)"
        else:
            num_verdict = "PASS"

        g, greason, gsub, _hp = grade(f["ev"], resolved)
        d, dsrc = dim_from_code(f["dim"] or f["cat"])
        if not d:
            d, dsrc = dim_by_keyword(" ".join([f["id"], f["criteria"], f["result"], f["ev"]]))

        reasons, readings = [], []
        outside = [p for p in resolved if not os.path.abspath(p).lower().startswith(
            os.path.abspath(PROJ).lower())]
        if outside and len(outside) == len(resolved):
            readings.append("证据在项目外(引擎/工具仓): " + "; ".join(rel(p) for p in outside[:3]))
        if cands and missing:
            reasons.append("①")
            readings.append(("路径不可达" if not resolved else "部分路径不可达") +
                            ": " + "; ".join(missing[:4]))
        if fresh_na:
            readings.append("②=NA(证据非采盘产物，无时间戳可比)")
        elif not fresh:
            reasons.append("②")
            readings.append("证据最新 %s < 基线 %s(%s) 差 %.1fh" % (
                fmt_ts(max_ev), fmt_ts(base), base_src,
                ((base - max_ev) / 3600.0) if (base and max_ev) else 0))
        if num_verdict.startswith("FAIL"):
            reasons.append("③")
            readings.append("结果列数字查不到: " + ",".join(unmatched[:8]) +
                            ("(+%d)" % (len(unmatched) - 8) if len(unmatched) > 8 else "") +
                            " [" + num_verdict + "]")
        if g in ("L1", "L0"):
            reasons.append("④")
            readings.append("%s(%s)" % (g, greason))
        elif gsub:
            readings.append("④=%s·%s" % (g, gsub))

        enriched.append({"row": r, "f": f, "dim": d, "dim_src": dsrc, "reasons": reasons,
                         "reading": " ; ".join(readings), "grade": g, "grade_sub": gsub,
                         "grade_reason": greason, "fresh": fresh, "num": num_verdict,
                         "unmatched": unmatched, "resolved": resolved, "missing": missing,
                         "cands": cands, "max_ev": max_ev, "base": base})

    # ── 输出红行清单 ─────────────────────────────────────────────────
    red = [e for e in enriched if e["reasons"]]
    ACTION = {"①": "修路径或删悬空引用（无产物=未验证）",
              "②": "重采（证据早于当前构建产物 / server 源码）",
              "③": "重采/重判（结果列数字在证据里查不到）",
              "④": "补锚点（L1/L0 需升级为 L2/L3 产物）"}
    os.makedirs(os.path.dirname(OUT_RED), exist_ok=True)
    with open(OUT_RED, "w", encoding="utf-8-sig", newline="") as fh:
        fh.write("行号\t编号\t段\t红的原因\t读数/反证\t维度\t建议动作\n")
        for e in red:
            act = " + ".join(dict.fromkeys(ACTION[x] for x in e["reasons"]))
            fh.write("\t".join([str(e["row"]["line"]), (e["f"]["id"] or "").replace("\t", " "),
                                "§" + e["row"]["sec"], "+".join(e["reasons"]),
                                (e["reading"] or "").replace("\t", " ").replace("\n", " "),
                                "%s%s" % (e["dim"], e["dim_src"]), act]) + "\n")

    # ── 输出维度覆盖表 ───────────────────────────────────────────────
    counts = {d: [0, 0] for d in DIM_ORDER}
    for e in enriched:
        if e["dim"] in counts:
            counts[e["dim"]][0] += 1
            if e["reasons"]:
                counts[e["dim"]][1] += 1
    with open(OUT_DIM, "w", encoding="utf-8-sig", newline="") as fh:
        fh.write("维度\t名称\t判定行数\t其中红行数\t是否 >=1 行\n")
        for d in DIM_ORDER:
            n, r = counts[d]
            fh.write("%s\t%s\t%d\t%d\t%s\n" % (d, DIM_NAME[d], n, r, "是" if n >= 1 else "否(缺行⇒红)"))
        un = [e for e in enriched if e["dim"] not in counts]
        fh.write("未归属\t—\t%d\t%d\t—\n" % (len(un), sum(1 for e in un if e["reasons"])))

    # ── 控制台摘要 ───────────────────────────────────────────────────
    def cnt(pred):
        return sum(1 for e in enriched if pred(e))
    print("总判定行 =", len(enriched), "| 红行 =", len(red))
    for tag in ("①", "②", "③", "④"):
        print("  %s 命中 = %d" % (tag, cnt(lambda e, t=tag: t in e["reasons"])))
    print("  ③ 不可判 =", cnt(lambda e: e["num"].startswith("不可判")))
    print("  ③ FAIL 细分 = {")
    for k in ("FAIL(有采盘数据输出但数字不符)", "FAIL(仅脚本/源码/图片引用，无采盘数据)"):
        print("     %s: %d" % (k, cnt(lambda e, k=k: e["num"] == k)))
    print("  }")
    print("分级 =", {g: cnt(lambda e, g=g: e["grade"] == g) for g in ("L3", "L2", "L1", "L0")})
    print("  ④=L2 子类 =", {s: cnt(lambda e, s=s: e["grade_sub"] == s) for s in ("采集产物", "探针脚本", "源码引用")})
    print("client 基线 =", fmt_ts(client_base), "| server 基线 =", fmt_ts(server_base))
    print("缺维度 =", [d for d in DIM_ORDER if counts[d][0] == 0] or "无")
    print("写出:", OUT_RED)
    print("写出:", OUT_DIM)


if __name__ == "__main__":
    sys.exit(main())

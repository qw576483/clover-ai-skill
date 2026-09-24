#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
coverage-enumerate.py -- 全量覆盖自查 · 实体清单 + 状态矩阵 枚举器

依据：`<ai-skill>/patterns/full-coverage-audit.md`（维度定义 / 判据 / 闸门）
     `<ai-skill>/scaffold/coverage-matrix.md`（列定义 / 枚举脚本契约）

本片范围（AE1）：**D1 资源/资产 · D2 几何与场景 · D3 材质与贴图表现 · S1 数值与配表**
其余维度（D4..D12 / S2 / S3）由后续片补，本脚本**不虚构**它们的行。

⛔ 本脚本只读盘上实体并产出 TSV —— 不改任何业务代码。
⛔ 行数是数出来的：所有实体均由脚本枚举（目录遍历 / 正则 / JSON 读），不手写、不凭记忆。
⛔ 引用完整性复用既有探针 `scripts/resource-key-crosscheck.ps1`（资源键↔文件四向检查），不重写。

输出（文件名与列定义见 spec.outputs；稳定排序，同一份盘 => 同一份输出，可 diff）：
  <root>/<plan>/<outputs.entity>    列：维度|实体|载体/路径|出处|状态数|判据类型|归属片
  <root>/<plan>/<outputs.matrix>    列：维度|实体|状态/事件|边界值|期望表现(出处)|实测|结论|证据
  <root>/<plan>/<outputs.diff>      列：编号|是什么|为什么|出处|何时消除        （只登记"允许的差异"）
  <root>/<tmp>/<outputs.summary>    计数汇总 + **未判(阻塞)块清单**（给人看的）
  <root>/<tmp>/<outputs.orphans>    文件在盘上但没人引用（典型漏检）

用法：python <skill>/scripts/coverage-enumerate.py --project-root <项目根> [--spec <spec.json>]
                                                    [--ref-md <参考规格.md>] [--dims a,b,c] [--no-ps]
      --project-root / --root
               项目根（默认 = 当前目录）。⛔ 不按本文件位置反推：本脚本现在住在 skill 里，
               按 `__file__/../..` 反推会指到 skill 目录，然后把 skill 当项目来枚举。
      --spec    【定义表】JSON（维度 / 路径 / 几何表 / 节点表 / 面板表 / 材料表 / 差异登记）。
               默认 = 本文件同目录 `config/coverage-enumerate.spec.json`（骨架；空表 ⇒ 该块 FAIL）。
      --ref-md  参考规格 md（默认在 <plan>/<plan_spec_dir>/ 下找 `*参考规格*.md`）。
      --no-ps  跳过 `resource-key-crosscheck.ps1`（离线/无 PowerShell 时的**有意**降级；不计入 blocked）
      --dims   覆盖维度表（逗号分隔），优先于 spec.dims

退出码：0 = 产出四份文件且**没有任何块被跳过**；2 = spec 缺失 / 坏 JSON / 结构性键缺失（FATAL）；
        3 = 有块因为「表空 / 文件缺 / 配置缺」**没被判**——产物照写，但⛔ 不许把它当"覆盖完整"。
"""

# ---------------------------------------------------------------- UPSTREAM NOTE（2026-09-24 上浮 → 外置）
# 本文件来自一个具体项目（下文一律称"来源项目"），上浮时做了两轮：
#   ① **参数化**：项目根 → `--project-root`；参考规格 → `--ref-md` / 自动找；
#      复用探针名 → skill 侧新名字 `resource-key-crosscheck.ps1`。
#   ② **定义表外置**（2026-09-24，第二片）：代码里**不再留任何来源项目的字面量** ——
#      维度表 / 路径族 / 资源根常量名 / 战场几何表 / 渲染节点表 / 面板清单 / 场景清单 /
#      材料表 / 打表对账 / 官方数据字段映射 / 差异登记，全部改从 `--spec` 的 JSON 读。
#      ⛔ 后果是刻意的：默认骨架里那些表是**空**的 ⇒ 对应块**明确 FAIL**（退出码 3 + 逐条 blocked），
#      ⛔ **不会**退化成"该维度没有实体"（"少判一块"和"判过且通过"在产物里长得一样 = 最贵的假绿）。
#      来源项目的实际表值仍完整保存在该项目的探针副本里；新项目把骨架复制过去填上即可。
# 保留原样的部分：实体枚举口径（目录遍历 / 正则 / png_stats）/ 不虚构未覆盖维度的声明 /
# 四份产物的列定义与稳定排序。
# 仍未做（明确登记，不藏着）：实体发现规则里的**目录层数**假设（如 `<resources>/Sprites/<族>/<目录名>`）
# 是引擎侧约定，不是项目数据；换引擎要改这里，不是改 spec。

import argparse
import io
import json
import os
import re
import subprocess
import sys
import zlib

# ---------------------------------------------------------------- 路径

def _argv_opt(name):
    """命令行预扫：模块级常量要在 import 期就算出来，所以 --root / --spec 必须先被读出来。
    ⛔ 不要改成 argparse：模块级路径常量在 main() 之前就被用到（PLAN/ENTITY_TSV/...）。"""
    for i, a in enumerate(sys.argv):
        if a == name and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
        if a.startswith(name + '='):
            return a.split('=', 1)[1]
    return ''


HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT_ARG = _argv_opt('--project-root') or _argv_opt('--root')
ROOT = os.path.abspath(_ROOT_ARG) if _ROOT_ARG else os.getcwd()

# ---------------------------------------------------------------- 定义表（spec） —— 唯一来源
# ⛔ 这里之后的所有常量都必须来自 spec：代码里再出现项目专有字面量 = 这份上浮作业白做。
DEFAULT_SPEC = os.path.join(HERE, 'config', 'coverage-enumerate.spec.json')
_SPEC_ARG = _argv_opt('--spec')
# 兼容旧命令行：`--spec` 过去指"参考规格 md"。给了 .md 就按 md 用并**明确告知**（⛔ 不静默当 JSON 读）。
_SPEC_ARG_IS_MD = bool(_SPEC_ARG) and _SPEC_ARG.lower().endswith('.md')
SPEC_PATH = DEFAULT_SPEC if (not _SPEC_ARG or _SPEC_ARG_IS_MD) else _SPEC_ARG
SPEC_ERROR = ''
MISSING_KEYS = []
MALFORMED_KEYS = []


def _load_spec(path):
    if not os.path.isfile(path):
        return {}, 'spec file missing: ' + path
    try:
        with io.open(path, encoding='utf-8-sig') as f:
            doc = json.load(f)
    except Exception as e:
        return {}, 'spec file unreadable / not JSON: %s :: %r' % (path, e)
    if not isinstance(doc, dict):
        return {}, 'spec root must be a JSON object: ' + path
    return doc, ''


SPEC, SPEC_ERROR = _load_spec(SPEC_PATH)

_NO_DEFAULT = object()


def spec_get(dotted, default=_NO_DEFAULT):
    """按点号取 spec 键。default 缺省 = 该键**必需**：缺失会登记进 MISSING_KEYS，收尾判 FATAL。"""
    cur = SPEC
    for k in dotted.split('.'):
        if not isinstance(cur, dict) or k not in cur:
            cur = None
            break
        cur = cur[k]
    if cur is None or (isinstance(cur, str) and cur == ''):
        if default is _NO_DEFAULT:
            MISSING_KEYS.append(dotted)
            return None
        return default
    return cur


def spec_table(dotted, min_rows=1):
    """必需的表：键缺失 ⇒ None（已登记）；键在但行数 < min_rows ⇒ []（调用方判 blocked，⛔ 不静默跳过）。"""
    v = spec_get(dotted)
    if v is None:
        return None
    if not isinstance(v, list):
        MALFORMED_KEYS.append(dotted + ' (expected a list)')
        return None
    return v if len(v) >= min_rows else []


# 结构性键：缺一个就没法运行 ⇒ main() 开头直接 FATAL（⛔ 不"尽力而为"地猜默认值）
REQUIRED_KEYS = [
    'dims', 'paths.plan', 'paths.plan_spec_dir', 'paths.numeric_dir', 'paths.tmp',
    'paths.client', 'paths.resources', 'paths.scripts', 'paths.editor', 'paths.scenes',
    'paths.source',
    'outputs.entity', 'outputs.matrix', 'outputs.diff', 'outputs.summary', 'outputs.orphans',
]


def spec_missing_required():
    miss = []
    for dotted in REQUIRED_KEYS:
        cur = SPEC
        for k in dotted.split('.'):
            if not isinstance(cur, dict) or k not in cur:
                cur = None
                break
            cur = cur[k]
        if cur is None or (isinstance(cur, str) and cur == ''):
            miss.append(dotted)
    return miss


def numeric_table(name):
    """spec.numeric_tables 里 id == name 的那一项（配表源件）。缺 ⇒ None（调用方判 blocked）。"""
    tabs = spec_table('numeric_tables')
    if tabs is None:
        return None
    for t in tabs:
        if isinstance(t, dict) and str(t.get('id', '')).lower() == name.lower():
            if not t.get('src'):
                MALFORMED_KEYS.append('numeric_tables[%s].src is empty' % name)
                return None
            return t
    R.blk('numeric table %s' % name, 'spec.numeric_tables has no entry with id=%r' % name)
    return None


def _rel_join(base, dotted, default):
    return os.path.join(base, spec_get(dotted, default).replace('/', os.sep))


PLAN = _rel_join(ROOT, 'paths.plan', '\u7b56\u5212')                    # 策划
SPEC_DIR = _rel_join(PLAN, 'paths.plan_spec_dir', '\u7b56\u5212\u6848')  # 策划案
NUMDIR = _rel_join(PLAN, 'paths.numeric_dir', '\u6570\u503c\u6587\u6863')  # 数值文档
ENTITY_TSV = os.path.join(PLAN, spec_get('outputs.entity', '\u5b9e\u4f53\u6e05\u5355.tsv'))
MATRIX_TSV = os.path.join(PLAN, spec_get('outputs.matrix', '\u72b6\u6001\u77e9\u9635.tsv'))
DIFF_TSV = os.path.join(PLAN, spec_get('outputs.diff', '\u5dee\u5f02\u767b\u8bb0.tsv'))

TMP = _rel_join(ROOT, 'paths.tmp', '.ai-tmp/test')
SUMMARY = os.path.join(TMP, spec_get('outputs.summary', 'coverage-enumerate-summary.txt'))
ORPHANS = os.path.join(TMP, spec_get('outputs.orphans', 'coverage-enumerate-orphans.tsv'))

CLIENT = _rel_join(ROOT, 'paths.client', 'client')
RES = _rel_join(CLIENT, 'paths.resources', 'Assets/Resources')
SCRIPTS = _rel_join(CLIENT, 'paths.scripts', 'Assets/Scripts')
EDITOR = _rel_join(CLIENT, 'paths.editor', 'Assets/Editor')
SCENES = _rel_join(CLIENT, 'paths.scenes', 'Assets/Scenes')
SOURCE = _rel_join(ROOT, 'paths.source', '\u539f\u7248\u8d44\u6e90')     # 原版资源
_SPRITE_PACK = spec_get('paths.source_sprite_pack', '')
_SPRITE_SUB = spec_get('paths.source_sprite_subdir', ['assets', 'sc'])
SC_SRC = os.path.join(SOURCE, _SPRITE_PACK, *[str(s) for s in _SPRITE_SUB]) if _SPRITE_PACK else ''
_API_DIR = spec_get('paths.source_api_dir', '')
API_JSON = _rel_join(ROOT, 'paths.source_api_dir', '') if _API_DIR else ''


def code_file(dotted):
    """<spec.code_files.*> 的相对段 → 绝对路径。空 ⇒ ''（调用方必须判 blocked）。"""
    segs = spec_get(dotted, [])
    if not isinstance(segs, list) or not segs:
        return ''
    return os.path.join(SCRIPTS, *[str(s) for s in segs])


RESPATHS = code_file('code_files.res_paths')
GAMECONST = code_file('code_files.game_const')
BATTLEVIEW = code_file('code_files.battlefield_view')
_CHECK_SCRIPT = spec_get('cross_check.script', 'resource-key-crosscheck.ps1')
CHECKUI = os.path.join(HERE, _CHECK_SCRIPT) if _CHECK_SCRIPT else ''
UI_FAMILIES_CONFIG = _argv_opt('--ui-families-config') or spec_get('cross_check.families_config', '')

# 参考规格 md：--ref-md 优先；否则在 策划案/ 下找第一个 `*参考规格*.md`（'参考规格' 用 code point 拼，
# 本文件才能保持可移植 / 不夹带项目词）；再没有就退到一个不存在的路径 ⇒ 下游按"读不到"处理，不虚构。
_REF_SPEC_NAME = '\u53c2\u8003\u89c4\u683c'
REF_MD = _argv_opt('--ref-md') or (_SPEC_ARG if _SPEC_ARG_IS_MD else '')
if not REF_MD and os.path.isdir(SPEC_DIR):
    for _n in sorted(os.listdir(SPEC_DIR)):
        if _REF_SPEC_NAME in _n and _n.lower().endswith('.md'):
            REF_MD = os.path.join(SPEC_DIR, _n)
            break
if not REF_MD:
    REF_MD = os.path.join(SPEC_DIR, _REF_SPEC_NAME + '.md')

# 维度取值（scaffold 定死；spec.dims 可覆盖，--dims 再覆盖）
DIMS = list(spec_get('dims', ['D1\u8d44\u6e90', 'D2\u51e0\u4f55', 'D3\u6750\u8d28', 'D4UI',
                              'D5\u52a8\u753b', 'D6\u7279\u6548', 'D7\u97f3\u4e50', 'D8\u97f3\u6548',
                              'D9\u78b0\u649e', 'D10\u903b\u8f91', 'D11\u8f93\u5165', 'D12\u6d41\u7a0b',
                              'S1\u6570\u503c', 'S2\u6027\u80fd', 'S3\u8bbe\u7f6e']))

# ---------------------------------------------------------------- 工具

def rd_text(p):
    with io.open(p, 'r', encoding='utf-8', errors='replace') as f:
        return f.read()

def rd_bytes(p):
    with open(p, 'rb') as f:
        return f.read()

def read_tsv(p):
    """返回 (header, rows)；rows 里跳过全部为 '-' 的占位行。"""
    t = rd_text(p)
    lines = [l for l in t.split('\n')]
    if lines and lines[-1] == '':
        lines.pop()
    rows = [l.split('\t') for l in lines]
    if not rows:
        return [], []
    header = rows[0]
    body = [r for r in rows[1:] if not all((c.strip() in ('', '-')) for c in r)]
    return header, body

def read_src_table(p):
    """读《数值文档》源表（xx_cs.txt）：行0=列名，行1=类型，行2=cs，行3=说明，行4+=数据。
    ⛔ 只保留首列为纯数字 id 的数据行（类型/cs/说明行首列不是数字）。"""
    t = rd_text(p)
    lines = [l for l in t.split('\n')]
    while lines and lines[-1].strip() == '':
        lines.pop()
    if not lines:
        return [], []
    header = lines[0].split('\t')
    body = []
    for l in lines[1:]:
        if not l.strip():
            continue
        cells = l.split('\t')
        if cells and re.match(r'^\d+$', cells[0].strip()):
            body.append(cells)
    return header, body

def rel(p):
    return os.path.relpath(p, ROOT).replace('\\', '/')

def walk_files(base, ext=None):
    out = []
    if not os.path.isdir(base):
        return out
    for dp, dn, fn in os.walk(base):
        dn[:] = [d for d in dn if d != '__pycache__']
        for n in fn:
            if ext is None or n.lower().endswith(ext):
                out.append(os.path.join(dp, n))
    return sorted(out)

def walk_dirs(base):
    out = []
    if not os.path.isdir(base):
        return out
    for dp, dn, fn in os.walk(base):
        dn[:] = [d for d in dn if d != '__pycache__']
        for d in dn:
            out.append(os.path.join(dp, d))
    return sorted(out)

_png_cache = {}
def png_stats(p):
    """(w,h,nonalpha_pixels,all_near_white) —— 纯 stdlib PNG 解码（zlib），只支持 8bit RGBA/RGB/灰度。"""
    if p in _png_cache:
        return _png_cache[p]
    val = None
    try:
        b = rd_bytes(p)
        if b[:8] != b'\x89PNG\r\n\x1a\n':
            val = None
        else:
            pos = 8
            w = h = bitd = ctype = None
            idat = b''
            while pos + 8 <= len(b):
                ln = int.from_bytes(b[pos:pos + 4], 'big')
                typ = b[pos + 4:pos + 8]
                data = b[pos + 8:pos + 8 + ln]
                if typ == b'IHDR':
                    w = int.from_bytes(data[0:4], 'big')
                    h = int.from_bytes(data[4:8], 'big')
                    bitd = data[8]
                    ctype = data[9]
                elif typ == b'IDAT':
                    idat += data
                elif typ == b'IEND':
                    break
                pos += 12 + ln
            if w is None or bitd != 8 or ctype not in (0, 2, 4, 6):
                val = (w, h, None, None)
            else:
                raw = zlib.decompress(idat)
                ch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
                stride = w * ch
                prev = bytearray(stride)
                nonalpha = 0
                white = True
                off = 0
                for y in range(h):
                    ft = raw[off]; off += 1
                    line = bytearray(raw[off:off + stride]); off += stride
                    if ft == 1:
                        for i in range(ch, stride):
                            line[i] = (line[i] + line[i - ch]) & 0xFF
                    elif ft == 2:
                        for i in range(stride):
                            line[i] = (line[i] + prev[i]) & 0xFF
                    elif ft == 3:
                        for i in range(stride):
                            a = line[i - ch] if i >= ch else 0
                            line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
                    elif ft == 4:
                        for i in range(stride):
                            a = line[i - ch] if i >= ch else 0
                            c = prev[i - ch] if i >= ch else 0
                            bb = prev[i]
                            pa, pb, pc = abs(bb - c), abs(a - c), abs(a + bb - 2 * c)
                            pr = a if (pa <= pb and pa <= pc) else (bb if pb <= pc else c)
                            line[i] = (line[i] + pr) & 0xFF
                    if ctype == 6:
                        for x in range(w):
                            al = line[x * 4 + 3]
                            if al > 8:
                                nonalpha += 1
                                if not (line[x * 4] > 235 and line[x * 4 + 1] > 235 and line[x * 4 + 2] > 235):
                                    white = False
                    elif ctype == 4:
                        for x in range(w):
                            if line[x * 2 + 1] > 8:
                                nonalpha += 1
                                if line[x * 2] < 235:
                                    white = False
                    else:
                        nonalpha = w * h
                        total = sum(line)
                        white = white and (total / stride) > 235
                    prev = line
                val = (w, h, nonalpha, bool(white) if nonalpha > 0 else False)
    except Exception:
        val = None
    _png_cache[p] = val
    return val

class Rows:
    def __init__(self):
        self.ent = []   # 实体清单
        self.mat = []   # 状态矩阵
        self.diff = []  # 差异登记
        self.orphans = []
        self.note = []
        self.blocked = []   # 因为「表空 / 文件缺 / 配置缺」而**没被判**的块 ⇒ 收尾非 0 退出

    def add_e(self, dim, entity, path, origin, nstate, judge, slice_):
        self.ent.append([dim, entity, path, origin, str(nstate), judge, slice_])

    def add_m(self, dim, entity, state, boundary, expect, actual, verdict, ev):
        self.mat.append([dim, entity, state, boundary, expect, actual, verdict, ev])

    def blk(self, block, why):
        """登记一个没被判的块。⛔ 不许静默：blocked 数会进 summary、note 区，并让退出码 = 3。"""
        self.blocked.append('%s: %s' % (block, why))
        self.note.append('blocked: %s -- %s' % (block, why))

    def degrade(self, why):
        """**有意**降级（如 --no-ps）：同样写进 note，但不计入 blocked（不该让有意降级变成红）。"""
        self.note.append('degraded: ' + why)

R = Rows()

# ---------------------------------------------------------------- 出处常量（唯一标准答案文件）

ORIGIN_SPEC = '\u53c2\u8003\u89c4\u683c.md'
def spec_sec(n):
    return u'%s \u00a7%s' % (ORIGIN_SPEC, n)

# ---------------------------------------------------------------- .cs 语料（引用扫描）

def build_cs_corpus():
    """散文 + 常量表。常量做**迭代展开**（处理 `CardsRoot = SpritesRoot + "/Cards"` 这类拼接）。"""
    files = walk_files(SCRIPTS, '.cs') + walk_files(EDITOR, '.cs')
    blob = '\n'.join(rd_text(f) for f in files)
    raw = {}
    for m in re.finditer(r'const\s+string\s+(\w+)\s*=\s*([^;]+);', blob):
        raw.setdefault(m.group(1), m.group(2).strip())
    vals = {}
    for _ in range(10):
        改 = False
        for n, rhs in raw.items():
            if n in vals:
                continue
            toks = re.findall(r'"[^"]*"|[A-Za-z_]\w*', rhs)
            if toks and all(t.startswith('"') or t in vals for t in toks):
                vals[n] = ''.join(t[1:-1] if t.startswith('"') else vals[t] for t in toks)
                改 = True
        if not 改:
            break
    return blob, vals

CS_BLOB, CS_CONSTS = build_cs_corpus()
# 数据驱动引用：素材目录名可能只出现在《数值文档》配表（sprite_dir 列）而不在 .cs 里
# （实测某单位的精灵目录仅由 unit 源表的 sprite_dir 数据引用）⇒ 语料并入配表，
# 避免「代码字面量」单口径把这类目录误判成孤儿（口径写在 spec.allowed_differences / resource_note_dirs）。
if os.path.isdir(NUMDIR):
    for _n in sorted(os.listdir(NUMDIR)):
        if _n.endswith('.txt'):
            CS_BLOB += '\n' + rd_text(os.path.join(NUMDIR, _n))

def referenced_token(name):
    """目录名/常量值是否在 .cs 语料里出现（作为字面量片段）。"""
    return name in CS_BLOB

# ---------------------------------------------------------------- D1 资源/资产

def _spec_rel(base, dotted, default_segs):
    """spec 里的「相对段数组」→ 绝对路径。空数组 ⇒ ''（调用方判 blocked）。"""
    segs = spec_get(dotted, default_segs)
    if not isinstance(segs, list) or not segs:
        return ''
    return os.path.join(base, *[str(s) for s in segs])


# 资源族表（spec.resource_groups）：每项 {name, rel:[段...], mode:'dir', ext:'.png'}
# ⛔ 来源项目的族表已随外置移除：spec 里是空表 ⇒ D1 报 blocked（退出码非 0），⛔ 不静默当"没有实体"。
RES_GROUPS = []
for _g in (spec_table('resource_groups') or []):
    if not isinstance(_g, dict) or not _g.get('rel'):
        MALFORMED_KEYS.append('resource_groups[] item needs {name, rel:[...]}')
        continue
    RES_GROUPS.append((_g.get('name') or os.path.basename(str(_g['rel'][-1])),
                       os.path.join(RES, *[str(s) for s in _g['rel']]),
                       _g.get('mode', 'dir'),
                       _g.get('ext', '.png')))

UI_DIR = _spec_rel(RES, 'ui.rel', ['Sprites', 'Ui'])
SOUND_DIR = _spec_rel(RES, 'sound.rel', ['Sound'])
UI_EXT = spec_get('ui.ext', '.png')
SOUND_EXT = spec_get('sound.ext', '.ogg')
PANEL_DIR = spec_get('panel_dir', ['UI', 'Panels'])
LANDED_EXT = {}   # 已落地精灵目录 → 该族的扩展名（逐族登记，供 D3 抽首帧）

def d1_resources():
    if not RES_GROUPS:
        R.blk('D1 resource_groups', 'spec.resource_groups is empty -> no sprite family is enumerated')
        return {}
    landed_dirs = {}   # bare dir name -> path
    for grp, base, mode, ext in RES_GROUPS:
        for d in walk_dirs(base):
            files = walk_files(d, ext)
            if not files:
                continue
            name = os.path.basename(d)
            landed_dirs[name] = d
            LANDED_EXT[d] = ext
            ref = referenced_token(name)
            R.add_e('D1\u8d44\u6e90', name, rel(d), spec_sec(6) + ' / ResPaths.cs',
                    len(files), '\u811a\u672c\u65ad\u8a00', 'AE1-D1')
            if not ref:
                R.orphans.append([name, rel(d), str(len(files)),
                                  '\u76ee\u5f55\u540d\u672a\u5728\u4efb\u4f55 .cs \u91cc\u51fa\u73b0',
                                  '\u811a\u672c(cs-corpus)', '\u4e25\u91cd'])

    # 「明知会被 .cs 字面量口径误判成孤儿」的目录：解释从 spec 读（⛔ 不写死在代码里）
    for _nd in (spec_get('resource_note_dirs', []) or []):
        if not isinstance(_nd, dict) or not _nd.get('name'):
            MALFORMED_KEYS.append('resource_note_dirs[] item needs {name, note}')
            continue
        R.note.append('%s: %s' % (_nd['name'], _nd.get('note', '')))

    # 音频：逐个文件
    if not SOUND_DIR:
        R.blk('D1 sound', 'spec.sound.rel is empty -> no audio file is enumerated')
    else:
        for f in walk_files(SOUND_DIR, SOUND_EXT):
            n = os.path.basename(f)[:-len(SOUND_EXT)] if SOUND_EXT else os.path.basename(f)
            ref = referenced_token(n)
            R.add_e('D1\u8d44\u6e90', n, rel(f), spec_sec(7) + ' S27 / AudioPaths.cs',
                    1, '\u811a\u672c\u65ad\u8a00', 'AE1-D1')
            if not ref:
                R.orphans.append([n, rel(f), '1', '\u97f3\u9891\u540d\u672a\u5728\u4efb\u4f55 .cs \u91cc\u51fa\u73b0',
                                  '\u811a\u672c(cs-corpus)', '\u4e25\u91cd'])
    return landed_dirs

def d1_ui_per_frame():
    """UI 逐帧目录下逐文件登记（键→路径按帧引用，帧级粒度才有意义）。"""
    if not UI_DIR:
        R.blk('D1 ui per frame', 'spec.ui.rel is empty -> UI frames are not enumerated')
        return []
    files = walk_files(UI_DIR, UI_EXT)
    landed_by = spec_get('ui.landed_by', 'the asset-copy step')
    for f in files:
        relp = rel(f)
        R.add_e('D1\u8d44\u6e90', os.path.basename(f)[:-len(UI_EXT)] if UI_EXT else os.path.basename(f), relp,
                os.path.basename(RESPATHS or 'ResPaths.cs') + ' / ' + landed_by, 2,
                '\u811a\u672c\u65ad\u8a00', 'AE1-D1')
    return files

def d1_sources():
    """原版资源/** 的来源登记（顶层来源包，出处=参考规格 §9）。"""
    for d in sorted(os.listdir(SOURCE)) if os.path.isdir(SOURCE) else []:
        p = os.path.join(SOURCE, d)
        if not os.path.isdir(p):
            continue
        n = len(walk_files(p))
        R.add_e('D1\u8d44\u6e90', d, rel(p), spec_sec(9), n,
                '\u53c2\u8003\u7269\u6bd4\u5bf9', 'AE1-D1')

def d1_respaths_keys():
    """ResPaths 键 ↔ 实际文件（复用既有键对账逻辑的同口径正则 + 自算存在性）。"""
    if not RESPATHS or not os.path.isfile(RESPATHS):
        R.blk('D1 ResPaths', 'spec.code_files.res_paths is empty or the file is missing: %s' % (RESPATHS or '<empty>'))
        return
    src = rd_text(RESPATHS)
    dirs = dict(re.findall(r'public const string (Ui\w+Dir) = "([^"]+)";', src))
    srcs = dict(re.findall(r'public const string (UiSrc\w+) = "([^"]+)";', src))
    keys = []
    for m in re.finditer(r'public static string (\w+) \{ get \{ return UiFrame\((\w+), (\w+), (\d+)\); \} \}', src):
        key, d, s, fr = m.group(1), dirs.get(m.group(2)), srcs.get(m.group(3)), int(m.group(4))
        if not d or not s:
            keys.append((key, None, False, m.group(2) + '/' + m.group(3)))
            continue
        relp = '/'.join([str(s) for s in spec_get('ui.rel', ['Sprites', 'Ui'])]) + '/%s/%s/frame_%03d' % (d, s, fr)
        absp = os.path.join(UI_DIR, d, s, 'frame_%03d.png' % fr)
        keys.append((key, relp, os.path.isfile(absp), None))
    for key, relp, exists, bad in keys:
        origin = os.path.basename(RESPATHS or 'ResPaths.cs') + ':UiFrame'
        R.add_e('D1\u8d44\u6e90', key, relp or ('<unresolved %s>' % bad), origin, 2,
                '\u811a\u672c\u65ad\u8a00', 'AE1-D1')
        if relp is not None and not exists:
            verdict = '\u4e0d\u4e00\u81f4(\u952e\u6307\u5411\u7684\u6587\u4ef6\u4e0d\u5728\u76d8\u4e0a)'
            ev = 'Test-Path False: ' + relp + '.png'
        elif relp is None:
            verdict = '\u4e0d\u4e00\u81f4(\u57fa\u5ea7\u5e38\u91cf\u65e0\u6cd5\u89e3\u6790)'
            ev = 'unresolved ' + str(bad)
        else:
            verdict = '\u4e00\u81f4'
            ev = 'Test-Path True: ' + relp + '.png'
        R.add_m('D1\u8d44\u6e90', key, '\u952e\u2192\u6587\u4ef6\u5b58\u5728',
                'exists / missing', 'ResPaths \u952e\u5fc5\u987b\u6307\u5411\u76d8\u4e0a\u5b58\u5728\u7684 frame',
                ev, verdict, 'coverage-enumerate.py / resource-key-crosscheck.ps1 A')

    # 资源根常量（spec.res_paths.root_keys）：名字从 spec 读，取值从 ResPaths.cs 的 RHS 递归展开
    # （把已知 const 名替换成其字面值，处理 `SpritesRoot + "/Towers/" + TowerSpriteDir` 这类拼接）。
    def resolve(rhs, depth=0):
        if depth > 6:
            return None
        out = []
        for tok in re.findall(r'"[^"]*"|[A-Za-z_]\w*', rhs):
            if tok.startswith('"'):
                out.append(tok[1:-1])
            elif tok in CS_CONSTS:
                out.append(CS_CONSTS[tok])
            elif tok in ('true', 'false'):
                out.append(tok)
            else:
                return None
        return ''.join(out)

    root_keys = spec_table('res_paths.root_keys') or []
    if not root_keys:
        R.blk('D1 resource roots',
              'spec.res_paths.root_keys is empty -> no resource-root constant is checked')
    for m in re.finditer(r'public const string (\w+) = ([^;]+);', src):
        key, rhs = m.group(1), m.group(2).strip()
        if key not in root_keys:
            continue
        path = resolve(rhs)
        if path is None:
            R.note.append('blocked: cannot resolve ResPaths.%s = %s' % (key, rhs))
            R.add_m('D1\u8d44\u6e90', key, '\u8d44\u6e90\u6839\u5b58\u5728', 'exists',
                    'ResPaths \u8d44\u6e90\u6839\u5fc5\u987b\u80fd\u89e3\u6790\u4e14\u5728\u76d8\u4e0a',
                    'unresolved rhs=' + rhs, '\u963b\u585e(\u5e38\u91cf\u7f16\u8f91\u94fe\u65e0\u6cd5\u89e3\u6790)',
                    'coverage-enumerate.py')
            continue
        absp = os.path.join(RES, path.replace('/', os.sep))
        ok = os.path.isdir(absp) or os.path.isfile(absp) or os.path.isfile(absp + '.png')
        res_prefix = spec_get('paths.resources', 'Assets/Resources').rstrip('/') + '/'
        R.add_e('D1\u8d44\u6e90', key, res_prefix + path, os.path.basename(RESPATHS or 'ResPaths.cs'), 1,
                '\u811a\u672c\u65ad\u8a00', 'AE1-D1')
        R.add_m('D1\u8d44\u6e90', key, '\u8d44\u6e90\u6839\u5b58\u5728', 'exists',
                'ResPaths \u8d44\u6e90\u6839\u5fc5\u987b\u5728\u76d8\u4e0a',
                'Test-Path ' + str(ok) + ': ' + res_prefix + path,
                '\u4e00\u81f4' if ok else '\u4e0d\u4e00\u81f4(\u8d44\u6e90\u6839\u4e0d\u5b58\u5728)',
                'coverage-enumerate.py')

def d1_source_vs_landed(landed_dirs):
    """原版素材目录 → 是否落地（典型漏检：源有、我们没搬）。"""
    if not SC_SRC:
        R.blk('D1 source-vs-landed',
              'spec.paths.source_sprite_pack is empty -> the source sprite tree is unknown')
        return
    if not os.path.isdir(SC_SRC):
        R.blk('D1 source-vs-landed', 'source sprite dir missing: ' + SC_SRC)
        return
    src_names = sorted(d for d in os.listdir(SC_SRC) if os.path.isdir(os.path.join(SC_SRC, d)))
    landed_all = set(landed_dirs.keys()) | ({os.path.basename(d) for d in walk_dirs(UI_DIR)} if UI_DIR else set())
    for n in src_names:
        R.add_e('D1\u8d44\u6e90', n, rel(os.path.join(SC_SRC, n)),
                spec_sec(9) + ' / ' + _SPRITE_PACK, 2, '\u53c2\u8003\u7269\u6bd4\u5bf9', 'AE1-D1')
        if n not in landed_all:
            R.add_m('D1\u8d44\u6e90', n, '\u6e90\u76ee\u5f55\u662f\u5426\u5df2\u843d\u5730',
                    '\u843d\u5730 / \u672a\u843d\u5730',
                    '\u53c2\u8003\u89c4\u683c \u00a76 \u5217\u51fa\u7684\u7d20\u6750\u76ee\u5f55\u5e94\u843d\u5730',
                    '\u672a\u843d\u5730\uff08Resources \u4e0b\u65e0\u540c\u540d\u76ee\u5f55\uff09',
                    '\u672a\u5224(\u5f85\u5224\u5b9a\u662f\u5426\u5c5e\u672c\u9879\u76ee\u8303\u56f4)',
                    'coverage-enumerate.py (source-vs-landed)')
        else:
            R.add_m('D1\u8d44\u6e90', n, '\u6e90\u76ee\u5f55\u662f\u5426\u5df2\u843d\u5730',
                    '\u843d\u5730 / \u672a\u843d\u5730', '\u5df2\u843d\u5730', '\u5df2\u843d\u5730',
                    '\u4e00\u81f4', 'coverage-enumerate.py')

def d1_unit_sprite_dirs():
    """unit 源表的 sprite_dir 列 → 盘上是否有该目录（配表与素材是否对齐）。"""
    nt = numeric_table('unit')
    if nt is None:
        return
    p = os.path.join(NUMDIR, nt['src'])
    if not os.path.isfile(p):
        R.blk('D1 sprite_dir', 'numeric source table missing: ' + p)
        return
    header, rows = read_src_table(p)
    col_key = spec_get('numeric_columns.key', 'key')
    col_sd = spec_get('numeric_columns.sprite_dir', 'sprite_dir')
    if col_sd not in header or col_key not in header:
        R.blk('D1 sprite_dir', 'source table %s lacks column %r or %r' % (nt['src'], col_sd, col_key))
        return
    roots = spec_get('sprite_dir_roots', []) or []
    if not roots:
        R.blk('D1 sprite_dir', 'spec.sprite_dir_roots is empty -> sprite_dir cannot be resolved')
        return
    i_sd = header.index(col_sd)
    seen = set()
    for r in rows:
        sd = r[i_sd].strip()
        if not sd or sd in seen:
            continue
        seen.add(sd)
        for one in sd.split(';'):
            one = one.strip()
            if not one:
                continue
            cand = [os.path.join(RES, *[str(s) for s in root]) for root in roots
                    if isinstance(root, list) and root]
            hit = next((c for c in cand if os.path.isdir(c)), None)
            R.add_e('D1\u8d44\u6e90', one, rel(hit) if hit else 'Resources/**/' + one,
                    nt['src'] + ':' + col_sd + ' / ' + spec_sec(6), 1, '\u811a\u672c\u65ad\u8a00', 'AE1-D1')
            R.add_m('D1\u8d44\u6e90', one, 'sprite_dir \u662f\u5426\u6709\u5bf9\u5e94\u76ee\u5f55',
                    'dir hit / miss', nt['src'] + '.' + col_sd + ' \u5fc5\u987b\u5728\u76d8\u4e0a\u5b58\u5728',
                    ('dir hit: ' + rel(hit)) if hit else 'dir MISS',
                    '\u4e00\u81f4' if hit else '\u4e0d\u4e00\u81f4(sprite_dir \u5728\u76d8\u4e0a\u4e0d\u5b58\u5728)',
                    'coverage-enumerate.py')

def run_check_ui_keys():
    """复用既有探针（不重写），把它的四向检查折进 D1。
    ⚠️ 上浮后该探针改名 `resource-key-crosscheck.ps1`，并且**必须**给 -Config(路径族配置)：
    没给就必须报 blocked（⛔ 不许静默跳过 —— "少判一块"和"判过且通过"在产物里长得一样）。"""
    if not os.path.isfile(CHECKUI):
        R.blk('D1 key cross-check', 'cross-check script missing: ' + (CHECKUI or '<not configured>'))
        return
    if not UI_FAMILIES_CONFIG:
        R.blk('D1 key cross-check', 'needs -Config (pass --ui-families-config <families.json>'
                                    ' or set spec.cross_check.families_config) -- this block is NOT judged')
        return
    try:
        out = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                              '-File', CHECKUI, '-ProjectRoot', ROOT,
                              '-Config', UI_FAMILIES_CONFIG, '-Quiet'],
                             cwd=ROOT, capture_output=True, timeout=180)
        txt = out.stdout.decode('utf-8', 'replace')
    except Exception as e:
        R.blk('D1 key cross-check', 'resource-key-crosscheck.ps1 failed: %r' % (e,))
        return
    for line in txt.splitlines():
        line = line.rstrip()
        # 两种前缀都收：上浮前是 "B) landed png reachable"，上浮后是 "B) landed files reachable"
        if line.startswith('B) landed png reachable') or line.startswith('B) landed files reachable'):
            R.note.append('resource-key-crosscheck: ' + line)
        if line.strip().startswith('unreferenced:'):
            for item in line.split(':', 1)[1].split(','):
                item = item.strip()
                if item:
                    R.orphans.append(['(ui) ' + item, (rel(UI_DIR) + '/' + item) if UI_DIR else item, '1',
                                      'UI \u76ee\u5f55\u4e0b\u843d\u5730\u4f46\u65e0\u4efb\u4f55\u5f15\u7528',
                                      'resource-key-crosscheck.ps1 B', '\u4e25\u91cd'])
        if line.strip().startswith('missing:'):
            for item in line.split(':', 1)[1].split(','):
                item = item.strip()
                if item:
                    R.add_m('D1\u8d44\u6e90', item, '\u4efb\u610f .cs \u5f15\u7528\u2192\u6587\u4ef6\u5b58\u5728',
                            'exists', 'ResPaths/\u5b57\u9762\u91cf\u5f15\u7528\u7684\u8def\u5f84\u5fc5\u987b\u5b58\u5728',
                            'missing on disk', '\u4e0d\u4e00\u81f4(.cs \u5f15\u7528\u4e86\u4e0d\u5b58\u5728\u7684\u8d44\u6e90)',
                            'resource-key-crosscheck.ps1 D')

# ---------------------------------------------------------------- D2 几何与场景
# ⛔ 两张表都来自 spec，代码里不留任何实体名：
#   battlefield_geometry[] = {entity(完整显示名), consts:[GameConst 里必须存在的常量名],
#                             value(几何值描述), literals:[参考规格里必须逐字出现的字面量]}
#   battlefield_nodes[]    = {entity, tokens:[视图文件里必须出现的 token], source(出处描述)}
# 表空 / 常量文件名缺失 / 视图文件名缺失 ⇒ 一律 blocked（⛔ 不退化成"该维度没有实体"）。


def _bad_item(key, need):
    MALFORMED_KEYS.append('%s[] item needs %s' % (key, need))


def d2_battlefield():
    geo = spec_table('battlefield_geometry') or []
    nodes = spec_table('battlefield_nodes') or []
    if not geo:
        R.blk('D2 battlefield geometry', 'spec.battlefield_geometry is empty -> no geometry entity is judged')
    if not nodes:
        R.blk('D2 battlefield nodes', 'spec.battlefield_nodes is empty -> no render node is judged')
    if not geo and not nodes:
        return
    if not GAMECONST or not os.path.isfile(GAMECONST):
        R.blk('D2 battlefield', 'spec.code_files.game_const empty/missing: %s' % (GAMECONST or '<empty>'))
        return
    gc = rd_text(GAMECONST)
    view = BATTLEVIEW if (BATTLEVIEW and os.path.isfile(BATTLEVIEW)) else ''
    if not view:
        R.blk('D2 battlefield', 'spec.code_files.battlefield_view empty/missing: %s' % (BATTLEVIEW or '<empty>'))
        return
    av = rd_text(view)
    if os.path.isfile(REF_MD):
        ref = rd_text(REF_MD)
    else:
        ref = ''
        R.blk('D2 reference md', 'reference md not readable: ' + REF_MD
                                 + ' -> the "reference states this literal" rows are NOT judged')

    for it in geo:
        if not isinstance(it, dict) or not it.get('entity') or not isinstance(it.get('consts'), list) or not it['consts']:
            _bad_item('battlefield_geometry', '{entity, consts:[...], value, literals:[...]}')
            continue
        name, consts = it['entity'], it['consts']
        val = str(it.get('value', ''))
        lit = [str(x) for x in (it.get('literals') or [])]
        found = [(c, c in gc) for c in consts]
        ok = all(x[1] for x in found)
        R.add_e('D2\u51e0\u4f55', name, rel(GAMECONST), spec_sec(2), 3,
                '\u811a\u672c\u65ad\u8a00', 'AE1-D2')
        R.add_m('D2\u51e0\u4f55', name,
                '\u5e38\u91cf\u5b58\u5728\u4e0e\u53d6\u503c', val,
                spec_sec(2) + '\uff1a' + val + ' \u5fc5\u987b\u6709\u5bf9\u5e94\u5e38\u91cf',
                ('consts=%s' % ','.join('%s=%s' % (c, o) for c, o in found)),
                '\u4e00\u81f4' if ok else '\u4e0d\u4e00\u81f4(\u5e38\u91cf\u7f3a\u5931)',
                'coverage-enumerate.py (' + os.path.basename(GAMECONST) + ')')
        # 参考规格对应节是否逐字写着该几何值（参考物自带判据）
        miss = [s for s in lit if s not in ref]
        R.add_m('D2\u51e0\u4f55', name,
                '\u53c2\u8003\u89c4\u683c \u5b57\u9762\u503c', '/'.join(lit),
                spec_sec(2) + ' \u5fc5\u987b\u9010\u5b57\u5199\u7740\u8be5\u51e0\u4f55\u503c',
                'missing=' + (','.join(miss) if miss else 'none'),
                '\u672a\u5224(\u53c2\u8003\u89c4\u683c\u8bfb\u4e0d\u5230)' if not ref
                else ('\u4e00\u81f4' if not miss else '\u4e0d\u4e00\u81f4(\u53c2\u8003\u89c4\u683c\u7f3a\u8be5\u5b57\u9762\u503c)'),
                'coverage-enumerate.py (REF_MD)')

    for it in nodes:
        if not isinstance(it, dict) or not it.get('entity') or not isinstance(it.get('tokens'), list) or not it['tokens']:
            _bad_item('battlefield_nodes', '{entity, tokens:[...], source}')
            continue
        name, toks = it['entity'], [str(t) for t in it['tokens']]
        src = str(it.get('source', ''))
        miss = [t for t in toks if t not in av]
        ok = not miss
        R.add_e('D2\u51e0\u4f55', name, rel(view), spec_sec(2) + ' + ' + os.path.basename(view),
                2, '\u811a\u672c\u65ad\u8a00+\u5e76\u6392\u56fe', 'AE1-D2')
        R.add_m('D2\u51e0\u4f55', name,
                '\u8be5\u6709\u7684\u8282\u70b9\u662f\u5426\u5b58\u5728', 'exists / missing',
                spec_sec(2) + ' \u8981\u6c42\u7684\u51e0\u4f55\u7269\u4ef6\u5fc5\u987b\u751f\u6210',
                'source=' + src + ' | tokens ok' if ok else ('MISSING tokens=' + ','.join(miss)),
                '\u4e00\u81f4' if ok else '\u4e0d\u4e00\u81f4(\u4ee3\u7801\u91cc\u627e\u4e0d\u5230\u8be5\u8282\u70b9)',
                'coverage-enumerate.py (' + os.path.basename(view) + ')')


def d2_panels():
    panels = spec_table('panels') or []
    if not panels:
        R.blk('D2 panels', 'spec.panels is empty -> no panel is enumerated')
    for it in panels:
        if not isinstance(it, dict) or not it.get('name'):
            _bad_item('panels', '{name, section}')
            continue
        name, sec = it['name'], str(it.get('section', ''))
        p = os.path.join(SCRIPTS, *[str(s) for s in (PANEL_DIR if isinstance(PANEL_DIR, list) else [])], name + '.cs')
        ok = os.path.isfile(p)
        R.add_e('D2\u51e0\u4f55', '\u9762\u677f\uff1a' + name,
                rel(p) if ok else '(missing) ' + rel(p),
                '\u53c2\u8003\u89c4\u683c / ' + sec, 3,
                '\u5e76\u6392\u56fe', 'AE1-D2')
        R.add_m('D2\u51e0\u4f55', '\u9762\u677f\uff1a' + name, '\u5b58\u5728\u6027(\u8be5\u6709\u7684\u6709\u6ca1\u6709)',
                'exists / missing', '\u53c2\u8003\u89c4\u683c\u5217\u4e3a [\u6838\u5fc3] \u7684\u754c\u9762\u5fc5\u987b\u5b58\u5728',
                ('file exists: ' + rel(p)) if ok else 'file MISSING',
                '\u4e00\u81f4' if ok else '\u4e0d\u4e00\u81f4(\u754c\u9762\u6587\u4ef6\u7f3a\u5931)',
                'coverage-enumerate.py')

    # 场景生成器 + 场景文件
    sb_segs = spec_get('scene_builder', [])
    scenes = spec_table('scenes') or []
    if not isinstance(sb_segs, list) or not sb_segs:
        R.blk('D2 scene builder', 'spec.scene_builder is empty')
    if not scenes:
        R.blk('D2 scenes', 'spec.scenes is empty -> no scene file is enumerated')
    if isinstance(sb_segs, list) and sb_segs:
        sb = os.path.join(EDITOR, *[str(s) for s in sb_segs])
        R.add_e('D2\u51e0\u4f55', '\u573a\u666f\u751f\u6210\u5668 ' + os.path.basename(sb), rel(sb), spec_sec(7),
                1, '\u811a\u672c\u65ad\u8a00', 'AE1-D2')
        R.add_m('D2\u51e0\u4f55', '\u573a\u666f\u751f\u6210\u5668 ' + os.path.basename(sb), '\u5b58\u5728\u6027',
                'exists', '\u9996\u5c4f\u5e8f\u5217\u5fc5\u987b\u88ab\u914d\u7f6e\u51fa\u6765',
                'exists=' + str(os.path.isfile(sb)),
                '\u4e00\u81f4' if os.path.isfile(sb) else '\u4e0d\u4e00\u81f4(\u573a\u666f\u751f\u6210\u5668\u7f3a\u5931)',
                'coverage-enumerate.py')
    for it in scenes:
        s = it if isinstance(it, str) else (it.get('name') if isinstance(it, dict) else '')
        if not s:
            _bad_item('scenes', 'a scene name (string) or {name}')
            continue
        p = os.path.join(SCENES, s + '.unity')
        ok = os.path.isfile(p)
        R.add_e('D2\u51e0\u4f55', '\u573a\u666f\uff1a' + s, rel(p) if ok else '(missing) ' + rel(p),
                'verif\u9a8c\u6536\u8868 / ' + spec_sec(7), 1, '\u811a\u672c\u65ad\u8a00', 'AE1-D2')
        R.add_m('D2\u51e0\u4f55', '\u573a\u666f\uff1a' + s, '\u5b58\u5728\u6027', 'exists',
                'Build Settings \u5e8f\u5217\u91cc\u7684\u573a\u666f\u5fc5\u987b\u5b58\u5728',
                'exists=' + str(ok),
                '\u4e00\u81f4' if ok else '\u4e0d\u4e00\u81f4(\u573a\u666f\u6587\u4ef6\u7f3a\u5931)',
                'coverage-enumerate.py')

# ---------------------------------------------------------------- D3 材质与贴图表现
# ⛔ 表来自 spec.material_objects[]：{name, slot, source, frame_re?, frame_path?}
#   给了 frame_re + frame_path（相对 <resources>，%03d 占位）⇒ 逐帧核对盘上那张图是否非空/非纯白。
#   表空 ⇒ blocked（⛔ 不退化成"没有可见物件"）。


def d3(landed):
    if not UI_DIR:
        R.blk('D3 ui blank/white', 'spec.ui.rel is empty -> UI frames cannot be scanned for blank/white art')
    ui_files = walk_files(UI_DIR, UI_EXT) if UI_DIR else []
    ui_white = []
    for f in ui_files:
        st = png_stats(f)
        if st and st[1] is not None and st[2] is not None:
            w, h, na, white = st
            if na == 0:
                ui_white.append((os.path.basename(f), rel(f), '\u5168\u900f\u660e(\u7a7a\u56fe)'))
            elif white:
                ui_white.append((os.path.basename(f), rel(f), '\u975e\u900f\u660e\u50cf\u7d20\u5168\u4e3a\u8fd1\u767d(\u53ef\u80fd\u5360\u4f4d/\u7eaf\u767d)'))

    # 每个已落地精灵目录：抽首帧判"纯白/空图"（数值判据 → 典型漏检：skin 没绑 / 占位白）
    for dirname, offset in sorted(landed.items()):
        ext = LANDED_EXT.get(offset, UI_EXT)
        frames = sorted(walk_files(offset, ext))
        if not frames:
            R.blk('D3 dir ' + dirname, 'no %s frame found in %s' % (ext, offset))
            continue
        f = frames[0]
        st = png_stats(f)
        R.add_e('D3\u6750\u8d28', '\u53ef\u89c1\u7269\u4ef6\uff1a(\u76ee\u5f55) ' + dirname, rel(offset),
                spec_sec(6) + ' / ResPaths.cs', len(frames),
                '\u811a\u672c\u65ad\u8a00', 'AE1-D3')
        if st is None or st[2] is None:
            R.add_m('D3\u6750\u8d28', '\u53ef\u89c1\u7269\u4ef6\uff1a(\u76ee\u5f55) ' + dirname,
                    '\u9996\u5e27\u662f\u5426\u7a7a\u56fe/\u7eaf\u767d', '\u975e\u7a7a\u975e\u767d / \u7a7a / \u7eaf\u767d',
                    '\u7cbe\u7075\u9996\u5e27\u5fc5\u987b\u975e\u7a7a\u4e14\u975e\u7eaf\u767d',
                    'decode-failed(or unsupported ctype)', '\u672a\u5224(\u56fe\u50cf\u65e0\u6cd5\u89e3\u7801)',
                    'coverage-enumerate.py (png_stats)')
        else:
            w, h, na, white = st
            bad = (na == 0) or bool(white)
            R.add_m('D3\u6750\u8d28', '\u53ef\u89c1\u7269\u4ef6\uff1a(\u76ee\u5f55) ' + dirname,
                    '\u9996\u5e27\u662f\u5426\u7a7a\u56fe/\u7eaf\u767d', '\u975e\u7a7a\u975e\u767d / \u7a7a / \u7eaf\u767d',
                    '\u7cbe\u7075\u9996\u5e27\u5fc5\u987b\u975e\u7a7a\u4e14\u975e\u7eaf\u767d',
                    '%s: %dx%d nonalpha=%s near_white=%s' % (os.path.basename(f), w, h, na, white),
                    '\u4e0d\u4e00\u81f4(\u7a7a\u56fe/\u7eaf\u767d)' if bad else '\u4e00\u81f4',
                    'coverage-enumerate.py (png_stats)')

    mats = spec_table('material_objects') or []
    if not mats:
        R.blk('D3 material objects', 'spec.material_objects is empty -> no visible object is enumerated')
    for it in mats:
        if not isinstance(it, dict) or not it.get('name'):
            _bad_item('material_objects', '{name, slot, source, frame_re?, frame_path?}')
            continue
        name = it['name']
        slot = str(it.get('slot', ''))
        src = str(it.get('source', ''))
        R.add_e('D3\u6750\u8d28', '\u53ef\u89c1\u7269\u4ef6\uff1a' + name,
                src, spec_sec(6) + ' / ResPaths.cs', 3, '\u811a\u672c\u65ad\u8a00+\u5e76\u6392\u56fe', 'AE1-D3')
        # 能定位到具体帧的表项：逐帧核对盘上那张图（数值判据，非截图）
        if it.get('frame_re') and it.get('frame_path'):
            fr = re.search(str(it['frame_re']), slot)
            if fr is None:
                R.add_m('D3\u6750\u8d28', '\u53ef\u89c1\u7269\u4ef6\uff1a' + name, '\u8d34\u56fe\u662f\u5426\u7ed1\u4e0a\u4e14\u975e\u7a7a',
                        'exists / blank / white', '\u8be5\u5e27\u5fc5\u987b\u5728\u76d8\u4e0a\u4e14\u975e\u7a7a',
                        'frame_re %r did not match slot %r' % (str(it['frame_re']), slot),
                        '\u672a\u5224(\u539f\u578b\u65e0\u6cd5\u5b9a\u4f4d\u8be5\u5e27)',
                        'coverage-enumerate.py (spec)')
                continue
        else:
            R.add_m('D3\u6750\u8d28', '\u53ef\u89c1\u7269\u4ef6\uff1a' + name, '\u8d34\u56fe\u662f\u5426\u7ed1\u4e0a\u4e14\u975e\u7eaf\u767d',
                    '\u7ed1\u5b9a / \u672a\u7ed1\u5b9a', '\u7279\u5b9a\u7d20\u6750\u5e27\u5fc5\u987b\u88ab\u8d4b\u7ed9 SpriteRenderer',
                    'pending: \u9700\u5b9e\u4f8b\u5316\u5e27\u7d20\u636e', '\u672a\u5224(\u5f85\u5e76\u6392\u56fe)',
                    'coverage-enumerate.py (struct)')
            continue
        f = os.path.join(RES, str(it['frame_path']).replace('/', os.sep) % int(fr.group(1)))
        st = png_stats(f) if os.path.isfile(f) else None
        if st is None:
            R.add_m('D3\u6750\u8d28', '\u53ef\u89c1\u7269\u4ef6\uff1a' + name, '\u8d34\u56fe\u662f\u5426\u7ed1\u4e0a\u4e14\u975e\u7a7a',
                    'exists / blank / white', '\u8be5\u5e27\u5fc5\u987b\u5728\u76d8\u4e0a\u4e14\u975e\u7a7a',
                    'file MISSING: ' + rel(f), '\u4e0d\u4e00\u81f4(\u8be5\u5e27\u7f3a\u5931)',
                    'coverage-enumerate.py (png_stats)')
        else:
            w, h, na, white = st
            bad = (na == 0) or bool(white)
            R.add_m('D3\u6750\u8d28', '\u53ef\u89c1\u7269\u4ef6\uff1a' + name, '\u8d34\u56fe\u662f\u5426\u7ed1\u4e0a\u4e14\u975e\u7a7a',
                    'exists / blank / white', '\u8be5\u5e27\u5fc5\u987b\u975e\u7a7a\u4e14\u975e\u7eaf\u767d',
                    '%dx%d nonalpha=%s near_white=%s' % (w, h, na, white),
                    '\u4e0d\u4e00\u81f4(\u7eaf\u767d/\u7a7a\u56fe)' if bad else '\u4e00\u81f4',
                    'coverage-enumerate.py (png_stats)')
    # 纯白/空图清单（数值判据，非截图）
    landed_by = spec_get('ui.landed_by', 'the asset-copy step')
    for base, p, why in ui_white:
        R.add_e('D3\u6750\u8d28', '\u53ef\u89c1\u7269\u4ef6\uff1a(ui) ' + base, p,
                landed_by, 2, '\u811a\u672c\u65ad\u8a00', 'AE1-D3')
        R.add_m('D3\u6750\u8d28', '\u53ef\u89c1\u7269\u4ef6\uff1a(ui) ' + base, '\u8d34\u56fe\u662f\u5426\u7eaf\u767d/\u7a7a',
                '\u975e\u7a7a\u975e\u767d / \u7a7a / \u7eaf\u767d', 'UI \u56fe\u5143\u5fc5\u987b\u975e\u7a7a\u4e14\u975e\u7eaf\u767d',
                why, '\u4e0d\u4e00\u81f4(\u7a7a\u56fe/\u7eaf\u767d)', 'coverage-enumerate.py (png_stats)')

# ---------------------------------------------------------------- S1 数值与配表
# ⛔ 全部来自 spec：official_data.{dir,files,card_cost_fields,card_rarity_field,unit_columns,
#    unit_bool,unit_str,unit_custom,rarity_index,rarity_cn} + numeric_tables[] + numeric_columns{}
#    官方数据目录/文件表缺失 ⇒ S1 块 blocked（⛔ 不静默当"配表没有对应官方行"）。

RARITY_IDX = spec_get('official_data.rarity_index', {}) or {}
RARITY_CN = spec_get('official_data.rarity_cn', {}) or {}

def load_api():
    if not API_JSON or not os.path.isdir(API_JSON):
        R.blk('S1 official data', 'spec.paths.source_api_dir empty/missing: %s' % (API_JSON or '<empty>'))
        return {}
    names = spec_table('official_data.files') or []
    if not names:
        R.blk('S1 official data', 'spec.official_data.files is empty -> nothing to compare against')
        return {}
    d = {}
    for n in names:
        p = os.path.join(API_JSON, str(n) + '.json')
        d[str(n)] = json.load(io.open(p, encoding='utf-8')) if os.path.isfile(p) else None
    missing = sorted(n for n, v in d.items() if v is None)
    if missing:
        R.blk('S1 official data files', 'listed in the spec but missing on disk: ' + ','.join(missing))
    return d

def api_level_idx(rarity_name):
    return RARITY_IDX.get(rarity_name, None)

def pick_per_level(row, field, idx):
    v = row.get(field)
    if isinstance(v, list) and 0 <= idx < len(v):
        return v[idx]
    if not isinstance(v, list):
        return v
    return None

def s1_tables():
    """配表覆盖 + 逐值比官方 JSON（差值必须 0 或已登记）。"""
    api = load_api()
    if not api:
        R.blk('S1 value comparison', 'official data could not be loaded -> the per-value comparison is NOT judged')
        return api, {}, {}, {}, {}
    cards = api.get('cards') or []
    by_name_card = {}
    for c in cards:
        for k in ('key', 'name', 'id'):
            if k in c and c[k]:
                by_name_card[str(c[k]).lower()] = c
    chars = {r['name']: r for r in (api.get('cards_stats_characters') or [])}
    builds = {r['name']: r for r in (api.get('cards_stats_building') or [])}
    spells = api.get('cards_stats_spell') or []
    projs = {r['name']: r for r in (api.get('cards_stats_projectile') or [])}
    rar = {r['name']: r for r in (api.get('rarities') or [])}

    col_key = spec_get('numeric_columns.key', 'key')
    col_cost = spec_get('numeric_columns.cost', 'elixir')
    col_rarity = spec_get('numeric_columns.rarity', 'rarity')
    _cost_fields = spec_get('official_data.card_cost_fields', []) or []
    _rarity_field = spec_get('official_data.card_rarity_field', 'rarity')
    tsv_dir = spec_get('table_pipeline.tsv_dir', 'server/game/table/tsv')

    # ---- 产物 vs 源表 行数（打表产物 <tsv_dir>/*.tsv vs <数值文档>/<src>）
    tabs = spec_table('numeric_tables') or []
    if not tabs:
        R.blk('S1 table rows', 'spec.numeric_tables is empty -> no table row-count is compared')
    for t in tabs:
        if not isinstance(t, dict) or not t.get('tsv') or not t.get('src'):
            _bad_item('numeric_tables', '{id, tsv, src}')
            continue
        tsvname, srcname = t['tsv'], t['src']
        tf = os.path.join(ROOT, *str(tsv_dir).replace('\\', '/').split('/'), tsvname)
        sf = os.path.join(NUMDIR, srcname)
        if not (os.path.isfile(tf) and os.path.isfile(sf)):
            R.blk('S1 table ' + tsvname, 'table tsv/src missing: %s / %s' % (tf, sf))
            continue
        _, tr = read_tsv(tf)
        _, sr = read_src_table(sf)
        R.add_e('S1\u6570\u503c', '\u6253\u8868\u4ea7\u7269 ' + tsvname,
                rel(tf), os.path.basename(NUMDIR) + '/' + srcname, len(tr),
                '\u811a\u672c\u65ad\u8a00', 'AE1-S1')
        R.add_m('S1\u6570\u503c', '\u6253\u8868\u4ea7\u7269 ' + tsvname,
                '\u4ea7\u7269\u884c\u6570 vs \u6e90\u8868\u884c\u6570', '%d' % len(sr),
                '\u6e90\u8868\u6570\u636e\u884c\u5fc5\u987b\u7b49\u4e8e\u4ea7\u7269\u6570\u636e\u884c',
                'src=%d tsv=%d' % (len(sr), len(tr)),
                '\u4e00\u81f4' if len(sr) == len(tr) else '\u4e0d\u4e00\u81f4(\u6253\u8868\u4ea7\u7269\u884c\u6570\u4e0d\u5339\u914d)',
                'coverage-enumerate.py (table tsv)')

    # ---- card 源表逐值比官方
    ct = numeric_table('card')
    if ct is not None:
        h, rows = read_src_table(os.path.join(NUMDIR, ct['src']))
        for r in rows:
            d = dict(zip(h, r))
            key = d[col_key]
            off = by_name_card.get(key.lower())
            R.add_e('S1\u6570\u503c', os.path.splitext(ct['src'])[0] + ':' + key,
                    os.path.basename(NUMDIR) + '/' + ct['src'], spec_sec(6), 4,
                    '\u53c2\u8003\u7269\u6bd4\u5bf9', 'AE1-S1')
            if off is None:
                R.add_m('S1\u6570\u503c', os.path.splitext(ct['src'])[0] + ':' + key,
                        col_key + '\u2194\u5b98\u65b9 cards', 'found / missing',
                        '\u6bcf\u884c ' + col_key + ' \u5fc5\u987b\u80fd\u5728\u5b98\u65b9\u6570\u636e\u91cc\u627e\u5230',
                        'official: MISS', '\u4e0d\u4e00\u81f4(' + col_key + ' \u5728\u5b98\u65b9\u6570\u636e\u91cc\u4e0d\u5b58\u5728)',
                        'coverage-enumerate.py')
                continue
            # 资源消耗（官方字段名可能不止一个，按 spec 的顺序取第一个存在的）
            oc = None
            for f in _cost_fields:
                if off.get(f) is not None:
                    oc = off.get(f)
                    break
            try:
                ou = int(d[col_cost])
            except Exception:
                ou = None
            ok = (oc == ou)
            R.add_m('S1\u6570\u503c', os.path.splitext(ct['src'])[0] + ':' + key,
                    col_cost + ' \u2194 \u5b98\u65b9', str(oc),
                    '\u5b98\u65b9 = %s' % oc, 'ours=%s official=%s' % (ou, oc),
                    '\u4e00\u81f4' if ok else '\u4e0d\u4e00\u81f4(' + col_cost + ' \u2260 \u5b98\u65b9)',
                    'coverage-enumerate.py (official cards)')
            # 稀有度
            orr = off.get(_rarity_field)
            ourname = RARITY_CN.get(d[col_rarity], '?')
            ok2 = (str(orr).lower() == ourname.lower())
            R.add_m('S1\u6570\u503c', os.path.splitext(ct['src'])[0] + ':' + key,
                    col_rarity + ' \u2194 \u5b98\u65b9 ' + _rarity_field, ourname,
                    '\u5b98\u65b9:%s = %s' % (_rarity_field, orr), 'ours=%s official=%s' % (ourname, orr),
                    '\u4e00\u81f4' if ok2 else '\u4e0d\u4e00\u81f4(' + col_rarity + ' \u4e0d\u7b26)',
                    'coverage-enumerate.py (official cards)')

    # ---- unit 源表：逐行登记（逐值比对在 s1_unit_values）
    ut = numeric_table('unit')
    if ut is not None:
        h, rows = read_src_table(os.path.join(NUMDIR, ut['src']))
        ncol = spec_get('official_data.unit_columns', []) or []
        for r in rows:
            d = dict(zip(h, r))
            R.add_e('S1\u6570\u503c', os.path.splitext(ut['src'])[0] + ':' + d[col_key],
                    os.path.basename(NUMDIR) + '/' + ut['src'],
                    spec_sec(4) + '/' + spec_sec(5) + '/' + spec_sec(6),
                    max(2, len(ncol) + len(spec_get('official_data.unit_custom', []) or [])),
                    '\u53c2\u8003\u7269\u6bd4\u5bf9', 'AE1-S1')
    return api, chars, builds, projs, rar

def _norm(s):
    return re.sub(r'[^a-z0-9]', '', str(s).lower())

def build_official_index(api):
    """官方实体索引：norm(name) → 行；card key → 卡行；卡名 → 召唤实体名。"""
    by_norm = {}
    for src in ('cards_stats_characters', 'cards_stats_building', 'cards_stats_projectile'):
        for r in (api.get(src) or []):
            nm = r.get('name')
            if nm:
                by_norm.setdefault(_norm(nm), r)
    card_by_key = {}
    card_sc = {}                 # 卡 key(norm) -> 官方 cards.json:sc_key（= 该卡的战斗实体名）
    for c in (api.get('cards') or []):
        if c.get('key'):
            card_by_key[_norm(c['key'])] = c
            if c.get('sc_key'):
                card_sc[_norm(c['key'])] = c['sc_key']
    troop_summon = {}
    for r in (api.get('cards_stats_troop') or []):
        nm, sc = r.get('name'), r.get('summon_character')
        if nm and sc:
            troop_summon.setdefault(_norm(nm), sc)
    return by_norm, card_by_key, troop_summon, card_sc

def _lookup(name, by_norm):
    """官方实体名查找：先按原样、再按复数（官方把 FireSpirit 记作 FireSpirits 一类）。"""
    n = _norm(name)
    return by_norm.get(n) or by_norm.get(n + 's')

def resolve_official(key, kind, summon_key, by_norm, card_by_key, troop_summon, card_sc=None):
    """按 unit_cs 的 kind 定位官方实体行（出处 = 官方 JSON 的 name 字段）。
    ① 卡 key 有官方 sc_key ⇒ 以 sc_key 为准（bandit→Assassin / executioner→AxeMan /
       cannon-cart→MovingCannon / dart-goblin→BlowdartGoblin 等官方改名卡由此定位）；
    ② 部队再退到 summon_key（群体卡的实体行）；③ 最后按原名。"""
    if card_sc:
        sc = card_sc.get(_norm(key))
        if sc:
            r = _lookup(sc, by_norm)
            if r is not None:
                return r
    if kind in ('3', '2'):               # 投射物 / 塔
        return _lookup(key, by_norm)
    if kind == '0':                      # 部队：以"本体/被召唤实体"为准
        cand = summon_key.strip() or key
        return _lookup(cand, by_norm) or _lookup(key, by_norm)
    # kind == '1' 建筑：unit_cs.key 是卡 key ⇒ 先原名，再经卡名映射到官方建筑名
    r = _lookup(key, by_norm)
    if r is not None:
        return r
    c = card_by_key.get(_norm(key))
    if c is not None and c.get('name'):
        nm = c['name']
        r = _lookup(troop_summon.get(_norm(nm), nm), by_norm) or _lookup(nm, by_norm)
        if r is not None:
            return r
    return None

# 官方列映射 / 布尔列 / 字符串列 / 本项目自定列 —— 全部来自 spec.official_data.*
# ⛔ 空表 ⇒ 该块 blocked（不许把"没有列映射"静默当成"这些列不用比"）。
UNIT_OFFICIAL = []
for _c in (spec_get('official_data.unit_columns', []) or []):
    if isinstance(_c, (list, tuple)) and len(_c) >= 2:
        UNIT_OFFICIAL.append((_c[0], _c[1]))
    else:
        MALFORMED_KEYS.append('official_data.unit_columns[] item needs [our_column, official_field]')
UNIT_BOOL = tuple(spec_get('official_data.unit_bool', []) or [])
UNIT_STR = tuple(spec_get('official_data.unit_str', []) or [])
UNIT_CUSTOM = list(spec_get('official_data.unit_custom', []) or [])
# 本项目自定列（官方数据里没有对应字段）的出处文字，由 spec 提供
UNIT_CUSTOM_EVIDENCE = spec_get('official_data.unit_custom_evidence', 'the project defines these columns')

def _official_unit_value(off, off_k, ours_k, idx, by_norm):
    """返回官方取值（None = 官方无此字段/该等级无值，跳过）。damage 本体为 0 时退到投射物。"""
    if ours_k == 'projectile_key':
        v = off.get('custom_first_projectile') or off.get('projectile')
        return v if v else None
    if ours_k == 'spawn_interval_ms':
        v = off.get('spawn_interval') or off.get('spawn_pause_time')
        return int(v) if v is not None else 0
    if ours_k == 'damage':
        v = pick_per_level(off, 'damage_per_level', idx)
        if v in (None, 0):
            pj = by_norm.get(_norm(off.get('projectile') or ''))
            if pj is not None:
                v2 = pick_per_level(pj, 'damage_per_level', api_level_idx(pj.get('rarity')))
                if v2 is None and 'damage' in pj:
                    v2 = pj.get('damage')
                if v2 is not None:
                    v = v2
        return int(v) if v is not None else None
    if ours_k == 'radius_mt':
        for f in ('collision_radius', 'radius'):
            if f in off:
                v = pick_per_level(off, f, idx)
                return int(v) if v is not None else None
        return None
    if ours_k == 'flying':
        v = off.get('flying_height')
        return bool(v) if v is not None else None
    if ours_k in UNIT_BOOL:
        v = off.get(off_k)
        return bool(v) if v is not None else None
    if off_k not in off:
        return None
    v = pick_per_level(off, off_k, idx) if isinstance(off.get(off_k), list) else off.get(off_k)
    if v is None:
        return None
    return v if ours_k in UNIT_STR else int(v)

def s1_unit_values(api, chars, builds, projs, rar):
    if not api:
        return
    ut = numeric_table('unit')
    if ut is None:
        return
    if not UNIT_OFFICIAL:
        R.blk('S1 unit columns', 'spec.official_data.unit_columns is empty -> no column is compared')
    by_norm, card_by_key, troop_summon, card_sc = build_official_index(api)
    col_key = spec_get('numeric_columns.key', 'key')
    h, rows = read_src_table(os.path.join(NUMDIR, ut['src']))
    ent_prefix = os.path.splitext(ut['src'])[0] + ':'
    for r in rows:
        d = dict(zip(h, r))
        key = d[col_key]
        off = resolve_official(key, d.get('kind', ''), d.get('summon_key', '').split(';')[0],
                               by_norm, card_by_key, troop_summon, card_sc)
        if off is None:
            R.add_m('S1\u6570\u503c', ent_prefix + key, '\u2194\u5b98\u65b9\u5b9e\u4f53\u884c',
                    'found / missing', '\u6bcf\u884c\u5e94\u80fd\u5bf9\u5e94\u5b98\u65b9\u5b9e\u4f53',
                    'official entity: MISS', '\u672a\u5224(\u65e0\u6cd5\u5b9a\u4f4d\u5b98\u65b9\u884c)',
                    'coverage-enumerate.py')
            continue
        idx = api_level_idx(off.get('rarity'))
        # ① 官方列逐值比
        for ours_k, off_k in UNIT_OFFICIAL:
            vs = _official_unit_value(off, off_k, ours_k, idx, by_norm)
            if vs is None:
                continue
            ours = d.get(ours_k, '')
            if ours_k in UNIT_BOOL:
                ouv = (str(ours).strip() == '1')
                ok = (ouv == vs)
                ovs = '1' if vs else '0'
            elif ours_k in UNIT_STR:
                ouv = str(ours).strip()
                ok = (ouv == str(vs))
                ovs = str(vs)
            else:
                try:
                    ouv = int(ours)
                except Exception:
                    ouv = None
                ok = (ouv == int(vs))
                ovs = str(vs)
            R.add_m('S1\u6570\u503c', ent_prefix + key, ours_k + ' \u2194 \u5b98\u65b9 ' + off_k,
                    ovs, '%s:%s = %s' % (off.get('name'), off_k, ovs),
                    'ours=%s official=%s' % (ours, ovs),
                    '\u4e00\u81f4' if ok else '\u4e0d\u4e00\u81f4(%s: \u6211\u4eec %s vs \u5b98\u65b9 %s)' % (off_k, ours, ovs),
                    'coverage-enumerate.py (official data)')
        # ② 本项目自定列（登记为允许的差异）
        for col in UNIT_CUSTOM:
            R.add_m('S1\u6570\u503c', ent_prefix + key, col + ' (\u672c\u9879\u76ee\u81ea\u5b9a\u5217)',
                    '-', '\u672c\u9879\u76ee\u81ea\u5b9a\uff1a' + col,
                    'ours=%s' % d.get(col, ''),
                    '\u5141\u8bb8\u7684\u5dee\u5f02(\u672c\u9879\u76ee\u81ea\u5b9a\u5217)',
                    UNIT_CUSTOM_EVIDENCE)

def s1_spell_values(api):
    if not api:
        return
    st = numeric_table('spell')
    if st is None:
        return
    h, rows = read_src_table(os.path.join(NUMDIR, st['src']))
    ent_prefix = os.path.splitext(st['src'])[0] + ':'
    col_key = spec_get('numeric_columns.key', 'key')
    col_cost = spec_get('numeric_columns.cost', 'elixir')
    _cost_fields = spec_get('official_data.card_cost_fields', []) or []
    off_by_name = {}
    for c in (api.get('cards') or []):
        off_by_name[str(c.get('key', '')).lower()] = c
    for r in rows:
        d = dict(zip(h, r))
        key = d[col_key]
        R.add_e('S1\u6570\u503c', ent_prefix + key, os.path.basename(NUMDIR) + '/' + st['src'],
                spec_sec(6), 6, '\u53c2\u8003\u7269\u6bd4\u5bf9', 'AE1-S1')
        c = off_by_name.get(key.lower())
        if c is None:
            R.add_m('S1\u6570\u503c', ent_prefix + key, col_key + '\u2194\u5b98\u65b9 cards',
                    'found/missing', col_key + ' \u5fc5\u987b\u5728\u5b98\u65b9\u6570\u636e\u91cc', 'MISS',
                    '\u4e0d\u4e00\u81f4(' + col_key + ' \u4e0d\u5b58\u5728)', 'coverage-enumerate.py')
            continue
        oc = None
        for f in _cost_fields:
            if c.get(f) is not None:
                oc = c.get(f)
                break
        try:
            ou = int(d[col_cost])
        except Exception:
            ou = None
        R.add_m('S1\u6570\u503c', ent_prefix + key, col_cost + ' \u2194 \u5b98\u65b9', str(oc),
                '\u5b98\u65b9 = %s' % oc, 'ours=%s official=%s' % (ou, oc),
                '\u4e00\u81f4' if oc == ou else '\u4e0d\u4e00\u81f4(' + col_cost + ')',
                'coverage-enumerate.py (official cards)')

# ---------------------------------------------------------------- 差异登记（第三张表）

def build_diff():
    """允许的差异登记（spec.allowed_differences）。可以是空表 —— 空 = 本项目没有任何允许的差异。
    ⛔ 这张表**必然**是项目专有的（"用户本轮原话" / 本项目自定列），所以它只能住在项目 spec 里。"""
    rows = spec_get('allowed_differences', []) or []
    if not isinstance(rows, list):
        MALFORMED_KEYS.append('allowed_differences (expected a list of 5-column rows)')
        return
    for r in rows:
        if isinstance(r, (list, tuple)) and len(r) >= 5:
            R.diff.append([str(x) for x in r[:5]])
        else:
            MALFORMED_KEYS.append('allowed_differences[] item needs 5 columns [id, what, why, origin, when]')

# ---------------------------------------------------------------- 主流程

def main():
    global DIMS
    ap = argparse.ArgumentParser()
    ap.add_argument('--project-root', default='',
                    help='项目根（默认当前目录）。模块级路径常量已在 import 期按它算好。')
    ap.add_argument('--root', default='', help='--project-root 的旧名（兼容；两者都可用）')
    ap.add_argument('--spec', default='',
                    help='定义表 JSON（默认 = 本脚本同目录 config/coverage-enumerate.spec.json）')
    ap.add_argument('--ref-md', default='', help='参考规格 md（默认在 策划案/ 下找 *参考规格*.md）')
    ap.add_argument('--dims', default='',
                    help='逗号分隔的维度表覆盖（优先于 spec.dims）')
    ap.add_argument('--ui-families-config', default='',
                    help='键对账脚本的路径族配置 JSON（不给则该段报 blocked）')
    ap.add_argument('--no-ps', action='store_true')
    args = ap.parse_args()
    if args.dims:
        DIMS = [d.strip() for d in args.dims.split(',') if d.strip()]

    # ---- spec 闸门：缺失 / 坏 JSON / 结构性键缺 ⇒ FATAL（⛔ 绝不"尽力而为"地猜默认值）----
    if SPEC_ERROR:
        sys.stderr.write('FATAL: %s\n' % SPEC_ERROR)
        sys.stderr.write('FATAL: pass --spec <spec.json>; the skeleton lives at %s\n' % DEFAULT_SPEC)
        return 2
    miss = spec_missing_required()
    if miss:
        sys.stderr.write('FATAL: spec is missing required key(s): %s\n' % ', '.join(miss))
        sys.stderr.write('FATAL: spec=%s -- copy the skeleton at %s and fill it in\n'
                         % (SPEC_PATH, DEFAULT_SPEC))
        return 2
    if _SPEC_ARG_IS_MD:
        print('NOTE --spec got a .md file -> it is used as the REFERENCE SPEC instead; the definition'
              ' tables come from %s' % SPEC_PATH)
    print('spec = %s' % SPEC_PATH)

    if not os.path.isdir(PLAN):
        sys.stderr.write('FATAL: plan dir missing: %s\n' % PLAN)
        return 2

    landed = d1_resources()
    d1_ui_per_frame()
    d1_sources()
    d1_respaths_keys()
    d1_source_vs_landed(landed)
    d1_unit_sprite_dirs()
    if not args.no_ps:
        run_check_ui_keys()
    else:
        # 有意降级：写进 note，但**不计入 blocked**（否则有意降级会把退出码染红）
        R.degrade('--no-ps: the resource-key cross-check block was skipped on purpose')

    d2_battlefield()
    d2_panels()

    d3(landed)

    api, chars, builds, projs, rar = s1_tables()
    s1_unit_values(api, chars, builds, projs, rar)
    s1_spell_values(api)
    build_diff()

    # ---- 写出（稳定排序）
    R.ent.sort(key=lambda r: (r[0], r[1], r[2]))
    R.mat.sort(key=lambda r: (r[0], r[1], r[2], r[3]))
    R.orphans.sort(key=lambda r: (r[0], r[1]))

    if not os.path.isdir(TMP):
        os.makedirs(TMP)

    with io.open(ENTITY_TSV, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\t'.join(['\u7ef4\u5ea6', '\u5b9e\u4f53', '\u8f7d\u4f53/\u8def\u5f84', '\u51fa\u5904',
                           '\u72b6\u6001\u6570', '\u5224\u636e\u7c7b\u578b', '\u5f52\u5c5e\u7247']) + '\n')
        for r in R.ent:
            f.write('\t'.join(x.replace('\t', ' ') for x in r) + '\n')

    with io.open(MATRIX_TSV, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\t'.join(['\u7ef4\u5ea6', '\u5b9e\u4f53', '\u72b6\u6001/\u4e8b\u4ef6', '\u8fb9\u754c\u503c',
                           '\u671f\u671b\u8868\u73b0(\u51fa\u5904)', '\u5b9e\u6d4b', '\u7ed3\u8bba', '\u8bc1\u636e']) + '\n')
        for r in R.mat:
            f.write('\t'.join(x.replace('\t', ' ') for x in r) + '\n')

    with io.open(DIFF_TSV, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\t'.join(['\u7f16\u53f7', '\u662f\u4ec0\u4e48', '\u4e3a\u4ec0\u4e48', '\u51fa\u5904',
                           '\u4f55\u65f6\u6d88\u9664']) + '\n')
        for r in R.diff:
            f.write('\t'.join(r) + '\n')

    with io.open(ORPHANS, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\t'.join(['\u5b9e\u4f53', '\u8def\u5f84', '\u6587\u4ef6\u6570', '\u95ee\u9898',
                           '\u5224\u636e', '\u4e25\u91cd\u5ea6']) + '\n')
        for r in R.orphans:
            f.write('\t'.join(r) + '\n')

    per_dim_e = {}
    for r in R.ent:
        per_dim_e[r[0]] = per_dim_e.get(r[0], 0) + 1
    per_dim_m = {}
    for r in R.mat:
        per_dim_m[r[0]] = per_dim_m.get(r[0], 0) + 1
    vd = {}
    for r in R.mat:
        vd[r[6]] = vd.get(r[6], 0) + 1
    nonagree = sum(1 for r in R.mat if r[6].startswith('\u4e0d\u4e00\u81f4'))
    unjudged = sum(1 for r in R.mat if r[6].startswith('\u672a\u5224') or r[6].startswith('\u963b\u585e'))
    dims_covered = sorted(per_dim_e.keys())
    dims_missing = [d for d in DIMS if d not in per_dim_e]

    with io.open(SUMMARY, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\u679a\u4e3e\u6c47\u603b\uff08coverage-enumerate.py\uff09\n')
        f.write('root=%s\n' % ROOT)
        f.write('spec=%s\n' % SPEC_PATH)
        f.write('reference_md=%s\n' % REF_MD)
        f.write('\u5b9e\u4f53\u6e05\u5355\u884c\u6570 = %d\n' % len(R.ent))
        f.write('\u72b6\u6001\u77e9\u9635\u884c\u6570 = %d\n' % len(R.mat))
        f.write('\u7ed3\u8bba\u76f4\u65b9\u56fe:\n')
        for k in sorted(vd):
            f.write('  %s = %d\n' % (k, vd[k]))
        f.write('\u4e0d\u4e00\u81f4\u884c\u6570 = %d\n' % nonagree)
        f.write('\u672a\u5224/\u963b\u585e\u884c\u6570 = %d\n' % unjudged)
        f.write('\u5df2\u8986\u76d6\u7ef4\u5ea6 = %s\n' % ','.join(dims_covered))
        f.write('\u7f3a\u5931\u7ef4\u5ea6(%d/%d) = %s\n' % (len(dims_missing), len(DIMS), ','.join(dims_missing)))
        f.write('\u76d8\u4e0a\u672a\u88ab\u5f15\u7528(\u5b64\u513f) = %d\n' % len(R.orphans))
        # ★ 没被判的块：⛔ 必须在这里点名（"少判一块"和"判过且通过"在产物里长得一样）
        f.write('\u672a\u5224(\u963b\u585e)\u5757\u6570 = %d\n' % len(R.blocked))
        for b in R.blocked:
            f.write('  BLOCKED %s\n' % b)
        for n in R.note:
            f.write('note: %s\n' % n)
    print(rd_text(SUMMARY))
    # ---- 退出码：spec 结构性缺陷 ⇒ 2；有块没判 ⇒ 3（⛔ 两者都不许被当成"覆盖完整"）----
    if MISSING_KEYS:
        sys.stderr.write('FATAL: spec key(s) missing: %s\n' % ', '.join(sorted(set(MISSING_KEYS))))
        return 2
    if MALFORMED_KEYS:
        sys.stderr.write('FATAL: spec key(s) malformed: %s\n' % '; '.join(sorted(set(MALFORMED_KEYS))))
        return 2
    if R.blocked:
        sys.stderr.write('FAIL: %d block(s) were NOT judged (listed in the summary above):\n' % len(R.blocked))
        for b in R.blocked:
            sys.stderr.write('  - %s\n' % b)
        return 3
    return 0

if __name__ == '__main__':
    sys.exit(main())

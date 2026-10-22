# 逆向取证（1:1 复刻的第一动作）

> **适用**：用户点名复刻某款游戏，且原版客户端 / 安装包 / 二进制在本机可得。
> **核心**：**先取证、再实现**。素材、坐标、摆放、表数据一律从原版载体里**导出来**，⛔ 不许凭截图猜、⛔ 不许凭印象写数值。
> 链路与坑来自 CASC 系（WoW）实测，命令可直接复用。

---

## 1. 判定：什么时候走这条链

| 情况 | 动作 |
|---|---|
| 原版客户端在盘（哪怕只有部分数据） | **走本文件**：CASC 直读 → 导出地形/模型/摆放/表 |
| 只有安装包 / 压缩包 | 先解包到 `<项目根>/原版资源/`，再走 CASC |
| 只有 exe、数据全无 | 才退回"参考图量化"（`reference/asset-sources.md`） |
| 载体加密且缺 key（DB2 TACT / 加密封包） | 记为**阻塞项**，写清"缺什么 + 谁能给"，其余部分照常做 |

⛔ **别一上来就上网找同人素材**：原版载体里的东西精度更高、来源更硬（`§0` 铁律 4 的"出处"就是这个）。

---

## 2. 工具链（三件套）

| 层 | 工具 | 用途 |
|---|---|---|
| 读取容器 | `wow.export` 源码（纯 JS，可 headless） | 打开 CASC、解析 ADT/M2/WMO/DB2 的二进制结构 |
| 文件名索引 | 社区 listfile（`%TEMP%\wow-listfile.csv`，~146 MB） | `FileDataID ↔ 路径` 双向查；**没有它就只能读 ID，不知道是什么文件** |
| 模型转换 | 同一套 `wow.export` 的 exporter（M2Exporter / WMOExporter） | M2/WMO → GLB |

安装（本机一次性）：
```powershell
git clone --depth 1 https://github.com/Kruithne/wow.export <项目根>\tools\wow.export
# listfile：从 wowdev/wow-listfile releases 下 community-listfile.csv，放 %TEMP%
```

---

## 3. headless bootstrap（照抄这段，别自己发明）

```js
global.BUILD_RELEASE = true;
global.nw = { __dirname, App: { dataPath, manifest: { version: '0.2.19-headless' } } };
const view = anyCallable({ config, update(){}, casc: null, listfile: {}, restartApplication(){}, exportCancelled: false });
const core = anyCallable({ events: new EventEmitter(), view, create_busy_lock: () => ({ release(){} }) });
// Module._load 打桩：core / mmap / webp-wasm / casc-source 里的 ./listfile
```
```js
const casc = new CASCLocal(WOW_PATH); await casc.init();
const bi = casc.builds.findIndex(b => b.Product === '<产品名>');
await casc.load(bi); casc.locale = 0xFFFFFFFF;
await listfile.prepareListfile(); listfile.applyPreload(casc.rootEntries);
view.casc = casc;   // exporter 内部从 core.view.casc 取文件
```

🚨 **四个必踩的坑（都验证过）**：
1. `view` 必须是 `anyCallable` 代理，**不能是裸对象**：否则 `core.view.$watch is not a function` 直接崩。
2. `view.exportCancelled` 必须显式写 `false`：裸代理会把它变成本身就 truthy 的函数 ⇒ **exporter 以为用户取消了，静默不写文件**（现象：函数返回成功、目录里没有产物）。
3. `listfile.getByFilename(path)` 对大小写敏感、且要求路径与 listfile 完全一致；批量找用 `listfile.getFilteredEntries(/regex/i)`。
4. `casc.getFile(id)` 拿到的是**懒解码**缓冲：必须 `seek(0); processAllBlocks();` 后再读 `.raw`，否则读到的是一片零。

---

## 4. 地形（ADT）—— 结构要点

| 块 | 内容 | 关键点 |
|---|---|---|
| root ADT | MVER + MHDR + 256×MCNK | MCNK 头 **128 字节**，之后才是子块（MCVT 高度 / MCNR 法线） |
| `_tex0.adt` | 材质层 | **MCNK 没有 128 字节头**，payload 直接从 `MCLY` 开始；纹理名走 `MDID` 的 FileDataID |
| `_obj0.adt` | 物件摆放 | `MDDF`（M2，36 字节/条）+ `MODF`（WMO，64 字节/条），`nameId` **直接就是 FileDataID** |

**MCVT 145 个高度值是 17 宽的行缓冲**（不是紧凑的 9/8 排列）：
```
第 r 行起点 = r 偶 ? (r/2)*17 : (r/2)*17 + 9
偶数行 9 个点、奇数行 8 个点（沿列方向再偏半格）
三角化：每个 8×8 格子 = 四角 + 中心点 → 4 个三角形（共 256 tri/chunk）
```
🚨 按"紧凑 9/8 顺序"读会得到**撕裂成尖刺的地形**；接缝校验必须做（相邻 tile 的共享顶点高度必须相等，冲突数必须为 0）。

**物件摆放坐标是"统一坐标"**，不是世界坐标：
```
worldX = 32 * TILE - pos.z      TILE = 1600/3
worldZ = 32 * TILE - pos.x
```
（换算后用地形 tile 边界校验：落点与 tile 范围吻合才说明换算对了。）

---

## 5. 模型（M2 / WMO）

- **M2 → GLB**：`new M2Exporter(data, [], fdid).exportAsGLTF(out, helper, 'glb')`；`modelsExportTextures: false` 先拿几何（关掉贴图可绕开 exporter 的返回值 bug）。
- **WMO → GLB**：`new WMOExporter(data, fdid).exportAsGLTF(out, helper, 'glb')`；同样先关贴图。
- **生物贴图**：多数生物 M2 的纹理槽位 FileDataID 是 **0**（原版由 `CreatureDisplayInfo` 指定）⇒ 用命名约定兜底：同目录 `<模型名>skin*.blp`，优先 brown / grey。
- **角色贴图**：走 `CharSections` 外观分段；单张 `character/<race>/<sex>/<race><sex>skin00_00.blp` 只能当**肤色图集**用，装备/发型必须另外拼。
- **性能**：一次加载几十组巨型 WMO 会把主线程卡到 30s 以上 ⇒ 只加载出现频率最高的 N 组，或做距离分块加载；批绘制用 `Graphics.DrawMeshInstanced`（记得 `material.enableInstancing = true`，否则一个都不显示）。

**运行时读 GLB**：不要为几个已知格式引三方运行时，写 150 行的最小解析（header → JSON chunk → BIN chunk → accessor → Mesh）就够；⚠️ 高度归一化要用 **`mesh.bounds.size.y`**，不要用自己累加 min/max（累加容易漏写，缩放会差 10000 倍）。

---

## 6. 表数据（DB2）

- 本机 DB2 可能**根本没下载全**：先查 `listfile` 里有、但 `casc.getFile` 报"本地 CASC 没有这个文件"⇒ 数据缺失，不是代码问题。
- 无 `.dbd` 架构文件时只能出 `{ id, name, strings }` 级别；带 `encodingKey` 的表还需 TACT key。
- **判据**：导出的表能查到一条已知记录（例如区域表里出现目标区域名）才算通；⛔ 空数组 + "已完成"= 假结论。

---

## 7. 二进制（客户端 exe）

- 有反汇编器（Ghidra / IDA）才谈得上"逆向逻辑"；没装 ⇒ 只能做**字符串扫描**（协议名、函数名、错误文案），别声称"逆了协议"。
- Windows 上部分逆行工具不可用（`SKILL.md` §8 第 7 条）⇒ 先确认通道可用再排期。
- 复刻**不需要**理解原版服务器：素材与规则从客户端载体 + 公开资料取证，服务器用自己的引擎写（`patterns/handler.md`）。

---

## 8. 产出与落盘约定

| 产物 | 位置 | 备注 |
|---|---|---|
| 侦察证据（清单/统计） | `<项目根>/证据/*.json` | 可复跑生成，⛔ 不进 Assets |
| 导出资源（地形/模型/贴图） | `<项目根>/原版资源/` → 复制被引用的进 `Assets/` | 见 `§3` 第 6 条 |
| 摆放清单 | `原版资源/<地图>/placements.json` | 客户端按清单实例化，⛔ 不手工摆 |

**判据（三条，缺一即未取证）**：① 有可复跑的导出脚本（不是一次性手抄）；② 有统计输出（tiles / chunks / 模型数 / 摆放数）；③ 有一致性校验（接缝 0 冲突 / 摆放坐标落在 tile 范围内 / 导出模型能被运行时加载）。

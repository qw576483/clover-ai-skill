# 自证与取证配方（AI 必须自己跑完这些，再写交付说明）

> 原则：**不许说"应该好了"**。每一条都要有可粘贴的证据（日志 / 数字 / 截图 / 测试结果）。
> 工具用法出处：`reference/unity-cli.md` §8.1。前提：Unity 6 + 工程已在编辑器里打开。

---

## 0. 四连（每次交付前都跑）

```bash
unity status --format json                      # ① 编辑器 ready（不是 Safe Mode）
unity command recompile_status --format json    # ② failed=false
unity command clear_console; unity command editor_play; sleep 45
unity command console --tail 400                # ③ 关键日志都在 & 零异常
unity command eval_file --file <工程>/client/verify-runtime.cs   # ④ 运行时自证
unity command capture_game_view --source screen --save_path Screenshots/play.png
unity command editor_stop                       # ⑤ 收工
```

## 1. 运行时自证脚本（`verify-*.cs` 放 `Assets/` **外**，Unity 不会编译它）

**模板 A：对象状态**（组件是否挂上 / 模型是否加载 / 动画是否在跑）

```csharp
var m = UnityEngine.Object.FindFirstObjectByType<CloverMmo1.Module.Player.PlayerMotor>();
var c = UnityEngine.Object.FindFirstObjectByType<CloverMmo1.Module.CameraRig.ThirdPersonCamera>();
var hud = UnityEngine.Object.FindFirstObjectByType<CloverMmo1.UI.HudPanel>();
var model = (m != null) ? m.transform.Find("Model") : null;
var an = (model != null) ? model.GetComponent<Animator>() : null;
string clip = "none"; float t = -1f;
if (an != null) { var ci = an.GetCurrentAnimatorClipInfo(0); if (ci.Length > 0) clip = ci[0].clip.name; t = an.GetCurrentAnimatorStateInfo(0).normalizedTime; }
float d = (m != null && c != null) ? UnityEngine.Vector3.Distance(c.transform.position, m.transform.position) : -1f;
UnityEngine.Debug.Log("[Verify] motor=" + (m != null) + " camTarget=" + (c != null && c.Target != null)
    + " camDist=" + d.ToString("F2") + " hud=" + (hud != null) + " model=" + (model != null)
    + " clip=" + clip + " clipTime=" + t.ToString("F2"));
return "ok";
```

**模板 B：本地碰撞**（与服务端同规则？防穿墙？）

```csharp
// 地图：数据与空间事实在**引擎**（Game.Map，读服务端同一份字节）；
// 解算（半径采样 / 分轴滑墙 / 扫掠细分）在**业务模块**（这里是 MapModule，薄门面无状态）。
var map = new CloverMmo1.Module.Map.MapModule();
bool ok = false; map.Load(b => ok = b);      // 已加载/资源缓存命中时会同步回调

float x = 6.5f, z = 10.5f; int blocked = 0;
for (int i = 0; i < 100; i++) {
    var r = map.Resolve(new UnityEngine.Vector3(x,0,z), new UnityEngine.Vector3(x+0.1f,0,z), 0.35f);
    if (r.x <= x + 0.0001f) blocked++;
    x = r.x;
}
var big = map.Resolve(new UnityEngine.Vector3(6.5f,0,10.5f), new UnityEngine.Vector3(14f,0,10.5f), 0.35f);
UnityEngine.Debug.Log("[VerifyMove] loaded=" + ok + " 小步终点 x=" + x.ToString("F2") + " 被挡=" + blocked + "；一次 7.5m 位移结果=" + big.x.ToString("F2"));
return "ok";
```

**模板 C：服务端校正链路**（故意发一条非法移动，看是否收到校正并回放）

```csharp
CloverEngine.Game.Net.Send(CloverMmo1.Def.MsgDef.Move,
    new CloverMmo1.Def.MoveRequest { x = 10.5f, y = 0f, z = 10.5f, seq = 8888 });
UnityEngine.Debug.Log("[VerifyNet] 已发送非法移动（走进建筑）seq=8888");
return "ok";
// 等 2~3 秒后再跑模板 A：应看到 CorrectionCount>0，客户端日志有「应用服务端校正 ack=8888 …」
```

**模板 D：相机遮挡**（把角色挪到障碍旁、相机朝墙侧，读距离）

```csharp
var m = UnityEngine.Object.FindFirstObjectByType<CloverMmo1.Module.Player.PlayerMotor>();
var c = UnityEngine.Object.FindFirstObjectByType<CloverMmo1.Module.CameraRig.ThirdPersonCamera>();
m.SendEnabled = false;                                   // 测试期间别真发移动
m.Teleport(new UnityEngine.Vector3(7.5f, 0f, 10.5f));    // 障碍旁边
c.Yaw = 270f;                                            // 让相机朝向"墙那一侧"
UnityEngine.Debug.Log("[VerifyCam] 已就位，等一帧读距离");
return "ok";
// 2 秒后再跑一次只读距离：被挡应远小于 5.5（1.47）
```

## 2. 服务端探针（把不可见的逻辑变成可断言的事实）

- 加一条**探针消息**：给点返回「可走性 + 命中的碰撞体 id + 地图是否加载」；
- 用途：验地图管线、验建筑真的挡路、验客户端与服务端判定一致；
- 断言两个方向：**道路=true 且不在碰撞体**、**建筑=false 且在碰撞体**（只断言一边会被"全阻挡 / 全可走"蒙过）。

## 3. 截图取证（含 HUD）

```bash
# 必须在 Play 模式；save_path 必须在工程目录内（相对"作者根 Assets/"）
unity command capture_game_view --source screen --width 1600 --height 900 --save_path Screenshots/play.png
```

**客观校验（不要"看着像"）**：PNG 体积 + 颜色多样性（空白画面压不出体积、颜色数极少）。

```powershell
Add-Type -AssemblyName System.Drawing; $bmp=[System.Drawing.Bitmap]::FromFile($png)
$colors=@{}; for($y=0;$y -lt $bmp.Height;$y+=8){for($x=0;$x -lt $bmp.Width;$x+=8){$c=$bmp.GetPixel($x,$y);$colors["$($c.R),$($c.G),$($c.B)"]=1}}
:"不同颜色数=$($colors.Count)"; $bmp.Dispose()
# 判据：>200 种 = 有真实贴图/HUD；个位数 = 基本空白
```

## 4. 读日志（console 输出是一行 TSV，必须先落盘再正则）

```powershell
unity command console --tail 300 --no-pager --no-banner 2>&1 | Out-File -Encoding utf8 console.txt
$t=[IO.File]::ReadAllText('console.txt',[Text.Encoding]::UTF8)
[regex]::Matches($t,'\[(Boot|Motor|Cam|HUD|Combat)\][^"\\]{0,180}') | ForEach-Object { $_.Value } | Select-Object -Last 20
```

> ⚠️ **编码陷阱（两个方向各踩过一次 ⇒ 只搜一种必错）**：**同一工程里不同管道的编码可以不同** —— ① **探针 / L3 TSV**（产品自己写的运行日志）是**原样 UTF-8**；② **`unity command console` 落盘的 JSON** 是**双重编码**（中文要 gbk→utf8 还原后才搜得到）。
> ⇒ **判据 = 两种口径都搜**：原样读 + gbk→utf8 还原后再搜。⛔ 不许只搜一种就下"事件没发生"的结论，⛔ 更不许把"没搜到"当成"没有缺陷"去改代码。**两个口径都 0 才算"确实没有"**。
> 好用的对照：先搜纯 ASCII 关键字（`[Match]` / tag 名）—— 若两种口径一致命中，就证明"文件在、只是中文 mojibake"，接下来才轮到编码问题。
> ⚠️ **"还原"的写法本身也会骗你**：正确式 = **`utf8 解码 → 按 GBK 编回字节 → 再 utf8 解码`**；而"直接按 GBK 解码"（`raw.decode('gbk')`）那种写法 **0 命中**。⇒ 还原后**必须**先用纯 ASCII 对照关键字验证还原是否成功，否则你只是换了个更糟的坏解码器、还以为"事件没发生"。

## 5. 回归测试（既有套件必须跑过）

```bash
unity command run_tests --mode PlayMode --filter <命名空间>.<用例类> --timeout 300 --async_tests --format json
unity command test_status --format json      # 看 summary.passed / failed
```
> 引擎改动后也要跑：`go build ./... && go vet ./... && go test ./internal/... -run <复现用例> -v -timeout 90s`

## 6. 交付说明必须包含的证据清单

| 证据 | 具体形式 |
|---|---|
| 编译 | `recompile_status` → `failed=false`（客户端）/ `go build` 退出码 0（服务端） |
| 运行 | 关键日志逐条贴出（进图 / 装配 / 动画 / 碰撞 / 校正…）+ **零异常** |
| 自证 | 模板 A/B/C/D 的输出（数字） |
| 画面 | 截图路径 + 颜色多样性数字 |
| 回归 | PlayMode 用例结果（passed/failed）+ 引擎用例结果 |
| 引擎改动 | 若有：改动文件 + 方法 + 回归方式 |
| 未完成 | 诚实列出（不许把没做的说成"已预留"） |

## 7. 实操坑：跑闸门 / 跑长任务 / 启服务

```powershell
Set-Location <工程根>
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify.ps1 *> .ai-tmp/test/verify-out.txt
```

1. **⛔ `*>` 重定向出来的文件是 UTF-16LE**（带 BOM）。直接 `grep FAIL` 会**一条都匹配不到**（字符之间插了 `\x00`），极易误判成"闸门全绿"。⇒ 先转码再读：`iconv -f UTF-16LE -t UTF-8 .ai-tmp/test/verify-out.txt | grep -n '^FAIL\|^HUMAN-ONLY'`。（配套：本宿主的 PowerShell 工具 stdout 常不回显 ⇒ 一律**落盘 + 回读**。）
2. **（历史）`impl-by-executor` 会把"你自己新增的实现 / 测试文件"判成孤儿**：该判据要求时间窗（默认 72 h）内改动的每个 `.cs` / `.go` 都能对上一行派活留痕。⛔ **这条闸门已删、不检了**（它数的是"有没有一行台账"，人一眼就能看出谁改的）。留下的规矩只有一条：主 agent 直改（`SKILL.md`「派活清单」第 6 条那条窄例外）时，在 `.ai-tmp/test/ledger.tsv` 补一行 `kind=direct-fix`。
3. **⛔ 长时间 `go test` / `go vet` / 闸门：别直接跑，会被宿主的 shell 超时打断（`Signal: SIGTERM`）** —— 而且**输出连同缓冲区一起丢**（`... 2>&1 | tail` 这种管道尤其会把已完成的结果也吞掉，看起来像"卡住"，其实是**假挂起**）。正确做法二选一：① 用 `run_in_background` 跑，完成后再读；② **落盘 + 回读**：`go test ./game/... -count=1 > gotest.txt 2>&1`，然后单独 `cat gotest.txt`（即使 shell 报了 SIGTERM，**文件通常已经写完**，先去看文件）。
   ⚠️ 被 `SIGTERM` 打断的 `go` 进程可能**不释放构建缓存锁** ⇒ 后续 `go` 命令全部**真的**阻塞。判据：连续两条 `go` 命令都无输出且不动 ⇒ 先查残留 `go.exe`（`tasklist //FI "IMAGENAME eq go.exe"`），⛔ 不要因为第二条也"没输出"就断定代码有问题。
4. **⛔ 往 `策划/验收表.md` 的表格单元格里写数学竖线会把列数撑破**：写 `|增益| ≥ 1` 会让该行从 5 列变 7 列，闸门 / 后续脚本按列解析就会错位。⇒ 写成 `abs(增益) ≥ 1`（或全角 `｜`）。自查：`grep "^| D150 " 策划/验收表.md | awk -F'|' '{print NF}'` 应为 **7**（5 列 + 首尾空）。
5. **⛔ 用户说"开不了服务器 / 我改的没生效" ⇒ 先查有没有上一轮遗留的服务进程在当孤儿**。后台任务被回收时，它起来的服务**不一定会跟着死**，会继续**占端口**、而且跑的是**旧二进制**。

   ```powershell
   Get-Process | Where-Object { $_.ProcessName -like 'clover*' } | Select-Object Id,ProcessName,StartTime
   Get-NetTCPConnection -State Listen | Where-Object { $_.OwningProcess -eq <PID> } | Select-Object LocalPort
   ```
   **判据**：进程 `StartTime` **早于**你最近一次 `go build` ⇒ 它跑的是旧二进制 ⇒ `Stop-Process -Id <PID> -Force` 后再重启（⛔ 别拿它当"当前代码的表现"去下结论）。
   ⚠️ 孤儿还**锁构建产物**：它持有 `*.exe~` 句柄 ⇒ 删不掉，报 `Error during a trash operation: Unknown { ... }`；光看这条报错会误判成"权限问题"，其实是**文件被占用**（`[System.IO.File]::Open(...,'None')` 一探便知），**杀掉进程后即可清**。
# 状态机模板

> ⛔⛔ **`Game.Fsm` 是全局唯一实例**（实现类 internal、无工厂，业务不能 `new`）：多套状态（游戏流程 / 角色 / UI / 动画）**共用同一张状态表和一个 Current** ⇒ 任一模块 `Force`/`Trigger` 都会跑掉别的模块的 `OnExit`/`OnEnter`；`xxx.Current == "idle"` 这类判断会被别的模块的状态污染；`OnTick` 也只跑 Current 那个。
> ⇒ **一个项目只用一处 `Game.Fsm`**（通常就是**游戏流程 / 站点**，见 `patterns/client/app-flow.md`）。角色、UI、动画这类**各自独立**的状态机请自建（或直接 `switch`），⛔ 不要四个模块都拿 `Game.Fsm`。

## 模板 1：游戏流程状态机（唯一该用 `Game.Fsm` 的地方）

```csharp
using CloverEngine;
using UnityEngine;

public class GameFlowManager : MonoBehaviour
{
    private IFsm _gameFlow;

    void Start()
    {
        _gameFlow = Game.Fsm;   // ★ Fsm 是 internal，不要 new；直接用 Game.Fsm

        _gameFlow.RegisterState("launch",
            onEnter: () =>
            {
                Game.Logger.Info("FSM", "进入启动状态");
                _gameFlow.Force("login");
            });

        _gameFlow.RegisterState("login",
            onEnter: () => Game.UI.Open<LoginPanel>(),
            onExit:  () => Game.UI.Close<LoginPanel>());

        _gameFlow.RegisterState("mainCity",
            onEnter: () => Game.Scene.Load("MainCity"),
            onExit:  () => { /* 清理主城资源 */ });

        _gameFlow.RegisterState("battle",
            onEnter: () => Game.Scene.Load("Battle"),
            onExit:  () => { /* 清理战斗资源 */ });

        _gameFlow.Force("launch");
    }

    public void EnterMainCity() => _gameFlow.Force("mainCity");
    public void EnterBattle()   => _gameFlow.Force("battle");
}
```

> `RegisterState` 的参数名是 **`onTick`**（不是 `onUpdate`）；`Game.Fsm.Current`（不是 `CurrentState`）。

## 2. 独立状态机（角色 / UI / 动画）怎么建

**⛔ 不要用 `Game.Fsm`**。三种做法，按复杂度选：

| 复杂度 | 做法 |
|---|---|
| 只有 2~4 个状态、切换条件简单 | **直接 `switch`** + 一个枚举字段（最省事，也最好读） |
| 有明确的 enter / exit / tick 语义 | **自建一个小类**（`enum State` + `OnEnter/OnTick/OnExit` 三个方法 + `SetState(next)`），不依赖引擎 |
| 需要可视化调参 | 用 Unity 的 `Animator` 状态机（动画类状态机的正解，见 `Game.Anim`） |

**自建状态机的骨架**（照这个写，不要往 `Game.Fsm` 里塞）：

```csharp
public enum CharState { Idle, Walk, Attack, Die }

public class CharacterState
{
    private CharState _cur = CharState.Idle;

    public CharState Current => _cur;

    public void SetState(CharState next)
    {
        if (next == _cur) return;
        OnExit(_cur);
        _cur = next;
        OnEnter(_cur);
    }

    public void Tick(float dt) => OnTick(_cur, dt);

    private void OnEnter(CharState s)
    {
        switch (s)
        {
            case CharState.Idle:   /* 播待机动画 */ break;
            case CharState.Walk:   /* 播行走动画 */ break;
            case CharState.Attack: /* 播攻击动画 */ break;
            case CharState.Die:    /* 播死亡动画 + 禁用碰撞 */ break;
        }
    }

    private void OnTick(CharState s, float dt)
    {
        if (s == CharState.Idle && HasInput()) SetState(CharState.Walk);
        else if (s == CharState.Walk && !HasInput()) SetState(CharState.Idle);
        // 移动逻辑写在 Walk 分支里
    }

    private void OnExit(CharState s)
    {
        switch (s)
        {
            case CharState.Walk: /* 停止移动 */ break;
        }
    }

    private bool HasInput()
    {
        // 检测输入：必须走 Game.Input（后端无关），禁止直连 UnityEngine.Input，
        // 否则 Active Input Handling 不含「旧输入」时会整帧抛异常 → 键鼠全灭。
        // 详见 reference/client-conventions.md §13。
        return Game.Input.GetAxis("Horizontal") != 0 || Game.Input.GetAxis("Vertical") != 0;
    }
}

// 调用方（角色 / UI 面板）持有一个 CharacterState 实例即可，与 Game.Fsm 完全隔离。
```

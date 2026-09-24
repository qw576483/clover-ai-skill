# 定时器模板

> `Game.Timer` 的 `After` / `Every` 返回 **`long` id（不是 `IDisposable`）**；`Stop*` 返回 `void`。**`timeScale = 0` 时普通 `After` 永不触发**（引擎用 `Time.deltaTime` 推进）⇒ 暂停菜单 / 结算屏 / GameOver 这类"冻结画面里还要走时间"的**一律用 `AfterUnscaled` / `EveryUnscaled`**。

## 模板 1：延迟 / 循环 / 取消

```csharp
// 延迟执行
Game.Timer.After(3f, () => Game.Logger.Info("Timer", "3秒后执行"));

// 循环执行（返回 long id）
private long _timerId;
_timerId = Game.Timer.Every(1f, () => Game.Logger.Info("Timer", "每秒执行"));
Game.Timer.Stop(_timerId);

// 具名：同名会先停掉旧的，之后可按名字停（比记 id 更适合业务）
private const string TimerName = "my_repeat";
Game.Timer.EveryName(TimerName, 1f, () => Game.Logger.Info("Timer", "循环执行"));
Game.Timer.StopNamed(TimerName);
```

## 模板 2：倒计时（能在回调里自我取消）

```csharp
public void StartCountdown(float duration)
{
    _remainingTime = duration;

    // 每 0.1 秒更新一次；用 EveryName + StopNamed 才能在回调里自我取消
    Game.Timer.EveryName("countdown", 0.1f, () =>
    {
        _remainingTime -= 0.1f;

        if (_remainingTime <= 0)
        {
            _remainingTime = 0;
            Game.Timer.StopNamed("countdown");
            OnCountdownEnd();
        }

        UpdateTimerDisplay();
    });
}

private void UpdateTimerDisplay()
{
    int minutes = Mathf.FloorToInt(_remainingTime / 60);
    int seconds = Mathf.FloorToInt(_remainingTime % 60);
    _timerText.text = $"{minutes:00}:{seconds:00}";
}
```

## 模板 3：按 scope 批量清理（回菜单 / 退关卡时用）

```csharp
// 舞台内的定时器统一打 scope，离开时一次清干净（见 patterns/client/app-flow.md §5 清场清单）
Game.Timer.StopScope("stage");
Game.Timer.StopAll();
```

## 要点

- `After` / `Every` 另有带 `scope` 的重载；无 `Group`、无 `Cron`、无 `FromSeconds`。
- 组件销毁时记得 `StopNamed` / `Stop(id)`，避免回调打在已销毁对象上。
- 目标帧率用 `Application.targetFrameRate`（不是 Timer）。

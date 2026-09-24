# 事件总线模板

> `Game.Event.On/Off` **返回 `void`**（没有可 Dispose 的句柄）：注销必须传**同一个方法引用**；`Off<T>` 的泛型参数必须与 `On<T>` 一致。

## 模板 1：注册 / 发布 / 注销

```csharp
public class EventExample : MonoBehaviour
{
    void Start()
    {
        // 注册监听（带参事件 → 显式 On<T>；传方法组时必须把 T 写明，否则无法推断）
        Game.Event.On<LevelUpData>("Player.LevelUp", OnLevelUp);

        // 发布事件
        Game.Event.Emit("Player.LevelUp", new LevelUpData { OldLevel = 9, NewLevel = 10 });
    }

    private void OnLevelUp(LevelUpData data)
    {
        Game.Logger.Info("Event", $"升级: {data.OldLevel} -> {data.NewLevel}");
    }

    void OnDestroy()
    {
        // 取消监听（同样要写明泛型参数）
        Game.Event.Off<LevelUpData>("Player.LevelUp", OnLevelUp);
    }
}
```

## 模板 2：一次性监听 / 批量注销

```csharp
// 一次性监听（触发一次后自动移除；无参事件 → 处理器必须零参）
Game.Event.Once("Game.FirstLogin", () => Game.Logger.Info("Event", "首次登录"));

// 批量：逐个 Off（传同一方法引用），或一次性 OffAll
Game.Event.Off("Event1", Handler1);
Game.Event.Off("Event2", Handler2);
// Game.Event.OffAll("Event1");   // 清掉 Event1 的全部监听
// Game.Event.OffAll();           // 清掉全部事件的全部监听
```

## 模板 3：命名空间事件 + 事件数据类

```csharp
// 命名空间格式：Module.EventName
Game.Event.On("Net.OnConnected", OnConnected);                    // 无参发布 → 处理器必须零参
Game.Event.On("Net.OnDisconnected", OnDisconnected);
Game.Event.On<int>("Player.GoldChange", OnGoldChange);            // 带参 → 显式 On<T>
Game.Event.On<BuySuccessInfo>("Shop.BuySuccess", OnBuySuccess);

// ⚠️ 无参发布的事件绑了单参委托 ⇒ **运行期永不回调**（不报错），所以参数个数必须对上。

// 事件数据类
public class LevelUpData { public int OldLevel; public int NewLevel; }
public class BuySuccessInfo { public int ItemId; public string ItemName; public int Count; public int Cost; }
```

## 模板 4：网络生命周期事件

```csharp
// 无参发布的事件 → 处理器必须零参；带参事件 → On<T> 显式给类型
Game.Event.On("Net.OnConnected",    () => { Game.Logger.Info("Event", "已连接到服务器"); OnConnected(); });
Game.Event.On("Net.OnDisconnected", () => { Game.Logger.Warn("Event", "连接断开，正在重连..."); OnDisconnected(); });
Game.Event.On<EResumeSessionReply>("Net.OnResumed", data => { Game.Logger.Info("Event", "会话已恢复"); OnResumed(); });
Game.Event.On("Net.OnKicked",       () => { Game.Logger.Warn("Event", "被踢出，需要重新登录"); OnKicked(); });
```

> 事件名常量集中放 `Core/Events.cs`（禁止业务里写裸字符串），见 `reference/architecture.md`。引擎侧事件名（`Net.*`）用 `CloverEvents.Net.*` 常量。

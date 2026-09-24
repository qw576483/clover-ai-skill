# Entity-View 绑定模板

## 模板 1：基础 Entity-View（属性绑定 + 精确注销）

```csharp
using CloverEngine;
using TMPro;              // TextMeshProUGUI
using UnityEngine;
using UnityEngine.UI;     // Slider

public class PlayerView : MonoBehaviour
{
    [SerializeField] private TextMeshProUGUI _nameText;
    [SerializeField] private TextMeshProUGUI _levelText;
    [SerializeField] private Slider _hpBar;

    // 实体号来自服务端 uint64 ⇒ 一律 ulong（见文末「实体号类型」）
    private ulong _entityId;
    private float _hp;
    private float _maxHp;
    // 保留委托引用，才能在 OnDestroy 里精确注销（lambda 直接写在 On 调用里无法注销）
    private System.Action<ulong, string, object> _onProperty;

    public void Bind(ulong entityId)
    {
        _entityId = entityId;

        // 通过 IWorldSync 监听实体数据变化
        _onProperty = (id, attrName, value) =>
        {
            if (id == _entityId)
                OnPropertyChange(attrName, value);
        };
        Game.Sync.OnEntityProperty(_onProperty);
    }

    private void OnPropertyChange(string attrName, object value)
    {
        // 属性新值就是回调参数（EntityInfo 上没有 Attrs 字段）
        switch (attrName)
        {
            case "Name":  _nameText.text = (string)value;      break;
            case "Level": _levelText.text = $"Lv.{value}";     break;
            case "Hp":    _hp = System.Convert.ToSingle(value);    break;
            case "MaxHp": _maxHp = System.Convert.ToSingle(value); break;
        }

        if (attrName == "Hp" || attrName == "MaxHp")
            _hpBar.value = _maxHp > 0f ? _hp / _maxHp : 0f;
    }

    void OnDestroy()
    {
        // 用配对的 Off* 精确注销（传注册时的同一委托引用）；
        // 不方便持有引用时，也可用 Game.Sync.Clear() 统一清理全部回调
        Game.Sync.OffEntityProperty(_onProperty);
        _onProperty = null;
    }
}
```

> **初始显示（等首个属性同步回调到达后刷新）**：引擎**没有**同步读属性的入口，`EntityInfo` 上也没有 `Attrs` 字段 —— 值只能从 `OnEntityProperty` 回调缓存里取。

## 模板 2：WorldSync 实体同步（位置插值）

```csharp
public class SyncEntityView : MonoBehaviour
{
    private ulong _entityId;
    private Vector3 _targetPosition;
    private Quaternion _targetRotation;

    public void Init(ulong entityId)
    {
        _entityId = entityId;
        // 起点对齐：否则首帧拿 (0,0,0) 当"上一位置"，算出一个横穿全图的朝向
        _targetPosition = transform.position;
        _targetRotation = transform.rotation;

        Game.Sync.OnEntityMove((id, x, y, z) =>
        {
            if (id == _entityId)
            {
                var next = new Vector3(x, y, z);
                // 朝向由"移动方向"推出（位置同步不带朝向）：只取水平分量；
                // 位移过小则不更新，避免静止时朝向抖动。
                var dir = next - _targetPosition;
                dir.y = 0f;
                if (dir.sqrMagnitude > 0.0001f)
                    _targetRotation = Quaternion.LookRotation(dir);
                _targetPosition = next;
            }
        });

        Game.Sync.OnEntityProperty((id, attrName, value) =>
        {
            if (id == _entityId) OnPropertySync(attrName, value);
        });
    }

    private void OnPropertySync(string attrName, object value) { /* 处理属性同步 */ }

    void Update()
    {
        // 插值移动到目标位置
        transform.position = Vector3.Lerp(transform.position, _targetPosition, Time.deltaTime * 10f);
        transform.rotation = Quaternion.Slerp(transform.rotation, _targetRotation, Time.deltaTime * 10f);
    }
}
```

## 模板 3：Entity 创建和销毁

> **优先走引擎的异步 View 工厂**（官方入口 `CloverPresentation.EntityView`，契约 `IEntityViewFactory`）：它立即返回可用的视图根节点（占位体已就位）、异步加载模型，并处理**加载完成时实体已不存在**的竞态、按目标身高**归一化并贴地**、可选接动画；实体的 `Destroy` / `DestroyGroup` / `ClearAll` 会同步释放工厂侧记录（动画播放器 + 模型资源引用）。
>
> ```csharp
> // ⛔ 引擎这三处的形参都是 long（Create(long,int,string) / BindView(long,GameObject) /
> //    IEntityViewFactory.CreateView(long,EntityViewSpec)），而同步实体号按本文口径是 ulong
> //    ⇒ ulong→long **无隐式转换**，必须显式 (long)，否则 CS1503。
> Game.Entity.Create((long)entityId, PLAYER_TYPE_ID);
> var view = CloverPresentation.EntityView.CreateView(
>     (long)entityId, EntityViewSpec.Of("Models/hero", targetHeight: 1.8f));
> Game.Entity.BindView((long)entityId, view);   // 登记视图；其销毁由 Entity 侧统一负责
> ```
>
> 下面是**纯手工路径**（自建 GameObject + 自己的 View 组件），仅在不需要异步模型加载时使用：

```csharp
public class EntityManager : MonoBehaviour
{
    public void SpawnPlayer(ulong entityId, Vector3 position)
    {
        // ⚠️ 世界同步给的实体号是 ulong，而 IEntityManager 当前仍是 long
        //    ⇒ 跨这两者必须显式转换（见文末「实体号类型」）
        Game.Entity.Create((long)entityId, PLAYER_TYPE_ID);

        // 绑定 View（视图不放在 EntityInfo 上：走 IEntityManager.BindView / GetView）
        var viewGo = new GameObject("Player");
        Game.Entity.BindView((long)entityId, viewGo);
        var view = viewGo.AddComponent<PlayerView>();
        view.Bind(entityId);
    }

    public void RemoveEntity(ulong entityId) => Game.Entity.Destroy((long)entityId);
}
```

## 模板 4：AOI 视野管理

```csharp
public class AOIManager : MonoBehaviour
{
    void Start()
    {
        Game.Sync.OnEntityEnter((entityId, attrs) => SpawnEntity(entityId, attrs));
        Game.Sync.OnEntityLeave((entityId) => RemoveEntity(entityId));

        // 注意：这里拿到的是服务端下发的**离散目标坐标**（约 10Hz），只适合做逻辑判定；
        // 直接拿它驱动 Transform 会抖 —— 表现层请在 Update 里用
        // Game.Sync.TryGetPosition(entityId, out x, out y, out z) 读**插值后**的位置。
        Game.Sync.OnEntityMove((entityId, x, y, z) => SetEntityTarget(entityId, new Vector3(x, y, z)));
    }

    private void SpawnEntity(ulong entityId, Dictionary<string, object> attrs)
    {
        // 根据 attrs 中的 type 字段判断实体类型
        var type = attrs.ContainsKey("type") ? attrs["type"]?.ToString() : "default";
        switch (type)
        {
            case "player":  SpawnPlayer(entityId);  break;
            case "monster": SpawnMonster(entityId); break;
        }
    }

    private void RemoveEntity(ulong entityId) => Game.Entity.Destroy((long)entityId);

    private void UpdateEntityPosition(ulong entityId, Vector3 position)
    {
        var view = Game.Entity.GetView((long)entityId);
        if (view != null) view.transform.position = position;
    }
}
```

## 实体号类型（`ulong` vs `long`，照抄前必读）

服务端对象号是 `uint64`，因此**世界同步一路都是 `ulong`**：

- `IWorldSync`：`TryGetPosition(ulong)`、`OnEntityEnter/Leave/Move/Property(Action<ulong …>)`、以及配对的 `Off*`（`Runtime/Core/Contracts.cs:495,535-571`）；
- `ICloverScene`：`SceneID` / `RegisterMapping(ulong)` / `ResolveUnityScene(ulong)`。

⚠️ **但 `IEntityManager` / `EntityInfo.ObjectID` / `IEntityViewFactory` 目前仍是 `long`**（`Runtime/Core/EntityPool.cs:27,60,81,87,256`）—— 这是**引擎侧尚未统一的残留**，不是让你"再包一层 long"。跨这两者时要**显式转换**：

```csharp
Game.Sync.OnEntityEnter((ulong id, Dictionary<string, object> attrs) =>
{
    Game.Entity.Create((long)id, typeID);          // ulong → long：显式
    var v = CloverPresentation.EntityView.CreateView((long)id, spec);
    Game.Entity.BindView((long)id, v);
});
```

**别把世界同步回调的参数声明成 `long`**：那会让 `id == _entityId` 这类比较直接编译不过（`ulong` 与 `long` 之间无隐式转换），或者更糟 —— 用 `(long)id` 转换后在 `id` 高位为 1 时得到负数，表现为"实体找不到 / 视图不显示"而**不报错**。

## 模板 5：实体属性绑定（血条）

```csharp
public class HealthBarView : MonoBehaviour
{
    [SerializeField] private Slider _hpBar;
    [SerializeField] private TextMeshProUGUI _hpText;

    private ulong _entityId;
    private float _hp;
    private float _maxHp;

    public void Bind(ulong entityId)
    {
        _entityId = entityId;

        // 属性新值由回调给出（EntityInfo 上没有 Attrs 字段）
        Game.Sync.OnEntityProperty((id, attrName, value) =>
        {
            if (id != _entityId) return;
            if (attrName == "Hp") _hp = System.Convert.ToSingle(value);
            else if (attrName == "MaxHp") _maxHp = System.Convert.ToSingle(value);
            else return;
            UpdateHpDisplay();
        });
    }

    private void UpdateHpDisplay()
    {
        _hpBar.value = _maxHp > 0f ? _hp / _maxHp : 0f;
        _hpText.text = $"{_hp:F0}/{_maxHp:F0}";
    }
}
```

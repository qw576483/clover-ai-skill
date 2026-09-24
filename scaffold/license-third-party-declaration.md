# 交付用 `LICENSE` 模板（MIT + **第三方素材声明**）

> **为什么单独有这份**：仓库根现有的 `LICENSE`（以及 `clover-tools`、引擎仓那几份，
> 三份 **sha256 逐字节相同** = `725afdc0 850dd90a 90dac25b 2362f22e f1ca8630 c3f9a652 77d0cf83 1bbaf1d0`）
> **只含 MIT，没有"第三方素材"这一节**。
> 一旦工程用了**第三方 / 原作的名称、形象、图像、音效**，交付时那份 MIT 文件就是**不完整**的：
> 它只声明了"代码"的权利状态，等于把"素材"这块**静默留白**。
> ⇒ **交付时的 `<项目根>/LICENSE` 必须换成下面这份形状**（⛔ 不是新增第二个文件）。
>
> 占位符：`{A}` = 原作名称、`{权利人}` = 该素材的著作权 / 商标权人、`{原版资源目录}` = 本项目存放原版素材的目录（如 `原版资源/`）。

```markdown
# 许可与版权声明

## 用途

本项目**仅用于技术交流与学习**，**禁止用于任何商业用途**。

## 代码

本项目原创的代码（源代码、工具脚本、配置与文档）采用 MIT 许可证：

```
MIT License

Copyright (c) <年> Clover

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 第三方素材

- 《{A}》的名称、角色形象、图像、音效及其他内容，其著作权与商标权均归 **{权利人}** 所有。
- 本项目仅以学习研究为目的在本地重现该游戏的**部分**内容，**不对上述素材主张任何权利**。
- 原版游戏资源（`{原版资源目录}`）**不随本仓库分发**。
- 若权利人认为本项目存在不当之处，**请联系删除**。
```

## 落地要求（每一条都有判据）

| # | 要求 | 判据 |
|---|---|---|
| 1 | 三等节都在：**用途 / 代码(MIT) / 第三方素材** | `LICENSE` 里三节标题都在；⛔ 只有 MIT 一节 = 不合格 |
| 2 | 第三方素材四条都在：**权利人 + 不主张权利 + 原版资源不分发 + 可联系删除** | 逐条 grep 关键词命中；用 `{A}` / `{权利人}` 的**实际值**替换，⛔ 不残留占位符 |
| 3 | `README.md` 的「声明」一节与 `LICENSE` **口径一致**（都有"仅供学习 / 禁止商用"） | 两处都读一遍，措辞不许一严一松 |
| 4 | **原版资源目录不随仓库分发**：该目录在 `.gitignore` 里，且真实仓库里**0 文件被跟踪** | `git -C <工作区根> check-ignore -v -- <项目根>/<原版资源目录>` 有命中；`git -C <工作区根> status --porcelain -uall -- <项目根>/<原版资源目录>` **计数为 0** |
| 5 | ⛔ **不新增**第二个许可文件（`LICENSE-*.txt` 之类） | 项目根 `LICENSE` 唯一；多文件 = 读者只读一半 |

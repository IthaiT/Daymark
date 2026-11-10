# Obsidian 块 ID 的编辑保护调研

当前笔记的 YAML 属性 `daymark-id` 与正文行末统一保存完整的 `^daymark-obsidian-UUID`；两种位置表示同一个事项身份。仅接受这一种格式，旧格式不自动迁移。以下块 ID 的编辑保护讨论针对文件内的事项行。

调研日期：2026-11-08。结论是保留原生 `^块 ID` 作为持久身份，但把编辑保护放到 Obsidian 编辑器扩展中。透明 CSS 只改变外观，不提供数据保护；不应把它描述成“不可编辑的隐藏字段”。

实现更新（2026-11-10）：已在 [`plugins/daymark-id-guard`](../plugins/daymark-id-guard/README.md) 实现独立插件，保留现有格式。实时预览及源码模式隐藏事项行末身份，过滤普通误改，专门处理整行／子树剪切、复制、一次性移动身份和临时解锁。65 项插件无窗口测试及 42 项现有 Daymark Obsidian 测试通过；尚未在真实 Obsidian、Tasks 插件组合和原生中文输入法中运行验证。

## 可选方案

| 方案 | 编辑体验与身份保证 | 判断 |
| --- | --- | --- |
| `opacity: 0`、零字号或 `display: none` | 视觉变化不等于文档变化；选择、删除、替换、剪贴板仍操作源码 | 不适合作为身份保护机制 |
| 仅在当前编辑行显示 ID | 能看到行末元数据，减少单行编辑时的盲改；多行选择或删除仍可改坏 ID | 无插件时可采用的折中 |
| 原生块 ID + 编辑器扩展 | 隐藏显示、跳过光标、过滤元数据修改，并专门处理块的剪切和复制 | 最符合当前 Daymark 格式的实现方向 |
| 用外部索引、名称或内容散列代替行内身份 | 文件/行号会移动，名称/正文会修改；相同正文和跨文件剪切使匹配有歧义 | 可辅助定位，不能独立保证身份 |
| 每个事项单独一个文件，ID 放入文件属性 | 文件身份与正文分离更自然；但改变现有“一份文件包含事项树”的组织方式 | 需要改变工作流，当前不采用 |

Obsidian 官方开发文档说明，实时预览的显示和交互应通过 CodeMirror 6 编辑器扩展实现；`Decoration.replace` 可隐藏或替换源码范围。官方没有在这些接口文档中提供“Markdown 里的某个字段天然不可编辑”的保证。

`EditorView.atomicRanges` 只控制常规光标移动，让光标跨过整个范围；文档明确指出它也不阻止程序直接把选区放进去。CodeMirror 的删除命令会通过 `skipAtomic` 扩展删除范围，因此只加原子范围，仍可能一次删掉整个 ID。还需要事务过滤以及清楚定义的整行/子树操作规则。`transactionFilter` 可替换或取消事务，但 `filter: false` 的事务会绕过它，所以对其他插件和外部文件修改也不能作绝对保证。

## 现有社区实现的适用性

检索了 Obsidian 官方社区插件目录，并检查 Block Link Plus 的公开实现。其 `2.0.21` / 源码提交 `e106093ac008677b161d8b9580e72a7e6af99b2f` 提供大纲编辑器：`OutlinerBlock` 分别存放 `id`、可编辑 `text` 和 `system`，序列化时再写回文件。这是可参考的正文与身份分离方式。

但它不是当前 Daymark 的直接替代品：其协议包含独立的 `[blp_sys:: 1]` 等系统尾行；`serializeOutlinerBlocksForClipboard` 明确只输出正文与子树，不输出系统字段或块 ID，`copyBlockSubtree` 就调用这个函数；文本剪切则读取正文编辑器里的选区。不能由“支持隐藏 ID”推断它能够满足“跨文件 Ctrl+X 后保留 Daymark 历史关联”。这些结论来自源码审阅，未在用户当前 Obsidian/Tasks 插件组合中进行安装或运行验证。

BlindFold 的目标是折叠可展开的正文区块，不是管理每条 Tasks 事项的稳定身份。没有把它作为 ID 保护方案。

## 建议实现的保护规则

继续使用当前 ID，避免更换标识导致额外迁移；在 Daymark 管理的目录中由一个小型 Obsidian 扩展处理：

1. 用替换装饰隐藏身份范围，用原子范围使普通光标移动跳过它。
2. 普通输入、Backspace、Delete、局部替换不得修改或删除身份范围；不能只在保存后补回 ID，因为此时已难以判断用户是改正文还是删除/新建事项。
3. 移动完整行或完整子树时，允许从源文件删除，并把原 ID 连同源码放入剪贴板；复制出新的独立事项则分配新 ID。不能统一从剪贴板剥离 ID。
4. 保持撤销/重做、中文输入法、选区替换、缩进和跨文件粘贴的正常语义；为显式维护 ID 提供解锁方式。
5. Daymark 同步继续校验重复 ID，并保留旧记录及树备份；身份有歧义时提示用户处理，不按名称猜测或自动将旧记录改绑。

上述规则已落实到 [Daymark 事项保护插件](../plugins/daymark-id-guard/README.md)，通过真实 CodeMirror 的无窗口测试；Obsidian 生命周期使用宿主模拟。剪切身份只在同一次插件运行期间允许复用一次，粘贴前检查原位置已移除；无法证明来自本次剪切时按复制分配新 ID。多光标剪贴板及含身份的整行拖拽不支持；不保护 YAML 属性，也不能拦截外部文件改写或绕过过滤的事务。启用前仍需在隔离仓库验证真实输入法、Obsidian 与 Tasks 的组合行为，详见插件说明。

## 现在即可使用的无插件折中

提供 [编辑当前行时显示 ID 的样式](../tools/obsidian-daymark-reveal-on-edit.css)。用它替换之前的全隐藏样式：复制到 Vault 的 `.obsidian/snippets/`，在「设置 → 外观 → CSS 代码片段」启用。

未编辑的行隐藏块 ID；当前行显示 ID，源码模式保持正常。它适合暂时减少单行编辑时看不见元数据的问题，**不锁定 ID**，多行选择、替换与删除仍须保留完整行尾身份。需要始终隐藏且防误改时，应采用上述编辑器扩展。

## 依据

- [Obsidian：编辑器扩展](https://docs.obsidian.md/Plugins/Editor/Editor+extensions)，[官方文档源文件](https://github.com/obsidianmd/obsidian-developer-docs/blob/main/en/Plugins/Editor/Editor%20extensions.md)。
- [Obsidian：装饰与替换范围](https://docs.obsidian.md/Plugins/Editor/Decorations)，[官方文档源文件](https://github.com/obsidianmd/obsidian-developer-docs/blob/main/en/Plugins/Editor/Decorations.md)。
- [CodeMirror：原子范围](https://codemirror.net/docs/ref/#view.EditorView%5EatomicRanges)、[官方示例](https://codemirror.net/examples/decoration/#atomic-ranges)。
- [CodeMirror：事务过滤](https://codemirror.net/docs/ref/#state.EditorState%5EtransactionFilter)、[删除命令源码](https://github.com/codemirror/commands/blob/main/src/commands.ts)。
- [Obsidian 官方社区插件清单](https://github.com/obsidianmd/obsidian-releases/blob/master/community-plugins.json)。
- [Block Link Plus 数据协议与剪贴板序列化](https://github.com/jasper-1024/block-link-plus/blob/e106093ac008677b161d8b9580e72a7e6af99b2f/src/features/file-outliner-view/protocol.ts#L505)，[复制和文本剪切调用](https://github.com/jasper-1024/block-link-plus/blob/e106093ac008677b161d8b9580e72a7e6af99b2f/src/features/file-outliner-view/view.ts#L1290)。
- [BlindFold 说明](https://github.com/vzsky/blindfold-obsidian#readme)。

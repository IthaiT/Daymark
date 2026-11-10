# Daymark 事项保护

在 Obsidian 中隐藏并保护事项行末的完整 `^daymark-obsidian-UUID`。实时预览和源码模式都隐藏，编辑当前行时也不显示；原始 Markdown 仍保存 ID，Daymark 继续通过它关联时间记录。不更换已有 ID，不迁移数据格式。

## 安装

本工作区已构建好可安装目录：`release/daymark-id-guard/`。只需其中的 `main.js` 和 `manifest.json`，不需要复制源代码或 `node_modules`。

1. 将 `release/daymark-id-guard/` 整个文件夹复制到 Obsidian 仓库的 `.obsidian/plugins/`，得到 `.obsidian/plugins/daymark-id-guard/main.js` 和 `manifest.json`。
2. 在 Obsidian「设置 → 第三方插件」允许第三方插件，重新加载后启用「Daymark 事项保护」。插件为本地安装，无需上架社区目录。
3. 打开插件设置，填写**仓库内相对路径**并点击「保存并启用」。例如，仓库为 `D:\Vault`，Daymark 同步目录为 `D:\Vault\工作\Daymark`，这里填写 `工作/Daymark`。仓库根目录填写 `/`；留空表示关闭。只处理该目录直属的 `.md` 文件，与 Daymark 的导入范围一致。
4. 如果以前启用了 `obsidian-daymark.css` 或 `obsidian-daymark-reveal-on-edit.css`，请停用，避免它们继续影响其他块 ID 或遮住解锁后的 ID。

更新时停用插件，替换这两个安装文件，再启用。保留插件目录中的 `data.json` 即可保留目录设置；停用或卸载不会删除 Markdown 中的身份。

## 编辑规则

| 操作 | 行为 |
| --- | --- |
| 修改名称、描述、结果、勾选状态、缩进 | 保留原 ID |
| 移动光标或按 End 到行末 | 跳过隐藏字段；普通输入在 ID 之前 |
| 局部删除、替换隐藏字段 | 在写入编辑器之前拦截；保留当前内容和选区 |
| 当前事项正文中按 Enter | 保留原事项身份，在现有子树之后另建带新 ID 的同级事项，子事项仍属于原父事项；从名称开头回车时原身份随原正文移到下一行 |
| 空事项按 Enter | 退出列表，移除该空事项及其 ID |
| 无选区 Ctrl+X / Ctrl+C | 剪切／复制整行，包括不可见的 ID；复制生成新 ID |
| 选中完整的可见事项行后剪切／复制 | 自动包含隐藏的行末 ID；只选择名称仍属于文字编辑 |
| 跨文件粘贴剪切的完整事项／子树 | 第一次粘贴检查原位置确实已移除事项，然后保留原 ID |
| 重复粘贴、普通复制或外部来源的 ID | 分配新 ID，避免把副本关联到原事项 |
| 普通文字复制 | 不把选区中隐藏 ID 的片段输出到剪贴板 |
| 撤销／重做 | 使用 Obsidian 编辑器历史，恢复当次操作的原始 ID |

命令面板提供以下命令，也可以在 Obsidian「快捷键」设置中自行绑定：

- **剪切当前事项及子事项**：按缩进包含后续子事项及其正文，跨文件粘贴保留身份。
- **复制当前事项及子事项**：建立独立副本，为子树各事项分配新 ID。
- **删除当前事项及子事项**：整体删除，支持撤销。
- **显示并解锁 ID／恢复隐藏保护**：维护身份时临时显示并允许修改。解锁作用于配置目录，重新加载插件后自动恢复保护。

没有 ID 的新事项仍可正常输入，下一次 Daymark 同步会生成 ID。插件通过回车创建的事项直接获得新 ID。事项名称不能为空；未填完的空事项请填好或退出列表后再同步。

## 范围与限制

- 仅处理有效的 Daymark 事项行末身份；笔记 YAML 的 `daymark-id`、其他原生块 ID、代码块和注释不属于本插件的保护范围。格式错误的行末标识保持可见，交由 Daymark 校验。
- 完整事项的系统剪贴板文本仍包含 ID，所以可以跨文件移动并保留关联。将它粘贴到未配置保护的目录或其他软件中，ID 可能显示。
- 剪切和保留原身份的粘贴须在**同一插件运行期间**完成。重新加载插件后无法证明剪贴板来自本次剪切，按复制处理，使用新 ID。
- 各文件的撤销历史相互独立。剪切后先撤销源文件再粘贴，会按复制分配新 ID；移动完成后仅撤销源文件的剪切，可能重新造成重复 ID，需配合撤销目标粘贴。Daymark 仍会拒绝重复身份，不猜测关联。
- 多光标的事项剪贴板操作暂不支持。跨多行替换若涉及某个事项的部分隐藏身份，会被拦截；请选完整行，或用子树命令。行末 Delete 不用于合并两个事项，避免把 ID 放到正文中间。
- 含身份的整行文字拖拽会被阻止，请改用剪切／粘贴。原生复制行若制造重复 ID，也会被拦截，请用 Ctrl+C / Ctrl+V 或插件复制命令。
- 插件通过编辑器事务保护普通编辑，其他软件直接写文件、其他插件绕过事务过滤的改写不受此保护。插件不在保存后猜测并补回身份，也不直接写笔记文件。

## 开发与验证

开发环境：本工作区使用 Node.js 24.14.0。Obsidian 最低版本声明为 1.6.0，构建使用官方 SDK 1.14.4 的类型与其匹配的 CodeMirror 依赖；尚未在各 Obsidian 版本中完成运行矩阵验证。

```powershell
cd D:\Workspace\Temp\Daymark\plugins\daymark-id-guard
npm ci
npm run check
```

构建沿用官方示例的 TypeScript + esbuild + CommonJS 方式，`obsidian` 和 CodeMirror 保持 external，使用宿主提供的实例。输出 `main.js`，并生成仅含两个安装文件的 `release/daymark-id-guard/`。这些构建产物和依赖不提交 Git。修改的是独立 Obsidian 插件，不需要重建 Daymark 的 Flutter Windows 程序。

65 项测试使用真实 CodeMirror 状态、视图、命令及历史，在 jsdom 中运行；宿主生命周期测试模拟 Obsidian API。覆盖隐藏 DOM、编辑拦截、输入法事务、回车及子事项归属、缩进、只读、完整行和子树、跨文件剪切、复制、重复及并发粘贴、撤销源剪切、读写失败、异步操作期间继续编辑、目录切换与设置写入失败。另已通过 Daymark 原有 42 项 Obsidian 导入、同步、导航、删除及 Widget 测试。

**尚未在真实 Obsidian／Tasks 插件组合及原生中文输入法中运行验证。** 安装到日常仓库前，建议先在隔离仓库完成：当前行输入与删除、中文组词确认、勾选完成、父子事项缩进、整行／子树跨文件剪切、复制、重复粘贴、撤销重做、源码模式与临时解锁。原生窗口测试须遵循仓库要求，使用私有非活动桌面，不能在活动桌面打开自动测试窗口。

实现依据：[Obsidian 装饰接口](https://docs.obsidian.md/Plugins/Editor/Decorations)、[官方示例构建](https://github.com/obsidianmd/obsidian-sample-plugin/blob/master/esbuild.config.mjs)、[CodeMirror 事务过滤](https://github.com/codemirror/state/blob/main/src/state.ts)。

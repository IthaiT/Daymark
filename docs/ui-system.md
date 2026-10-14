# 共享桌面 UI

时间记录和记账统一采用 Material 3 的浅灰工作区、白色面板和青绿色操作强调。
参考 [Material 3 字体层级](https://m3.material.io/styles/typography/applying-type)
以及 [Linear 对导航、标题和面板层级的整理](https://linear.app/now/how-we-redesigned-the-linear-ui)。

## 共用组件与样式

- `lib/ui/theme.dart`：唯一的应用主题、字号、字重、输入框、菜单与控件样式；模块不再覆盖主题。
- `lib/ui/workspace_style.dart`：工作区边距、列间距、侧栏宽度、圆角等统一参数，以及 `WorkspaceLayout`、`WorkspacePanel`、`WorkspaceSectionHeader`、`AppSegmentedButton`。
- `lib/ui/tag_visual.dart`：`AppTagBadge` 和强调色到背景、前景的对比规则；时间标签、事件与记账分类使用同一规则。
- `lib/ui/tag_drop_target.dart`：标签拖放的上方、内部、下方三个目标区域及插入线。

常规正文 14，辅助文字 12，面板标题 16，较大标题与金额 20；字距为零、行高 1.45。
工作区和面板采用共享边距；小窗口允许水平滚动。布局树保持稳定，缩放窗口不会重建侧栏、丢失折叠状态或输入。
时间标签选择器复用侧栏的标签行，徽标和字体保持一致。

## 字体

项目内置 [Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc)，支持简体中文、英文和数字，字重轴为 100–900。
字体直接打包进 Release，不依赖网络请求或系统安装。异常字符保留 Windows 字体回退。
来源版本、完整文件 SHA-256 与 SIL OFL 授权见 `assets/fonts/README.md` 和 `assets/fonts/OFL.txt`；授权文件随发布资源一起打包。

## 标签操作

记账标签旁只保留金额与备注入口。右键新增、编辑、移至一级或删除，分类管理窗口支持点击编辑或右键管理。
标签按住 250 毫秒后拖动：行上方／下方显示插入线，调整同级顺序；中间区域高亮表示移入该标签。
主标签和子标签均可排序。调整层级与顺序组成一个原子事务，支持撤销重做；失败保留原分类、顺序、流水关联与输入。
分类 ID 和色系不因排序、改名或移动改变。

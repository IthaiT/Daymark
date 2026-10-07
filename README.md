# Daymark

一个本地运行的 Python 桌面时间记录工具，帮助你看见一天中的时间分配。

首版使用 Tkinter，不需要 Web 服务或第三方 Python 库。标签写入 JSON，事件写入 CSV。

## 开发环境

```powershell
conda env create --prefix ./.conda --file environment.yml
conda activate ./.conda
python -m daymark
```

也可以直接运行 `./.conda/python.exe -m daymark`，无须激活环境。当前机器的环境已经创建在 `E:\Workspace\Daymark\.conda`。

Windows 上可以双击 `start.cmd` 打开软件；或者在 PowerShell 中运行 `./start.ps1`。

如 PowerShell 的 Conda 初始化有问题，可以用 Miniconda 自带的 Python 调用 Conda：

```powershell
& 'D:/Creation_Tool/Miniconda/python.exe' -m conda env create --prefix ./.conda --file environment.yml
```

## 首版范围

- 任意层级的标签：新增、重命名、移动到其他父标签。
- 手动记录事件的开始和结束时间，提供日历和小时、分钟选择器。
- 修改事件内容、标签和时间，删除事件。
- 按日期浏览横向时间轴和事件明细。
- 标签树右键管理、拖拽移动，事件使用树状下拉选择标签。
- 本地存储，不上传数据。

开发使用 Git 单分支线性历史，将环境、数据层、界面和验证分步提交。

## 使用方法

1. 在左侧标签上右键，选择「新增子标签」「修改标签」或「删除标签」。在树的空白处右键可新增一级标签；双击标签也可修改。
2. 将标签拖到另一个标签上，整个分支会移动到该标签下。拖到树的空白处，或右键选择「移至一级标签」，可将分支移到顶层。不允许移动到自己或自己的子标签中。
3. 点击「补录事件」填写名称。在标签框中打开树状下拉框，展开分支，单击目标标签即可选定并关闭下拉框。父标签修改和批量更换标签也使用相同组件。
4. 点击日期输入框或日历按钮选择日期，点击时间输入框或下拉按钮选择小时和分钟，然后点击「确定」。按 Esc 可关闭选择器并继续输入；也可以通过 Tab 聚焦字段，直接输入 YYYY-MM-DD 和 HH:MM。支持跨午夜，不需要输入秒。
5. 在时间轴上悬停查看详情，单击选中事件，双击编辑。选择「2× / 4× 放大」查看较短事件；滚轮横向移动，Shift+滚轮纵向移动。
6. 在事件列表中按 Ctrl 或 Shift 多选，点击「更换标签」可以批量转移事件。编辑窗口还支持修改名称、时间和备注。
7. 左侧标签树只用于管理标签，点击不会筛选右侧记录。时间轴和列表始终显示所选日期的全部事件。
8. 用日期输入框、前后箭头或「今天」浏览日期。快捷键：Ctrl+N 补录事件，Ctrl+←/→ 切换日期。

事件可以重叠，时间轴自动分行。列表中的「本日用时」只显示事件在选中日期内的时长。界面采用白底黑字，时间轴中的标签使用浅色区分。

删除标签前，必须先移走它的子标签和关联事件；这能避免历史记录失去分类。

## 数据文件

首次运行自动建立项目目录下的 `data/`：

| 文件 | 内容 |
| --- | --- |
| `tags.json` | 标签 ID、名称、父标签 ID，带版本号 |
| `events.csv` | 事件名称、标签 ID、开始/结束时间、备注 |
| `.daymark.lock` | 防止两个窗口同时写入同一个数据目录的锁 |

标签示例：

```json
{
  "version": 1,
  "tags": [
    {"id": "work", "name": "主业", "parent_id": null},
    {"id": "embedded", "name": "嵌入式", "parent_id": "work"},
    {"id": "linux", "name": "Linux", "parent_id": "embedded"}
  ]
}
```

CSV 列固定为 `id,title,tag_id,start,end,notes`。时间格式为 `2026-10-07T09:00:00`，新记录精确到分钟；空 `tag_id` 表示未分类。CSV 使用 UTF-8 BOM，便于 Excel 显示中文。标签 ID 稳定，改名和移动只修改标签文件。

旧版数据可以直接读取，不会自动重写。已有秒数在只修改名称或分类时会保留。旧记录缺少结束时间时，列表显示「待补全」；补齐时间后才会显示在时间轴上。

保存采用同目录临时文件加原子替换。读取失败会显示错误并保留原文件，不会重建覆盖。不要在软件运行时手动修改数据；Excel 打开 CSV 时可能阻止保存，请先关闭文件。备份时关闭软件，复制整个 `data` 文件夹即可。

可以指定另一个数据目录，方便分开工作日志或测试：

```powershell
./.conda/python.exe -m daymark --data-dir ./another-journal
```

## 项目结构与验证

```text
daymark/
  __main__.py    启动入口与自定义数据目录
  app.py         主界面、标签右键菜单和拖拽管理
  dialogs.py     标签、事件和批量分类编辑
  widgets.py     树状标签、日历和分钟级时间选择器
  timeline.py    横向时间轴、缩放、提示和点击交互
  model.py       事件模型、跨天裁剪和重叠计算
  storage.py     JSON/CSV 校验与原子保存
  instance.py    数据目录的进程锁
tests/          数据层和真实 Tk 窗口集成测试
```

运行数据层测试（无需打开窗口）：

```powershell
./.conda/python.exe -m unittest discover -s tests -p test_storage.py -v
```

运行全部测试（会短暂打开测试窗口，测试数据使用独立目录）：

```powershell
$env:DAYMARK_UI_TESTS = '1'
./.conda/python.exe -m unittest discover -s tests -v
```

当前通过 29 项测试，覆盖标签关联保持、中文和换行 CSV、跨天和重叠显示、旧数据兼容、原子保存失败、损坏数据保护、右键及拖拽操作、树状/日期/时间选择、窗口布局和单实例锁。交互回归测试通过鼠标按下/释放和键盘事件验证名称、备注、标签选择以及弹窗关闭后的焦点恢复。

这是一个单机最小版。时间采用本机本地时间，不做跨时区转换；暂未实现多标签事件、自动识别电脑活动、周/月报表、云同步和安装包。

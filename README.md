# Daymark · 日迹

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
- 手动补录事件的开始和结束时间，也可以开始/结束实时计时。
- 修改事件内容、标签和时间，删除事件。
- 按日期浏览横向时间轴、事件明细和分类用时。
- 本地存储，不上传数据。

开发使用 Git 单分支线性历史，将环境、数据层、界面和验证分步提交。

## 使用方法

1. 在左侧标签树选中一个标签，再点击「新增标签」，新标签默认放在选中标签之下。不选择父标签时可创建一级标签。
2. 双击标签或点击「修改 / 移动标签」，可以修改名称、选择新的父标签。整个分支和历史事件自动跟随；不允许形成循环或同级重名。
3. 在「正在做什么」中输入事件名称、选择标签，点击「开始计时」，完成后点击「结束」。退出软件后开始时间仍被保留，再次打开可以继续或结束。
4. 忘记计时可点击「补录事件」，输入开始和结束日期、时间，支持跨午夜。每个事件选择一个标签，完整的祖先路径自动展示。
5. 在时间轴上悬停查看详情，单击选中事件，双击编辑。选择「2× / 4× 放大」查看较短事件；滚轮横向移动，Shift+滚轮纵向移动。
6. 在事件列表中按 Ctrl 或 Shift 多选，点击「更换标签」可以批量转移事件。编辑窗口还支持修改名称、时间和备注。
7. 左侧选中标签可筛选该标签及其全部子标签的事件；「显示全部事件」取消筛选。顶部卡片和右侧用时分布始终展示全天统计。
8. 用日期输入框、前后箭头或「今天」浏览日期。快捷键：Ctrl+N 补录事件，Ctrl+←/→ 切换日期。

事件可以重叠，时间轴自动分行。「事件累计」将每件事的用时相加，「实际覆盖」将重叠部分去重。「全天未记录」是全天 24 小时减去覆盖时间，包含尚未到来的时间。跨天事件只统计在选中日期内的部分。少于一分钟的事件显示「不足 1 分钟」；在同一秒内开始、结束的计时按 1 秒保存。

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

CSV 列固定为 `id,title,tag_id,start,end,notes`。时间格式为 `2026-10-07T09:00:00`；空 `tag_id` 表示未分类，空 `end` 表示正在计时。CSV 使用 UTF-8 BOM，便于 Excel 显示中文。标签 ID 稳定，改名和移动只修改标签文件。

保存采用同目录临时文件加原子替换。读取失败会显示错误并保留原文件，不会重建覆盖。不要在软件运行时手动修改数据；Excel 打开 CSV 时可能阻止保存，请先关闭文件。备份时关闭软件，复制整个 `data` 文件夹即可。

可以指定另一个数据目录，方便分开工作日志或测试：

```powershell
./.conda/python.exe -m daymark --data-dir ./another-journal
```

## 项目结构与验证

```text
daymark/
  __main__.py    启动入口与自定义数据目录
  app.py         主界面、筛选、计时和统计
  dialogs.py     标签、事件和批量分类编辑
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

当前通过 17 项测试，覆盖标签改名/移动后关联保持、中文和换行 CSV、跨天及重叠统计、计时恢复、原子保存失败、损坏数据保护、窗口操作和单实例锁。

这是一个单机最小版。时间采用本机本地时间，不做跨时区转换；暂未实现多标签事件、自动识别电脑活动、周/月报表、云同步和安装包。

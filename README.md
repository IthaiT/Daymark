# Daymark · 日迹

一个本地运行的 Python 桌面时间记录工具，帮助你看见一天中的时间分配。

首版使用 Tkinter，不需要 Web 服务或第三方 Python 库。标签写入 JSON，事件写入 CSV。

## 开发环境

```powershell
conda env create --prefix ./.conda --file environment.yml
conda activate ./.conda
python -m daymark
```

也可以直接运行 `./.conda/python.exe -m daymark`，无须激活环境。

## 首版范围

- 任意层级的标签：新增、重命名、移动到其他父标签。
- 手动补录事件的开始和结束时间，也可以开始/结束实时计时。
- 修改事件内容、标签和时间，删除事件。
- 按日期浏览横向时间轴、事件明细和分类用时。
- 本地存储，不上传数据。

开发使用 Git 单分支线性历史，将环境、数据层、界面和验证分步提交。

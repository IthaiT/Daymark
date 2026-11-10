import { type EditorState, type Extension } from "@codemirror/state";
import {
  editorInfoField,
  Notice,
  Plugin,
  PluginSettingTab,
  Setting,
  type App,
} from "obsidian";
import { GuardClipboard } from "./clipboard";
import { createIdGuard } from "./guard";
import { isManagedPath, normalizeFolder } from "./identity";

interface Settings {
  folder: string;
}

function filePath(state: EditorState): string {
  return state.field(editorInfoField, false)?.file?.path ?? "";
}

export default class DaymarkIdGuard extends Plugin {
  settings: Settings = { folder: "" };
  unlocked = false;
  private readonly extensions: Extension[] = [];
  private clipboard!: GuardClipboard;
  private lastBlockedNotice = 0;

  async onload(): Promise<void> {
    const stored: unknown = await this.loadData();
    if (stored && typeof stored === "object" && "folder" in stored && typeof stored.folder === "string") {
      this.settings.folder = normalizeFolder(stored.folder) ?? "";
    }
    this.clipboard = new GuardClipboard({
      enabled: (state) => this.enabled(state),
      notify: (message) => { new Notice(message); },
    });
    this.configure();
    this.registerEditorExtension(this.extensions);
    this.addSettingTab(new GuardSettingsTab(this.app, this));
    this.addCommand({
      id: "toggle-unlock",
      name: "显示并解锁 ID／恢复隐藏保护",
      callback: () => {
        this.unlocked = !this.unlocked;
        this.configure();
        new Notice(this.unlocked ? "Daymark ID 已显示并解锁。维护后请恢复保护。" : "Daymark ID 已恢复隐藏与保护。");
      },
    });
  }

  private enabled(state: EditorState): boolean {
    return !this.unlocked && isManagedPath(filePath(state), this.settings.folder);
  }

  private configure(): void {
    this.extensions.splice(0, this.extensions.length,
      createIdGuard({
        enabled: (state) => this.enabled(state),
        blocked: () => {
          if (Date.now() - this.lastBlockedNotice > 1500) {
            this.lastBlockedNotice = Date.now();
            new Notice("已阻止对隐藏 ID 的修改。删除或移动事项请选中完整行；维护 ID 请先解锁。");
          }
        },
      }),
      this.clipboard.extension(),
    );
    this.app.workspace.updateOptions();
  }

  async setFolder(value: string): Promise<void> {
    const folder = value.trim() ? normalizeFolder(value) : "";
    if (folder === null) {
      new Notice("请输入仓库内相对路径，例如 工作/Daymark；仓库根目录填写 /。");
      return;
    }
    try {
      await this.saveData({ folder });
    } catch {
      new Notice("设置保存失败，已保留原设置。");
      return;
    }
    this.settings = { folder };
    this.unlocked = false;
    this.configure();
    new Notice(folder ? `已保护 ${folder} 直属的 Markdown 事项。` : "已关闭目录保护。");
  }
}

class GuardSettingsTab extends PluginSettingTab {
  constructor(app: App, private readonly guard: DaymarkIdGuard) { super(app, guard); }

  display(): void {
    this.containerEl.empty();
    let folder = this.guard.settings.folder;
    new Setting(this.containerEl)
      .setName("Daymark 事项文件夹")
      .setDesc("填写与 Daymark 同步目录对应的仓库内相对路径，例如 工作/Daymark。只保护直属 .md 文件；根目录填 /，留空关闭。")
      .addText((text) => text.setPlaceholder("工作/Daymark").setValue(folder).onChange((value) => { folder = value; }))
      .addButton((button) => button.setButtonText("保存并启用").setCta().onClick(async () => {
        button.setDisabled(true);
        try { await this.guard.setFolder(folder); }
        finally { button.setDisabled(false); }
      }));
    new Setting(this.containerEl)
      .setName("维护 ID")
      .setDesc("命令面板中使用「显示并解锁 ID／恢复隐藏保护」。解锁仅在本次运行有效，重新启动插件后恢复保护。普通编辑及源码模式默认均隐藏任务行末 ID；文件属性不受此保护。");
  }
}

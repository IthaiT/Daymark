import { Text } from "@codemirror/state";
import { describe, expect, it } from "vitest";
import { freshenIdentities, isManagedPath, normalizeFolder, scanIdentities } from "../src/identity";

export const id = (n: number) => `^daymark-obsidian-00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const scan = (text: string) => scanIdentities(Text.of(text.split("\n")));

describe("Daymark identity scanner", () => {
  it.each(["- [ ]", "+ [/]", "* [-]", "1. [x]", "23) [X]"])("recognizes %s and hides only its suffix", (prefix) => {
    const text = `${prefix} 事项 | 描述 | 结果 ${id(1)}  `;
    const [span] = scan(text);
    expect(span?.id).toBe(id(1));
    expect(text.slice(0, span!.from)).toBe(`${prefix} 事项 | 描述 | 结果`);
  });

  it("recognizes an empty task so Enter can exit a list", () => {
    const [span] = scan(`- [ ]  ${id(1)}`);
    expect(span?.id).toBe(id(1));
    expect(span?.bodyFrom).toBe(span?.from);
  });

  it("ignores YAML, fences, comments, ordinary text and foreign blocks", () => {
    const text = [
      "---", `daymark-id: '${id(1)}'`, `- [ ] YAML ${id(2)}`, "---",
      "```md", `- [ ] code ${id(3)}`, "```",
      "~~~~md", `- [ ] code ${id(4)}`, "~~~", `- [ ] still code ${id(5)}`, "~~~~",
      "<!--", `- [ ] comment ${id(6)}`, "-->",
      "%%", `- [ ] comment ${id(7)}`, "%%",
      `ordinary ${id(8)}`, "- [ ] foreign ^user-id", `- [ ] real ${id(9)}`,
    ].join("\n");
    expect(scan(text).map((span) => span.id)).toEqual([id(9)]);
  });

  it("leaves malformed, multiple and unsupported identities visible", () => {
    expect(scan(`- [ ] broken ^daymark-obsidian-invalid\n- [ ] two ^other ${id(1)}\n- [?] bad ${id(2)}`)).toEqual([]);
  });

  it("changes only task identities when making a copy", () => {
    const text = `正文 [[文件#${id(1)}]]\n- [ ] 事项 ${id(1)}\n  - [ ] 子事项 ${id(2)}\n`;
    let next = 10;
    expect(freshenIdentities(text, () => id(next++))).toBe(
      `正文 [[文件#${id(1)}]]\n- [ ] 事项 ${id(10)}\n  - [ ] 子事项 ${id(11)}\n`,
    );
  });
});

describe("vault-relative folder scope", () => {
  it.each(["", "../Daymark", "Daymark/../Other", "D:\\Vault\\Daymark", "/Daymark", ".obsidian", "A//B"])("rejects %s", (folder) => {
    expect(normalizeFolder(folder)).toBeNull();
  });
  it("normalizes separators and accepts explicit vault root", () => {
    expect(normalizeFolder(" 工作\\Daymark/ ")).toBe("工作/Daymark");
    expect(normalizeFolder("/")).toBe("/");
  });
  it("protects only immediate Markdown files in the configured folder", () => {
    expect(isManagedPath("Daymark/事项.md", "Daymark")).toBe(true);
    expect(isManagedPath("Daymark/事项.MD", "Daymark")).toBe(true);
    expect(isManagedPath("Daymark/子目录/事项.md", "Daymark")).toBe(false);
    expect(isManagedPath("Other/事项.md", "Daymark")).toBe(false);
    expect(isManagedPath("Daymark/事项.txt", "Daymark")).toBe(false);
    expect(isManagedPath("事项.md", "/")).toBe(true);
    expect(isManagedPath("事项.md", "")).toBe(false);
  });
});

import { Text } from "@codemirror/state";

const idSource = String.raw`\^daymark-obsidian-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}`;
const suffix = new RegExp(`([ \\t]+)(${idSource})[ \\t]*$`);
export const taskPrefix = /^(\s*)([-+*]|\d+[.)])\s+\[([ /xX-])\]\s*/;

export interface Identity {
  readonly from: number;
  readonly to: number;
  readonly lineFrom: number;
  readonly lineTo: number;
  readonly bodyFrom: number;
  readonly id: string;
}

/** Only valid task suffixes are hidden. Malformed or ambiguous IDs stay visible. */
export function scanIdentities(doc: Text): Identity[] {
  const found: Identity[] = [];
  let yaml = doc.line(1).text.replace(/^\uFEFF/, "").trim() === "---";
  let fence: string | undefined;
  let comment: "-->" | "%%" | undefined;
  for (let n = 1; n <= doc.lines; n++) {
    const line = doc.line(n);
    const trimmed = line.text.trimStart();
    if (yaml) {
      if (n > 1 && trimmed.trim() === "---") yaml = false;
      continue;
    }
    if (comment) {
      if (trimmed.includes(comment)) comment = undefined;
      continue;
    }
    if (fence) {
      const closing = /^(`{3,}|~{3,})\s*$/.exec(trimmed)?.[1];
      if (closing && closing[0] === fence[0] && closing.length >= fence.length) {
        fence = undefined;
      }
      continue;
    }
    const opening = /^(`{3,}|~{3,})/.exec(trimmed)?.[1];
    if (opening) {
      fence = opening;
      continue;
    }
    if (trimmed.startsWith("<!--")) {
      if (!trimmed.includes("-->")) comment = "-->";
      continue;
    }
    if (trimmed.startsWith("%%")) {
      if (!trimmed.slice(2).includes("%%")) comment = "%%";
      continue;
    }
    const prefix = taskPrefix.exec(line.text);
    const match = suffix.exec(line.text);
    if (!prefix || !match) continue;
    // More than one block marker is an import error; do not conceal it.
    if (/(?:^|\s)\^[a-zA-Z0-9_.:-]+/.test(line.text.slice(0, match.index))) {
      continue;
    }
    // Keep the checkbox's own separator visible on an empty task. A generated
    // empty task has another space before its ID, ready for subsequent typing.
    const checkboxEnd = line.text.indexOf("]", prefix[1]!.length) + 1;
    const hiddenFrom = Math.max(match.index, checkboxEnd + 1);
    found.push({
      from: line.from + hiddenFrom,
      to: line.to,
      lineFrom: line.from,
      lineTo: line.to,
      bodyFrom: Math.min(line.from + prefix[0].length, line.from + hiddenFrom),
      id: match[2]!,
    });
  }
  return found;
}

export function newIdentity(): string {
  return `^daymark-obsidian-${crypto.randomUUID()}`;
}

export function freshenIdentities(text: string, nextId = newIdentity): string {
  const doc = Text.of(text.replace(/\r\n?/g, "\n").split("\n"));
  let result = doc.toString();
  const replacements = scanIdentities(doc).map((span) => ({ ...span, replacement: ` ${nextId()}` }));
  for (const span of replacements.reverse()) {
    result = result.slice(0, span.from) + span.replacement + result.slice(span.to);
  }
  return result;
}

/** Folder scope mirrors Daymark: immediate Markdown children, not descendants. */
export function normalizeFolder(input: string): string | null {
  const value = input.trim().replace(/\\/g, "/");
  if (value === "/") return "/";
  if (!value || value.startsWith("/") || value.includes(":")) return null;
  const parts = value.replace(/\/+$/, "").split("/");
  if (parts.some((part) => !part || part === "." || part === ".." || part === ".obsidian")) {
    return null;
  }
  return parts.join("/");
}

export function isManagedPath(path: string, folder: string): boolean {
  if (!normalizeFolder(folder) || !/\.md$/i.test(path)) return false;
  const parent = path.slice(0, Math.max(0, path.lastIndexOf("/")));
  return parent === (folder === "/" ? "" : folder);
}

export function indentation(line: string): number {
  let width = 0;
  for (const char of /^\s*/.exec(line)![0]) {
    width += char === "\t" ? 4 - (width % 4) : 1;
  }
  return width;
}

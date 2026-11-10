import { build } from "esbuild";
import { copyFile, mkdir } from "node:fs/promises";

// Obsidian supplies its own CodeMirror instances; bundling them breaks fields.
await build({
  entryPoints: ["src/main.ts"],
  bundle: true,
  external: ["obsidian", "@codemirror/*", "@lezer/*"],
  format: "cjs",
  target: "es2021",
  outfile: "main.js",
  logLevel: "info",
  banner: { js: "/* 由 npm run build 生成；源代码见 src/。 */" },
});

// This folder is ready to copy into a vault, without source or node_modules.
await mkdir("release/daymark-id-guard", { recursive: true });
await Promise.all([
  copyFile("main.js", "release/daymark-id-guard/main.js"),
  copyFile("manifest.json", "release/daymark-id-guard/manifest.json"),
]);

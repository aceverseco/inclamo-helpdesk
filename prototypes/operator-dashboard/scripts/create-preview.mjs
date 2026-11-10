import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";

// Produce a portable review artifact. The Vue source remains the editable source of truth.
const root = path.resolve("dist");
let html = await readFile(path.join(root, "index.html"), "utf8");
const favicon = `data:image/svg+xml;base64,${(await readFile("public/inclamo-logo.svg")).toString("base64")}`;
const script = html.match(/<script\b[^>]*src="([^"]+)"[^>]*><\/script>/);
const stylesheet = html.match(/<link\b[^>]*href="([^"]+\.css)"[^>]*>/);
if (!script || !stylesheet)
  throw new Error("Expected one bundled entry point and stylesheet.");
let js = await readFile(path.join(root, script[1].replace(/^\//, "")), "utf8");
let css = await readFile(
  path.join(root, stylesheet[1].replace(/^\//, "")),
  "utf8",
);
for (const match of [...css.matchAll(/url\(([^)]+)\)/g)]) {
  const asset = match[1].replace(/["']/g, "");
  if (!asset.startsWith("/assets/")) continue;
  const bytes = await readFile(path.join(root, asset.slice(1)));
  const mime = asset.endsWith(".woff2")
    ? "font/woff2"
    : "application/octet-stream";
  css = css.replace(
    match[0],
    `url(data:${mime};base64,${bytes.toString("base64")})`,
  );
}
js = js
  .replaceAll("/inclamo-logo.svg", favicon)
  .replaceAll("</script", "<\\/script");
html = html
  .replace(script[0], () => `<script type="module">${js}</script>`)
  .replace(stylesheet[0], () => `<style>${css}</style>`)
  .replace('href="/inclamo-logo.svg"', `href="${favicon}"`);
const notices = await Promise.all(
  ["LICENSE.shadcn-vue", "LICENSE.inter", "LICENSE.lucide"].map(
    async (name) => `${name}\n${await readFile(name, "utf8")}`,
  ),
);
html = html.replace(
  "<head>",
  `<head>\n<!-- Third-party notices:\n${notices.join("\n")}-->`,
);
await writeFile(path.join(root, "inclamo-inbox-preview.html"), html);
console.log(
  `Portable preview: dist/inclamo-inbox-preview.html (${Math.round(Buffer.byteLength(html) / 1024)} KB)`,
);

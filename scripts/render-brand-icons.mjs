// Development-only export of the original SVG; no runtime image dependency.
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(new URL('../e2e/package.json', import.meta.url));
const { chromium } = require('@playwright/test'); // npm install --prefix e2e

const root = fileURLToPath(new URL('../', import.meta.url));
const output = resolve(root, 'shims/public');
const source = await readFile(resolve(output, 'brand-assets/inclamo-mark.svg'), 'utf8');
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ deviceScaleFactor: 1 });
const pngs = new Map();

// The icons carry the names Chatwoot gives its own in public/, so its pages,
// its web manifest and its notification badge show ours without a change
// (each file is recorded in custom/CHATWOOT_FILES).
const names = [
  ...[36, 48, 72, 96, 144, 192].map(size => [`android-icon-${size}x${size}.png`, size]),
  ...[57, 60, 72, 76, 114, 120, 144, 152, 180].map(size => [`apple-icon-${size}x${size}.png`, size]),
  ['apple-icon.png', 192],
  ['apple-icon-precomposed.png', 192],
  ...[16, 32, 96, 512].map(size => [`favicon-${size}x${size}.png`, size]),
  ...[16, 32, 96].map(size => [`favicon-badge-${size}x${size}.png`, size, true]),
  ...[70, 144, 150, 310].map(size => [`ms-icon-${size}x${size}.png`, size]),
];

try {
  for (const [name, size, badge] of names) {
    const svg = badge
      ? source.replace('</svg>', '<circle cx="850" cy="174" r="145" fill="#FF6A00" stroke="#FFFFFF" stroke-width="55"/></svg>')
      : source;
    await page.setViewportSize({ width: size, height: size });
    await page.setContent(`<style>html,body{margin:0;width:100%;height:100%;overflow:hidden}svg{display:block;width:100%;height:100%}</style>${svg}`);
    const png = await page.screenshot({ type: 'png', animations: 'disabled' });
    await writeFile(resolve(output, name), png);
    if (!badge) pngs.set(size, png);
  }
} finally {
  await browser.close();
}

// ICO containers can embed PNG data directly, preserving the same exported mark.
const sizes = [16, 32];
const header = Buffer.alloc(6 + 16 * sizes.length);
header.writeUInt16LE(1, 2);
header.writeUInt16LE(sizes.length, 4);
let offset = header.length;
sizes.forEach((size, index) => {
  const entry = 6 + index * 16;
  const png = pngs.get(size);
  header[entry] = size;
  header[entry + 1] = size;
  header.writeUInt16LE(1, entry + 4);
  header.writeUInt16LE(32, entry + 6);
  header.writeUInt32LE(png.length, entry + 8);
  header.writeUInt32LE(offset, entry + 12);
  offset += png.length;
});
await writeFile(resolve(root, 'shims/public/favicon.ico'), Buffer.concat([header, ...sizes.map(size => pngs.get(size))]));
console.log(`Exported Inclamo browser icons to ${output}`);

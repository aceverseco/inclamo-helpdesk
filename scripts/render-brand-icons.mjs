// Development-only export of the original SVG; no runtime image dependency.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(new URL('../e2e/package.json', import.meta.url));
const { chromium } = require('@playwright/test'); // npm install --prefix e2e

const root = fileURLToPath(new URL('../', import.meta.url));
const output = resolve(root, 'shims/public/brand-assets');
const source = await readFile(resolve(output, 'inclamo-mark.svg'), 'utf8');
await mkdir(output, { recursive: true });
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ deviceScaleFactor: 1 });
const pngs = new Map();

try {
  for (const size of [16, 32, 96, 180, 192, 512]) {
    for (const badge of size <= 96 ? [false, true] : [false]) {
      const svg = badge
        ? source.replace('</svg>', '<circle cx="850" cy="174" r="145" fill="#FF6A00" stroke="#FFFFFF" stroke-width="55"/></svg>')
        : source;
      await page.setViewportSize({ width: size, height: size });
      await page.setContent(`<style>html,body{margin:0;width:100%;height:100%;overflow:hidden}svg{display:block;width:100%;height:100%}</style>${svg}`);
      const png = await page.screenshot({ type: 'png', animations: 'disabled' });
      const name = `favicon-${badge ? 'badge-' : ''}${size}x${size}.png`;
      await writeFile(resolve(output, name), png);
      if (!badge) pngs.set(size, png);
    }
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

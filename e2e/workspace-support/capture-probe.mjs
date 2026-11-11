import http from 'node:http';
import net from 'node:net';
import { execFileSync } from 'node:child_process';
import { chromium, firefox, webkit, request, expect } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
// Loopback is a secure browser context; upstream remains the synthetic client.
const server = http.createServer((incoming, outgoing) => {
  const upstream = http.request({ hostname: 'client', port: 3000, path: incoming.url, method: incoming.method, headers: { ...incoming.headers, host: 'client:3000' } }, response => {
    outgoing.writeHead(response.statusCode, response.headers); response.pipe(outgoing);
  });
  upstream.on('error', () => { outgoing.writeHead(502); outgoing.end(); }); incoming.pipe(upstream);
});
server.on('upgrade', (incoming, socket, head) => {
  const upstream = net.connect(3000, 'client', () => {
    const headers = Object.entries({ ...incoming.headers, host: 'client:3000' }).map(([key, value]) => `${key}: ${value}`).join('\r\n');
    upstream.write(`${incoming.method} ${incoming.url} HTTP/${incoming.httpVersion}\r\n${headers}\r\n\r\n`);
    upstream.write(head); socket.pipe(upstream); upstream.pipe(socket);
  });
  upstream.on('error', () => socket.destroy()); socket.on('error', () => upstream.destroy());
});
await new Promise(resolve => server.listen(3333, '0.0.0.0', resolve));
process.env.HELPDESK_URL = 'http://127.0.0.1:3333';
const { api, workspace, openSupport } = await import('./helpers.mjs');
const output = process.env.E2E_OUTPUT || '/out'; await mkdir(output, { recursive: true });
const apiContext = await request.newContext(); const session = await api(apiContext);
const results = [];
const cancelChooser = () => execFileSync('python3', ['-c', `import ctypes
x=ctypes.CDLL('libX11.so.6'); t=ctypes.CDLL('libXtst.so.6')
x.XOpenDisplay.restype=ctypes.c_void_p
x.XKeysymToKeycode.argtypes=[ctypes.c_void_p,ctypes.c_ulong]
x.XFlush.argtypes=[ctypes.c_void_p]
t.XTestFakeKeyEvent.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.c_int,ctypes.c_ulong]
d=x.XOpenDisplay(None); key=x.XKeysymToKeycode(d,0xff1b)
t.XTestFakeKeyEvent(d,key,1,0); t.XTestFakeKeyEvent(d,key,0,0); x.XFlush(d)
`]);

try {
  for (const [name, engine] of Object.entries({ chromium, firefox, webkit })) {
    const browser = await engine.launch({ headless: false, ...(name === 'chromium' ? { args: ['--auto-select-desktop-capture-source=Entire screen'] } : {}) });
    try {
      let page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
      const uploads = []; page.on('request', item => { if (/\/support\/uploads$/.test(item.url())) uploads.push(item.url()); });
      await page.addInitScript(() => {
        const get = navigator.mediaDevices?.getDisplayMedia?.bind(navigator.mediaDevices);
        window.captureTracks = [];
        if (get) navigator.mediaDevices.getDisplayMedia = async options => {
          try { const stream = await get(options); window.captureTracks.push(...stream.getTracks()); return stream; }
          catch (error) { window.captureError = { name: error.name, message: error.message }; throw error; }
        };
      });
      await workspace(page, session); let support = await openSupport(page);
      await support.getByTestId('support-description').fill('Capture cancellation preserves this draft');
      const available = await page.evaluate(() => ({ secure: isSecureContext, capture: Boolean(navigator.mediaDevices?.getDisplayMedia) }));
      const result = { name, version: browser.version(), ...available };
      if (name === 'chromium') {
        await page.evaluate(() => { const marker = document.createElement('div'); marker.id = 'capture-paint-marker'; marker.style.cssText = 'position:fixed;left:600px;top:300px;width:64px;height:64px;background:rgb(1,255,1);z-index:99999'; document.body.append(marker); });
        await support.getByRole('button', { name: 'Take screenshot', exact: true }).click();
        await expect(support.locator('canvas')).toBeVisible({ timeout: 30_000 });
        const green = await support.locator('canvas').evaluate(canvas => { const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data; let count = 0; for (let i = 0; i < pixels.length; i += 4) if (pixels[i] < 5 && pixels[i + 1] > 250 && pixels[i + 2] < 5) count += 1; return count; });
        await page.screenshot({ path: `${output}/capture-paint-check.png` });
        expect(green).toBeGreaterThan(1000); result.overlay_hidden = true;
        result.tracks = await page.evaluate(() => window.captureTracks.map(track => track.readyState));
        expect(result.tracks.length).toBeGreaterThan(0); expect(result.tracks.every(state => state === 'ended')).toBe(true);
        expect(uploads).toEqual([]);
        await page.screenshot({ path: `${output}/capture-chromium.png` });
        await support.getByRole('button', { name: 'Cancel', exact: true }).click();
        await expect(support.getByTestId('support-description')).toHaveValue('Capture cancellation preserves this draft');
        expect(uploads).toEqual([]); result.native_capture = 'passed'; result.editor_cancel = 'draft retained, zero uploads';
      } else {
        // Without a source choice the browser must never begin recording. Reject
        // through its own permission policy when supported; upload remains usable.
        if (available.capture) {
          await support.getByRole('button', { name: 'Take screenshot', exact: true }).click();
          await page.waitForTimeout(700);
          if (!await page.evaluate(() => window.captureError)) cancelChooser();
          try {
            await expect.poll(() => page.evaluate(() => Boolean(window.captureError)), { timeout: 10_000 }).toBe(true);
            result.native_capture = await page.evaluate(() => window.captureError);
            if (!await support.isVisible()) await openSupport(page);
            await expect(support.getByTestId('support-description')).toHaveValue('Capture cancellation preserves this draft');
          } catch (error) {
            if (name !== 'webkit') throw error;
            // Linux WebKit's native chooser does not resolve under Xvfb. Record
            // that platform limit explicitly; do not pretend this is a capture.
            expect(await page.evaluate(() => window.captureTracks.length)).toBe(0);
            expect(uploads).toEqual([]);
            result.native_capture = 'unresolved native chooser on Linux/Xvfb; no stream or upload; macOS Safari capture requires manual acceptance';
            await page.close();
            page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
            page.on('request', item => { if (/\/support\/uploads$/.test(item.url())) uploads.push(item.url()); });
            await workspace(page, session); support = await openSupport(page);
            await support.getByTestId('support-description').fill('Separate WebKit upload fallback');
          }
        } else result.native_capture = 'unavailable; upload fallback exercised';
        await support.locator('input[type=file]').setInputFiles({ name: 'notes.txt', mimeType: 'text/plain', buffer: Buffer.from('Synthetic desktop fallback') });
        await expect(support).toContainText('notes.txt'); expect(uploads).toEqual([]);
        await page.screenshot({ path: `${output}/capture-fallback-${name}.png` });
        result.upload_fallback = 'passed; zero uploads before Send';
      }
      results.push(result); console.log(JSON.stringify(result));
    } finally { await browser.close(); }
  }
  // A second real Chromium chooser is cancelled through the X11 keyboard,
  // without replacing getDisplayMedia or granting permission in script.
  const cancellation = await chromium.launch({ headless: false });
  try {
    const page = await cancellation.newPage();
    await page.addInitScript(() => { const get = navigator.mediaDevices.getDisplayMedia.bind(navigator.mediaDevices); navigator.mediaDevices.getDisplayMedia = options => get(options).catch(error => { window.captureError = { name: error.name, message: error.message }; throw error; }); });
    const uploads = []; page.on('request', item => { if (/\/support\/uploads$/.test(item.url())) uploads.push(item.url()); });
    await workspace(page, session); const support = await openSupport(page);
    await support.getByTestId('support-description').fill('Real chooser cancellation keeps this text');
    await support.getByRole('button', { name: 'Take screenshot', exact: true }).click();
    await page.waitForTimeout(700);
    cancelChooser();
    await expect.poll(() => page.evaluate(() => Boolean(window.captureError)), { timeout: 10_000 }).toBe(true);
    if (!await support.isVisible()) await openSupport(page);
    await expect(support.getByTestId('support-description')).toHaveValue('Real chooser cancellation keeps this text');
    expect(uploads).toEqual([]);
    results.push({ name: 'chromium-native-chooser-cancel', result: 'draft retained, zero uploads' });
    console.log('NATIVE_CHOOSER_CANCEL passed');
  } finally { await cancellation.close(); }
  await writeFile(`${output}/capture-results.json`, JSON.stringify(results, null, 2));
} finally { await apiContext.dispose(); server.closeAllConnections(); server.close(); }

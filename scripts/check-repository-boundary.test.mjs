import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { checkRepository } from './check-repository-boundary.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'helpdesk-boundary-'));
  execFileSync('git', ['init', '-q', root]);
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return { root, write(name, content = '') {
    const file = join(root, name);
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, content);
  } };
}

test('source, tests and self-contained documentation are publishable', t => {
  const { root, write } = fixture(t);
  write('README.md', '[Setup](docs/setup.md)');
  write('docs/setup.md', '[Source](../custom/app.rb)');
  write('custom/app.rb');
  write('e2e/tests/workflow.spec.mjs');
  assert.deepEqual(checkRepository(root), []);
});

test('ignored files cannot hide a force-added internal plan', t => {
  const { root, write } = fixture(t);
  write('.gitignore', '/openspec/\n');
  write('openspec/changes/example/tasks.md', '- [ ] Internal task');
  assert.deepEqual(checkRepository(root), []);
  execFileSync('git', ['add', '-f', 'openspec/changes/example/tasks.md'], { cwd: root });
  assert.match(checkRepository(root).join('\n'), /internal working material/);
  rmSync(join(root, 'openspec'), { recursive: true });
  assert.deepEqual(checkRepository(root), []);
});

test('untracked reports and broken or internal documentation links are refused', t => {
  const { root, write } = fixture(t);
  write('reports/acceptance.md');
  write('README.md', '[Missing](docs/missing.md)\n[Plan](openspec/changes/example/tasks.md)');
  const failures = checkRepository(root).join('\n');
  assert.match(failures, /reports\/acceptance.md: internal/);
  assert.match(failures, /missing link target/);
  assert.match(failures, /link targets internal/);
});

test('external workspace symlinks and links cannot become public dependencies', t => {
  const { root, write } = fixture(t);
  symlinkSync(tmpdir(), join(root, 'private-workspace'));
  write('README.md', '[Private](private-workspace)\n[Parent](../)');
  const failures = checkRepository(root).join('\n');
  assert.match(failures, /symlink leaves/);
  assert.match(failures, /link resolves outside/);
  assert.match(failures, /link leaves/);
});

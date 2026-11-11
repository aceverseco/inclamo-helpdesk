// Check the candidate working tree; tracked deletions are omitted and ordinary
// untracked additions are included. CI runs the same check after checkout.
import { execFileSync } from 'node:child_process';
import { lstatSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, isAbsolute, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const internal = /^(?:openspec|context|reports|strategy|projects|prototypes|\.claude|\.agents|\.codex)(?:\/|$)|^(?:STATUS\.md|CLAUDE(?:\.local)?\.md|\.mcp\.json)$|^docs\/(?:evidence(?:\/|$)|spec-plan\.md$)/;
const outside = (root, path) => {
  const rel = relative(root, path);
  return rel === '..' || rel.startsWith(`..${sep}`) || isAbsolute(rel);
};

export function checkRepository(root) {
  root = realpathSync(root);
  const names = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], { cwd: root, encoding: 'utf8' }).split('\0').filter(Boolean);
  const problems = [];
  for (const name of new Set(names)) {
    const file = resolve(root, name);
    let stat;
    try { stat = lstatSync(file); } catch (error) {
      if (error.code === 'ENOENT' || error.code === 'ENOTDIR') continue;
      throw error;
    }
    if (internal.test(name)) problems.push(`${name}: internal working material must not be published`);
    if (stat.isSymbolicLink()) {
      try {
        if (outside(root, realpathSync(file))) problems.push(`${name}: symlink leaves the public checkout`);
      } catch { problems.push(`${name}: broken symlink`); }
      continue;
    }
    if (!stat.isFile() || !/^(?:README\.md|CONTRIBUTING\.md|docs\/.*\.md)$/.test(name)) continue;
    const content = readFileSync(file, 'utf8');
    if (/\bADR\s+\d{4}\b|\/Users\/|\/home\/ubuntu\//.test(content)) {
      problems.push(`${name}: documentation refers to internal decisions or a private workspace`);
    }
    for (const match of content.matchAll(/\[[^\]]*\]\(([^\s)]+)(?:\s+"[^"]*")?\)/g)) {
      const target = match[1].replace(/^<|>$/g, '');
      if (/^(?:[a-z][a-z0-9+.-]*:|#|\/\/)/i.test(target)) continue;
      const path = resolve(dirname(file), decodeURIComponent(target.split('#')[0]));
      if (outside(root, path)) {
        problems.push(`${name}: link leaves the public checkout: ${target}`);
        continue;
      }
      const linkedName = relative(root, path).split(sep).join('/');
      if (internal.test(linkedName)) problems.push(`${name}: link targets internal material: ${target}`);
      try {
        if (outside(root, realpathSync(path))) problems.push(`${name}: link resolves outside the public checkout: ${target}`);
      } catch { problems.push(`${name}: missing link target: ${target}`); }
    }
  }
  return problems;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  const problems = checkRepository(root);
  if (problems.length) {
    console.error(problems.join('\n'));
    process.exitCode = 1;
  } else console.log('Public repository boundary and documentation links pass');
}

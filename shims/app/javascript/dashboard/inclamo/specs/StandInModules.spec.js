// The overlay's modules that stand in for Chatwoot's (custom/CHATWOOT_FILES):
// scripts/assemble.sh keeps Chatwoot's file beside each one as
// <name>.chatwoot.js. Whatever imports the module gets ours, so ours has to
// offer every name Chatwoot's does: a name left out would reach its importer
// as undefined, without an error. Read from the sources, so no module runs.
const kept = import.meta.glob(['../../../**/*.chatwoot.js', '!../../../**/*.spec.chatwoot.js'], { query: '?raw', import: 'default', eager: true });
const ours = import.meta.glob(['../../../**/*.js', '!../../../**/*.chatwoot.js', '!../../../**/*.spec.js', '!../../../**/specs/**'], { query: '?raw', import: 'default' });

const exported = source => {
  const names = [...source.matchAll(/^export (?:async )?(?:const|let|function\*?|class) (\w+)/gm)].map(match => match[1]);
  [...source.matchAll(/^export \{([^}]*)\}/gm)].forEach(match =>
    match[1].split(',').forEach(name => name.trim() && names.push(name.trim().split(/\s+as\s+/).pop()))
  );
  if (/^export default\b/m.test(source)) names.push('default');
  return names;
};

const pairs = Object.keys(kept).map(path => [path.replace(/\.chatwoot\.js$/, '.js'), path]);

describe("modules that stand in for Chatwoot's", () => {
  it('reads export lists the way the modules write them', () => {
    expect(exported("export const a = 1;\nexport async function b() {}\nexport {\n  c,\n  d as e,\n} from './x';\nexport default {};\n")).toEqual(['a', 'b', 'c', 'e', 'default']);
  });

  it('are found by the build', () => {
    expect(pairs.length).toBeGreaterThan(0);
    pairs.forEach(([path]) => expect(ours[path], path).toBeTypeOf('function'));
  });

  it.each(pairs)("%s offers every name of Chatwoot's module", async (path, original) => {
    const mine = exported(await ours[path]());

    expect(mine).toEqual(expect.arrayContaining(exported(kept[original])));
    expect(kept[original]).not.toMatch(/^export \* from/m);
  });
});

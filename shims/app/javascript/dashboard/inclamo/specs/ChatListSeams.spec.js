import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parse } from '@vue/compiler-sfc';

// ChatList.vue is Chatwoot's, changed by patches/0012-prototype-composition.patch.
// It needs the whole store and router to mount, so its seam is checked in the
// template the patches produce (the tests run from the assembled Chatwoot root).
const source = readFileSync(resolve(process.cwd(), 'app/javascript/dashboard/components/ChatList.vue'), 'utf8');
const elements = node => [node, ...(node.children || []).flatMap(elements)];
const find = tag => elements(parse(source).descriptor.template.ast).find(node => node.tag === tag);
const condition = node => node.props.find(prop => prop.name === 'if')?.exp?.content;

describe('conversation list seams', () => {
  it('offers the Mine / All / Unassigned queue only where it chooses the list', () => {
    // In a folder (a team queue included) or under advanced filters the list
    // comes from that filter, and the queue would change nothing on screen.
    expect(condition(find('ChatTypeTabs'))).toBe('!hasAppliedFiltersOrActiveFolders');
  });
});

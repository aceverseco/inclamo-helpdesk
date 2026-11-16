# How the overlay lives beside Chatwoot's files

Inclamo Helpdesk is Chatwoot Community Edition at a pinned tag plus an overlay. The overlay does not edit Chatwoot's files. Where it needs one to behave differently, it supplies its own file, and `scripts/assemble.sh` puts that in use.

## The record: `custom/CHATWOOT_FILES`

Every Chatwoot file the overlay stands in for is listed there with its blob id at the pinned tag.

| Line | Meaning |
| --- | --- |
| `<blob id> <path>` | `shims/<path>` takes the file's place. Chatwoot's own file is kept beside it, byte for byte, as `<name>.chatwoot.<ext>`. |
| `<blob id> <path> <our file>` | Chatwoot's file stays where it is. `<our file>` is used instead of it: a template found first through the overlay's view path, a component the overlay mounts itself. |

`assemble.sh` stops when:

- a recorded blob id no longer matches: Chatwoot changed the file. Read their change, carry over what our file needs, record the new id (`git rev-parse <tag>:<path>`);
- a file of `shims/` would overwrite a Chatwoot file that is not recorded.

## Kinds of stand-in

| Kind | What our file does | Examples |
| --- | --- | --- |
| Extends from outside | Imports `<name>.chatwoot` and adds to what it exports. Chatwoot's code is not copied. | routes, `useUISettings.js`, `editorHelper.js`, `tailwind.config.js` |
| Renders Chatwoot's | Renders `<name>.chatwoot.vue` unchanged, with a theme label or scope around it. | `App.vue`, `SettingsHeader.vue`, `menuItem.vue` |
| Hands over | Mounts a component of `inclamo/workspace/` wherever Chatwoot mounts its own. | `ContactPanel.vue`, `ConversationCard.vue` |
| Carried whole | Chatwoot's file with the workspace's drawing inside it. Used for screens the workspace redraws; each must be merged by hand when Chatwoot changes its file. | `Sidebar.vue`, `ChatList.vue`, `Message.vue`, `Button.vue` |
| Template | A copy under `custom/app/views/`, found before Chatwoot's. | SuperAdmin sign-in, widget page |
| Image | Ours under Chatwoot's file name. | favicons, logos |

A module that extends from outside names every export of Chatwoot's module explicitly (`export { a, b } from './x.chatwoot'`); `export *` beside an override is not used, because the test runner resolves it to Chatwoot's name. `inclamo/specs/StandInModules.spec.js` fails when a name is missing.

On the server the same is done with Ruby's own means in `custom/config/overlay.rb`: modules prepended to Chatwoot's classes, a view path, scheduled jobs.

## What is still changed inside Chatwoot's files: `patches/`

A few short insertions remain where a screen is Chatwoot's and the overlay adds a line or two inside its template: six patches, 175 changed lines in 23 files.

| Patch | What it inserts |
| --- | --- |
| `0001-macro-steps.patch` | the overlay's order steps in the macro editor and preview |
| `0002-reply-variables.patch` | the overlay's variables in the variable list |
| `0003-authorized-article-preview.patch` | article preview through an authorized link |
| `0004-theme-radius-tokens.patch` | corner radius tokens in tabs, dialogs and dropdowns |
| `0005-workspace-conversation.patch` | the thread title, conversation context and composer height |
| `0006-website-widget.patch` | page rules, starters and delivery state in the website widget |

`patches/LIMIT` holds the number of changed lines. `assemble.sh` stops when the patches change more: a change that needs more room belongs in a file of the overlay. Lower the number whenever a patch shrinks.

A patch that no longer applies to a new Chatwoot tag also stops the build.

## Choosing

1. Can the overlay add it from its own file (a route, a registry entry, a store module, a server module)? Do that; nothing of Chatwoot is involved.
2. Can our file import Chatwoot's and extend or wrap it? Stand in for it that way.
3. Is the screen redrawn by the workspace? Carry it whole and record it.
4. Is it a line or two inside a screen that stays Chatwoot's? A patch, within the limit.

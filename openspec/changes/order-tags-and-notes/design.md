## Context

See proposal.md. The order panel has an action runner (`OrderActionRunner`) that checks the role and the scope, calls the store, writes an `inclamo_order_actions` row and a private note, and drops the panel's cache. Scopes already gate actions ("write scopes decide which actions exist").

## Goals / Non-Goals

**Goals:** reuse the runner; no overwrite of tags changed elsewhere; the new scope stays optional.

**Non-Goals:** editing tags of products or draft orders; metafields; a tag dictionary.

## Decisions

**D1. Tags change one at a time.** Shopify's `tagsAdd` and `tagsRemove` take the object and the tags to add or remove, so nothing is overwritten. The same pair serves orders and customers. Alternative rejected: `orderUpdate(tags: [...])`, which replaces the whole list and loses tags added in the store meanwhile.

**D2. Notes are replaced whole**, through `orderUpdate(note)` and `customerUpdate(note)`. The dialog loads the fresh note when it opens, so the agent edits what the store holds now. Two agents editing the same note within seconds overwrite each other; that is accepted.

**D3. No confirmation step.** Tags and notes cost no money and are undone by the opposite click; the actions reuse the runner without the dialog's confirm stage. The record is written the same way.

**D4. The record names the change, not the content of a note.** The private note says "changed the note of #1042"; the text of a store note may hold a phone number or an address, and private notes travel to webhooks and exports.

**D5. Scope gating.** `write_customers` joins the optional scopes: the connection reports it, the panel receives `can.customer_marks`, and the guide lists it. The documents are validated against the pinned schema; the scope each mutation needs is confirmed on the test store in task 1.1.

## Risks / Trade-offs

- [`write_customers` is a wide permission for a narrow use] → optional; the guide says what it is used for; nothing else in the code uses it.
- [A tag longer than the store allows] → the store's refusal is shown as is.

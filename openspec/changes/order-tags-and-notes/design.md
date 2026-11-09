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

## Probed on the test store (2026-11-06)

A throwaway script ran each document against the development store with three
apps: the guide app (version 5, holding `write_orders` and `write_customers`),
the seeding app, and the limited app (`write_orders` without
`write_customers`, and no access to protected customer data). Output, store
domain left out:

```
bench tagsAdd order: accepted
bench tagsRemove order: accepted
bench orderUpdate note: accepted
order after: tags=address-confirmed,e2e,e2e-probe…,fraud-check,gift note="Customer asked for delivery after 6 pm"
bench tagsAdd customer: accepted
bench tagsRemove customer: accepted
bench customerUpdate note: accepted
customer after: tags=e2e,e2e-probe…,VIP note="Prefers phone calls"
bench tagsAdd order, 300-char tag: userErrors: Order tags is invalid
bench tagsAdd order, empty tag: accepted
bench tagsAdd unknown order: userErrors: Order does not exist
bench orderUpdate note, 6000 chars: userErrors: Note is too long (maximum is 5000 characters)
bench customerUpdate note, 6000 chars: userErrors: Note is too long (maximum is 5000 characters)
limited tagsAdd customer: refused: ACCESS_DENIED Access denied for tagsAdd field.
limited tagsRemove customer: refused: ACCESS_DENIED Access denied for tagsRemove field.
limited customerUpdate note: refused: ACCESS_DENIED Access denied for customerUpdate field. Required access: `write_customers` access scope.
limited tagsAdd order: refused: ACCESS_DENIED This app is not approved to access the Order object.
limited orderUpdate note: refused: ACCESS_DENIED This app is not approved to access the Order object.
```

What follows from it:

- D1 holds: "fraud-check", added by another app between the read and the
  change, stayed on the order.
- Customer tags and the customer note need `write_customers`; an app with
  `write_orders` alone is refused at the field, before any customer is read.
- Order tags and the order note work with `write_orders`. Their refusal
  without it was not seen live: every app on the test store that may read
  orders holds `write_orders`, and the limited app is refused the order object
  first. The server refuses them without calling the store when the scope is
  missing (task 2.1).
- The store matches a customer tag to an existing tag of the store regardless
  of case: "vip" was saved as "VIP" because the store already had "VIP". The
  panel shows what the store answers; tests compare tags without case.
- An empty tag is accepted and changes nothing, so the panel refuses an empty
  tag before calling the store. A note longer than 5000 characters and a tag
  longer than the store allows are refused by the store with the reasons above.

Fixtures recorded from this run (`custom/spec/fixtures/shopify`):
`customer_orders_marks`, `order_marks`, `customer_marks`, `tags_add_order`,
`tags_remove_order`, `order_note_update`, `tags_add_customer`,
`tags_remove_customer`, `customer_note_update`, `tags_add_refused`,
`tags_add_customer_without_scope`, `customer_note_update_without_scope`. The
older `customer_orders*` fixtures were recorded before `tags` and `note` were
read on the customer and stay as they are: a customer without those keys reads
as no tags and no note.

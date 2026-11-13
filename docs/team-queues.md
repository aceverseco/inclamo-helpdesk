# Team queues and ready replies

Team queues are the account's shared conversation queues: one definition per
account, shown to every staff member in the workspace navigation under "All",
"Assigned to me" and "Unassigned", each with the number of conversations it
holds for that person. Behavior is specified in
[team-queues](behavior/team-queues/spec.md) and
[ready-replies](behavior/ready-replies/spec.md).

## What an account gets

Eight ready queues, installed for new and existing accounts:

| Queue | Lists open conversations that… |
| --- | --- |
| Urgent | have urgent priority |
| Handed over by AI | carry one of the AI agent's hand-over labels: `inclamo_handover`, `inclamo_error`, `inclamo_limit` |
| Overdue | carry the label `sla-overdue` |
| Delivery | carry `delivery`, `inclamo_intent_delivery`, `inclamo_intent_shipping_problem` or `inclamo_intent_order_status` |
| Cancellation | carry `cancellation`, `inclamo_intent_cancellation` or `inclamo_intent_cancel_order` |
| Damage | carry `damage`, `inclamo_intent_damage`, `inclamo_intent_damaged_in_transit` or `inclamo_intent_claim` |
| Missing parts | carry `missing-parts`, `inclamo_intent_missing_parts` or `inclamo_parts_request` |
| Return | carry `return`, `inclamo_intent_return` or `inclamo_intent_exchange` |

The helpdesk keeps `sla-overdue` itself, from the SLA timers: it is added when
a target is missed and removed when that target is no longer unmet (the first
response arrived and the resolution target is not missed) or the conversation
is resolved. It is the live state; the label `sla-missed` stays as the
permanent record that a target was missed.

The label is the helpdesk's own: the SLA check also removes `sla-overdue` from an
open conversation that has no unmet target, including one a person or an
automation rule added. A store that used a label of this name for something
else should rename its own.

The plain category labels are the store's to set: by hand, in a macro, or in
an automation rule. The `inclamo_` labels are for the AI agent, which may add
only labels with that prefix ([AI connector](ai-connector.md)): an agent that
labels a conversation `inclamo_intent_return` puts it in "Return".

"Handed over by AI" lists what the AI service labelled when it handed over
(`inclamo_handover`), failed (`inclamo_error`) or reached its turn limit
(`inclamo_limit`), as the connector contract asks of it. A conversation that
reaches the team without such a label is not in this queue: one a person took
over, one handed back when the AI agent was disconnected, or one the helpdesk
handed over because the AI service did not answer at all. Those are in "All"
and "Unassigned" like any other open conversation. The labels are not removed,
so a conversation resolved and later opened again by hand is listed again.

Five ready saved replies (`delivery-status`, `cancel-confirm`, `damage-photos`,
`missing-part`, `return-start`) are ordinary saved replies using the
[order variables](order-variables.md).

Administrators manage queues at **Settings → Team queues**: rename, reorder,
hide and show, and restore a ready queue. Queues and replies are installed when
an account is created and, for existing accounts, by the upgrade's migration,
which fails loudly if an account could not be served; a job every ten minutes
completes any account that still lacks them. Installation is repeatable: it never
duplicates a queue or a reply, never changes what the store edited, and never
brings back what the store hid or deleted. If the store already used one of the
category labels for something else, the queue of that name lists those
conversations; hide the queue if that is not wanted.

A queue that is already installed keeps the labels it was installed with: a
release that changes the labels of a ready queue changes them for accounts
created afterwards. "Restore" on the queue gives an older account the current ones.

## How it is built

- A queue's conditions are stored in Chatwoot's own saved-filter format and the
  list is served by Chatwoot's own `conversations/filter` endpoint. Permissions,
  sorting, paging and live updates are Chatwoot's; the overlay has no second
  conversation finder. The count next to a queue comes from the same service,
  for the same person, so it equals the list.
- State the native filter cannot see (a target that is unmet now) is mirrored
  into the label `sla-overdue` by the SLA code of the overlay.
- A queue opens on Chatwoot's folder route under an id no native folder has
  (`custom_view/q-<id>`).

## Seam: `patches/0020-team-queues.patch`

Three hunks, each an import or a guarded expression; all logic is in
`shims/app/javascript/dashboard/inclamo/teamQueues.js`.

| File | Change | Why the existing code was not enough | Covered by |
| --- | --- | --- | --- |
| `routes/dashboard/conversation/conversation.routes.js` | `isFolderAvailable` asks the overlay about a `q-…` id before the native lookup | the guard of both folder routes refuses any id that is not a native numeric folder | `specs/teamQueues.spec.js` (guard answers), e2e "Link to a hidden queue" |
| `components/ChatList.vue` | `activeFolder` asks the overlay's resolver first; passes `folder-locked` to the header | the list finds its folder only in the per-user `customViews` store | `specs/teamQueues.spec.js` (resolver), e2e queue scenarios |
| `components/ChatListHeader.vue` | new prop `folderLocked`: no edit or delete button for a team queue | the buttons render for any folder and would edit a per-user record that does not exist | `specs/TeamQueuesNavigation.spec.js` (header), e2e "Agent cannot manage" |

`scripts/assemble.sh` stops when the patch no longer applies to the pinned
Chatwoot tag. A backend contract test runs every shipped queue through
Chatwoot's real filter service, so a renamed filter key or operator upstream
fails the build of the upgrade, not a merchant's list.

Not included: a condition editor for custom team queues, queues on live order
data, per-team queues, unread counters.

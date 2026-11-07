# SLA timers

An SLA policy says how fast conversations must get a first answer from a person
and how fast they must be resolved. Each new conversation in the inboxes a
policy covers gets a timer; agents see the time left in the conversation's
sidebar, and a conversation that misses a target is marked so that it shows up
in lists, saved views, rules and reports.

This is written in our own code. Chatwoot's paid edition has an SLA feature of
its own; it is not used, and its tables and screens stay empty.

## Policies

Policies live under **Settings → SLA**, a page only administrators see; agents
have no entry for it in the menu, and the address does not open for them.

A policy has:

- a **name**, shown to agents in the sidebar;
- a **first-response target** and a **resolution target**, in minutes, hours or
  days. One of the two may be left empty, but not both: the page refuses a
  policy without a target and says so;
- **Count business hours only**: when on, time counts only while the inbox is
  open (see below);
- the **inboxes** it covers: all of them, or chosen ones.

The policies form a list. Use the arrows to change their order: when a
conversation is created, the **first** policy in the list that covers its
inbox applies.

Below each policy is a summary for the last 7 or 30 days: how many
conversations the policy was applied to, and the share of them that met each
target. A conversation whose timer is still running counts as neither met nor
missed, so the two shares can add up to less than 100 %.

## Which conversations get a timer

Only conversations created after a policy exists, in an inbox it covers.
Conversations that were already there when the policy was created get no timer,
nor do conversations in inboxes no policy covers; their sidebar has no "SLA"
section at all.

The targets are copied into the timer when it starts. Editing a policy later
changes the targets of new conversations only. Deleting a policy stops the
timers it started on conversations that are still open: they show "Stopped" and
are never marked as missed afterwards. Results already reached (met or missed)
stay, and a target that had already passed when the policy is deleted is marked
as missed at that moment.

## When the timers stop

Both timers start when the conversation is created.

- The **first-response** timer stops at the first **public reply sent by a
  person**: an agent typing in the reply box, an agent running a macro, or a
  person answering from the channel's own app (for example WhatsApp Business).
  Private notes do not count, nor do messages sent by automation rules, bots or
  campaigns. Resolving a conversation does not stop it either.
- The **resolution** timer stops the **first** time the conversation is
  resolved. Reopening it later does not start new timers. A conversation
  Chatwoot creates already resolved (one from a blocked contact) has its
  resolution counted at once.

Replies and resolutions count from the moment they happen, even when the
helpdesk is busy and records them a little later.

A target reached in time shows as **Met**, with the time it took.

## Business hours

With **Count business hours only**, a timer advances only while the
conversation's inbox is open, as set under the inbox's **Business hours**
settings, in the inbox's time zone. Nights, weekends and closed days are
skipped, and a day the clocks change counts its real length. Outside business
hours the sidebar shows the timer as **Paused** with the time it still has. If
an inbox has no business hours switched on, its timers advance at all times.

## A missed target

When a target passes, within about a minute:

- the conversation gets the label **`sla-missed`** (created in the account the
  first time it is needed; you may change its colour);
- a private note names the policy, the target and its length, for example
  `SLA "Standard": the first-response target of 2 hours was missed.`

This happens once per target, however often the check runs. The sidebar shows
the target as **Missed** and by how much. A reply or resolution that comes
later does not undo it: the target stays missed. Nobody is emailed or
notified; build a rule on the label if you want that.

## For administrators of the installation

- The check for missed targets runs every 60 seconds. `INCLAMO_SLA_CHECK_SECONDS`
  changes the interval (the end-to-end tests use 5).
- The overlay's tables are `inclamo_sla_policies` and `inclamo_sla_timers`.
- API, for administrators: `GET/POST /api/v1/accounts/:id/inclamo/sla_policies`,
  `PATCH/DELETE .../sla_policies/:policy_id`, `POST .../sla_policies/reorder`
  (`ids` in the new order), `GET .../sla_policies/summary?days=7` (or 30).
  Targets are in seconds. For anyone who may see the conversation:
  `GET /api/v1/accounts/:id/inclamo/conversations/:display_id/sla`.

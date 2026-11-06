## Context

See proposal.md. Chatwoot v4.19.1 keeps its SLA feature behind a paid-edition flag; its server code is in `enterprise/`, which this project never uses, patches or ships. Its tables (`sla_policies`, `applied_slas`, `sla_events`) and dashboard screens exist in the open part of the tree. The release plan says paid-edition features are written by us in our code, so none of that is reused: no flag is switched, no table of theirs is written, no screen of theirs is shown.

We already have two dashboard seams that fit: sidebar sections and settings pages. The sidebar seam always draws a section's header, so it needs one addition (D8). Inboxes have business hours with a time zone in Chatwoot's open code.

## Goals / Non-Goals

**Goals:** the whole feature in `custom/` and our components; targets fixed at the moment of applying; time arithmetic in one tested place.

**Non-Goals:** a badge in the conversation list (would need a new seam; the label does that job); notifications; next-reply targets; reopened conversations.

## Decisions

**D1. Two tables.** `inclamo_sla_policies` (account, name, position, first_response_seconds, resolution_seconds, business_hours_only, all_inboxes, inbox_ids) and `inclamo_sla_timers` (conversation, policy id or null after deletion, policy name, the two targets in seconds, business_hours_only, started_at, first_response_at, resolved_at, first_response_missed_at, resolution_missed_at, stopped_at). The timer row copies the targets, so later edits of the policy do not move them.

**D2. Applying and stopping ride on Chatwoot's events.** A listener of ours on `conversation_created` applies the first covering policy; on `message_created` it stops the first-response timer when the message is outgoing, public, sent by a `User`, and not created by an automation rule or a campaign (the same markers Chatwoot's own reporting uses for "first reply"; task 1.1 lists them from the code); on `conversation_resolved` it stops the resolution timer.

The markers, read from `Message#human_response?` and `#valid_first_reply?` in v4.19.1 (task 1.1), as `Inclamo::Sla::HumanReply` checks them:
- outgoing (`message_type`) and not private;
- not a forwarded email: `content_attributes.forwarded_message_id` is empty;
- not from an automation rule: every message a rule sends or notes carries `content_attributes.automation_rule_id` (`AutomationRules::ActionService`), and its sender is empty;
- not a campaign message: `additional_attributes.campaign_id` is empty;
- the sender is a `User`, or `content_attributes.external_echo` is set: a reply a person sent from the channel's own app (WhatsApp Business, Instagram), which Chatwoot also counts as a human reply. Bots send as `AgentBot` or `Captain::Assistant`, so they never count.

A macro run by an agent sends as that agent (`Macros::ExecutionService` builds the message with the agent as sender), so it counts as the agent's reply. In Community Edition rules cannot run macros, so no rule-run macro message exists. Events are handled in the background, so applying a timer also takes a human reply that is already in the conversation; and a reply or resolution that arrives after its deadline marks the target as missed at once (D4's "once" holds: the same conditional update guards both paths).

**D3. Elapsed time is computed, not ticked.** One function gives the elapsed seconds between two moments for a timer: plain difference, or the sum of overlaps with the inbox's business hours in its time zone. The deadline is derived from it. The sidebar asks the backend for the timer and counts down locally between refreshes.

**D4. Missed targets are found by a periodic job** every minute: timers that are running and whose computed deadline has passed. It sets the `*_missed_at` field first (so it happens once), then adds the label and the private note. The interval is a setting (`INCLAMO_SLA_CHECK_SECONDS`, default 60) so the end-to-end tests can run it every few seconds.

**D5. Targets are stored in seconds; the page offers minutes, hours, days.** The API accepts seconds, which lets the end-to-end tests create a policy with a ten-second target for the "missed" scenarios without waiting minutes.

**D6. The label `sla-missed` is created on first use.** A label is what Chatwoot's list, saved views, rules and label report already understand.

**D7. Summary** is a grouped query over `inclamo_sla_timers` for the period; no stored aggregates.

**D8. The sidebar seam can hide a section.** Patch 0001 drew every registered section with its header, so a conversation without a timer would still show "SLA". The registry entry gets an optional `visible(conversationId)`; ContactPanel leaves the section out while it returns false (five lines in the existing patch, no new patch; chosen by the founder on 2026-11-06 over keeping the header with a "no policy" line). Our `visible` reads a small shared store of timers per conversation (`slaTimers.js`): the first question starts a read, an answer older than a minute is read again, and the section itself reads through the same store, so the two never disagree.

## Risks / Trade-offs

- [No timer in the conversation list] → agents see missed ones by label; a list badge is a later change with its own seam.
- [Business-hours arithmetic across days and time zones is error-prone] → one function, specs for overnight gaps, weekends, a closed day and a daylight-saving change.
- [The periodic job on a large account] → one indexed query per run on running timers only.
- [Our table names sit next to Chatwoot's own `sla_*` tables] → ours are prefixed `inclamo_`; theirs stay empty.

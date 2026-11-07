## Why

The AI service answers the store's phone. Today its calls reach a helpdesk only as Gorgias tickets; in this helpdesk they reach nobody. ADR 0068 joins the AI service and the helpdesk through Chatwoot's agent bot and says where a call goes: after it ends, as a conversation in an API inbox "Phone", on the same contact as the shopper's chats, its turns as messages ("a call is a chat"). This change is the helpdesk side of that: what a filed call looks like to the team and what the helpdesk accepts from the AI service. It is slice 8 of `docs/spec-plan.md` without the telephony, which stays in the AI service.

## What Changes

- **A call becomes one conversation in the Phone inbox.** The AI service files a finished call with one request; the helpdesk finds or creates the caller's contact, creates the conversation, writes the caller's turns as incoming messages and the agent's as outgoing ones, adds the call's record (outcome, summary, requests) as a private note, and sets labels, status and priority.
- **The caller lands on the same contact as their chats**: by phone number, then by the email the AI service sends, otherwise a new contact. A contact that cannot be told apart from another is never picked at random, and a found contact is never changed.
- **One call, one conversation.** The call's id is the key: a repeat of the same call returns the conversation filed first and adds nothing.
- **A call card in the conversation sidebar**, our component next to the order panel: entry (inbound, outbound, storefront call button), the shop's line, the caller's number, duration, when it ended, the outcome, how the contact was found, and the recording link when the AI service sends one. It shows on call conversations only.
- **Nothing reaches the caller and no agent wakes.** Filing a call sends no message, email or webhook to the caller; the agent bot gets no event for the filed turns; a teammate is notified about the call, not about every turn.
- **No payment card number is stored**, even when one slipped through the AI service's own masking.
- The part of the connector contract for calls, written down for the AI service's side in `docs/ai-connector-calls.md` (linked from `docs/ai-connector.md` of `ai-agent-connection`).

Not in this change: telephony, recordings (stored by the AI service; the helpdesk keeps a link), the AI service's code that files calls, calls in another helpdesk, a live view of a call while it runs, outbound calling from the helpdesk.

## Capabilities

### New Capabilities
- `call-conversations`: how a finished call is filed in the helpdesk, who may file it, on which contact it lands, what the conversation, its messages, labels, status, priority and card hold, what is refused, and what the filing must not do.

### Modified Capabilities
- none.

## Assumptions for the founder

1. **A call is filed by one request to an endpoint of ours** (`POST /api/v1/accounts/:account_id/inclamo/calls` in the overlay), authenticated by the connection's agent bot token. The chat path stays stock Chatwoot as ADR 0068 says. For calls this narrows ADR 0068's consequence "the portal's adapter speaks stock Chatwoot only": a Chatwoot without our overlay would need a second, stock path on the AI service's side, not built. The reason, verified in Chatwoot 4.19.1: a bot token may not read or create contacts, and a call of sixty turns would be more than sixty requests with no key to find the call again (design D1).
2. **The contact rule:** exactly one contact with the caller's number; otherwise exactly one with the email the AI service sends; otherwise a new contact of ours. Two or more contacts with the number: none is picked, a new contact gets `inclamo_match_ambiguous`. No number and no email: a nameless contact with `inclamo_no_caller_id`. A found contact's name, email and phone are never changed.
3. **Turns are messages**, the caller's incoming and the agent's outgoing from the AI agent, dated by the call; the record is a private note written last, so the conversation list shows the outcome first.
4. **The card's fields are conversation custom attributes** (`inclamo_call_*`), defined in the account by this change when the AI agent is connected, as one more step it adds to the connection of `ai-agent-connection`. Chatwoot's own "Conversation attributes" section then shows them too, and conversation filters and automation rules can use them.
5. **The AI service decides labels, status and priority; the helpdesk applies them.** Only `inclamo_*` labels are accepted; one the account does not list yet is added to the list on first use. Priority uses Chatwoot's four levels, and the contract asks for `urgent` (Chatwoot's highest, above `high`) on an urgent request.
6. **The Phone inbox has no agent bot and no webhook URL**, so a filed call wakes no bot and sends nothing out. Its auto-assignment follows the merchant's setting of that inbox and runs once, after the turns are in.
7. **Card numbers:** any run of 13 to 19 digits that passes the Luhn check, in a turn or the record, is stored as `[card number removed]`.
8. **The first filing wins:** a repeat with the same call id changes nothing, even when its content differs.
9. **Turns are written as records, without Chatwoot's per-message events**, so a call gives no notification, send job, reopening or rule run per turn. What it gives up: the merchant's webhooks and automation rules see the call's conversation and its record note, not each turn (design D5).

## Impact

- Backend (overlay): the calls endpoint, the contact rule, a table keyed by account and call id, the masking, request and model specs.
- Dashboard: the call card registered in seam 1 (the conversation sidebar sections), with its visibility hook; no new seam. Strings, component tests.
- Chatwoot: no core change. Our controller skips Chatwoot's list of endpoints open to bots and checks the token itself (design D2).
- The AI service: one request per call against the contract in `docs/ai-connector-calls.md`, instead of its Gorgias sink's sequence.
- Depends on `ai-agent-connection`: the connection record, the agent bot and its token, the Phone inbox, and the labels; this change adds the attribute definitions to its connection step.
- Tests: backend specs; end-to-end tests where a stand-in agent files calls and the dashboard is read, on the stand.

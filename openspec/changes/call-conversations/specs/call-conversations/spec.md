## Purpose

How a finished call of the AI phone agent becomes a conversation in the helpdesk: who may file it, on which contact it lands, what the conversation, its messages, labels, status, priority and call card hold, what the helpdesk refuses, and what filing a call must never do.

## ADDED Requirements

### Requirement: A finished call becomes one conversation in the Phone inbox
When the AI service files a finished call, the helpdesk SHALL create one conversation in the account's Phone inbox, on the caller's contact. The caller's turns SHALL be incoming messages and the agent's turns outgoing messages sent by the AI agent, in the order of the call and dated by the call's own times when the AI service gives them. The call's record (its outcome line, summary and requests for the team) SHALL be a private note written after the turns. The conversation SHALL hold the call's entry, line, caller number, duration, end time, outcome and, when sent, recording link as its attributes. A call the AI service files without turns (the caller said nothing) SHALL become a conversation with the record alone.

#### Scenario: A resolved inbound call
- **WHEN** the AI service files an inbound call to the shop's line from +1 555 010 0001 with eight turns and the outcome "resolved"
- **THEN** the Phone inbox has one new conversation on the caller's contact with four incoming and four outgoing messages in the call's order, a private note starting with "Resolved by the agent" after them, and the call's attributes

#### Scenario: A call where the caller said nothing
- **WHEN** the AI service files a call with no turns and the outcome "no conversation"
- **THEN** the conversation holds the private note and no other message

#### Scenario: Turns keep the call's times
- **WHEN** the AI service files a call whose turns carry the times they were spoken
- **THEN** each message of the conversation is shown with the time of its turn, not the time of the filing

### Requirement: Only the connected AI agent may file a call
A call SHALL be filed only with the access token of the agent bot of the account's AI agent connection. A request with no token, with a user's token, or with the token of another agent bot SHALL be refused as unauthorised and SHALL file nothing. While the account has no connection, or its connection is switched off, a filing SHALL be refused with the code `not_connected` and SHALL file nothing.

#### Scenario: The connection's agent files a call
- **WHEN** the AI service files a call with the token of the connection's agent bot
- **THEN** the call is filed

#### Scenario: An administrator's token
- **WHEN** a request to file a call carries the access token of an administrator of the account
- **THEN** it is refused as unauthorised and no conversation is created

#### Scenario: Another agent bot
- **WHEN** a request to file a call carries the token of an agent bot that is not the connection's
- **THEN** it is refused as unauthorised and no conversation is created

#### Scenario: The AI agent was disconnected
- **WHEN** the AI service files a call after an administrator disconnected the AI agent
- **THEN** the request is refused with `not_connected` and no conversation is created

### Requirement: The call lands on the caller's contact
The helpdesk SHALL choose the call's contact by this rule, first match wins: the one contact of the account whose phone number is the caller's number; the one contact whose email is the email the AI service sent for the caller; otherwise a new contact with the caller's number, the email when sent, and the caller's name or "Unknown caller" ("Website visitor" for a call from the storefront button). When two or more contacts have the caller's number, or two or more have the sent email, none of them SHALL be chosen: the call SHALL get a new contact and the label `inclamo_match_ambiguous`. A call with neither a number nor an email SHALL get a new nameless contact and the label `inclamo_no_caller_id`. The name, email and phone number of a contact that already existed SHALL NOT be changed by a call.

#### Scenario: The caller chatted before
- **WHEN** a contact with email anna@example.com has a website chat, and the AI service files a call from a number no contact has, sending anna@example.com as the caller's email
- **THEN** the call's conversation is on that contact, and the contact's page lists both the chat and the call

#### Scenario: The number is known
- **WHEN** exactly one contact has the number +1 555 010 0002 and a call comes from that number
- **THEN** the call's conversation is on that contact and the contact's fields are as they were

#### Scenario: Two contacts share the number
- **WHEN** two contacts have the number +1 555 010 0003 and a call comes from that number
- **THEN** the call's conversation is on a new contact, it has the label `inclamo_match_ambiguous`, and neither of the two contacts is changed

#### Scenario: No caller id
- **WHEN** the AI service files a call without a number and without an email
- **THEN** the call's conversation is on a new nameless contact and has the label `inclamo_no_caller_id`

#### Scenario: A new caller
- **WHEN** the AI service files a call from +1 555 010 0004 named "Ben" that no contact matches
- **THEN** a new contact "Ben" with that number holds the call's conversation

### Requirement: One call gives one conversation
The call's id SHALL be its key in the account. Filing a call whose id was filed before SHALL create nothing, change nothing, and answer with the conversation filed first, marked as found. Two filings of the same call arriving at the same time SHALL still give one conversation.

#### Scenario: The AI service files the same call again
- **WHEN** the AI service files call `c-17` a second time after a timeout on its side
- **THEN** the answer names the conversation of the first filing as found, and that conversation has the same messages as before

#### Scenario: Two filings at once
- **WHEN** two filings of call `c-18` arrive at the same moment
- **THEN** the account has one conversation for `c-18`

### Requirement: Status, priority and labels follow the call
The conversation SHALL be open when the AI service marks the call as needing the team, and resolved otherwise. Its priority SHALL be the one the AI service sends (none, low, medium, high or urgent). It SHALL carry the labels the AI service sends; every label SHALL start with `inclamo_`, and a filing with any other label SHALL be refused with the code `invalid_label` and file nothing. A label the account does not list yet SHALL be added to the account's labels on first use.

#### Scenario: A request for the team
- **WHEN** the AI service files a call with a request for the team, marked as needing the team, with labels `inclamo_call`, `inclamo_inbound`, `inclamo_handover` and `inclamo_escalation`
- **THEN** the conversation is open and carries those four labels

#### Scenario: An urgent request
- **WHEN** the AI service files a call with an urgent request and priority `urgent`
- **THEN** the conversation is open with priority urgent

#### Scenario: A resolved call
- **WHEN** the AI service files a call not marked as needing the team, with the label `inclamo_resolved`
- **THEN** the conversation is resolved and carries `inclamo_resolved`

#### Scenario: A label of someone else's
- **WHEN** a filing carries the label `vip`
- **THEN** it is refused with `invalid_label` and no conversation is created

### Requirement: The call card shows the call
The conversation sidebar SHALL show a call card on conversations filed as calls, and SHALL NOT show it on any other conversation. The card SHALL show the entry (a call to the shop's number, a call the agent made, or a call from the storefront button), the shop's line, the caller's number or that there was none, the duration, when the call ended, the outcome in words, how the contact was found (by number, by email, new contact, nameless, or not told apart from another), and, when the AI service sent one, a link to the recording that opens in a new tab.

#### Scenario: The card of a call
- **WHEN** an agent opens the conversation of a 3 minute 12 second inbound call that needed the team, matched by number, with a recording link
- **THEN** the sidebar shows a call card with "Call to the shop's number", the line, the caller's number, "3 min 12 s", the end time, "Request for the team", "Found by number" and a recording link

#### Scenario: A chat has no card
- **WHEN** an agent opens a website chat conversation
- **THEN** the sidebar shows no call card

### Requirement: Filing a call reaches nobody outside and wakes no agent
Filing a call SHALL NOT send any message, email or webhook to the caller, and the agent bot SHALL NOT receive an event for the messages a filing writes. A teammate SHALL NOT be notified once for each turn: a filed call SHALL give the notifications a new conversation and its assignment give, as a chat does, and none for its messages.

#### Scenario: The agent's turns stay records
- **WHEN** a call with outgoing agent turns is filed for a contact who has an email
- **THEN** no email and no message is sent to that contact

#### Scenario: The agent bot stays quiet
- **WHEN** a call with twenty turns is filed
- **THEN** the AI service's webhook receives no event for those twenty messages

#### Scenario: No notification for each turn
- **WHEN** a call with forty turns, needing the team, is filed and the Phone inbox assigns it to an agent
- **THEN** that agent has the assignment notification and no notification for any of the forty messages

### Requirement: No payment card number is stored
Before a turn or a record is stored, every run of 13 to 19 digits, with or without spaces or dashes between them, that passes the Luhn check SHALL be replaced with `[card number removed]`.

#### Scenario: A card number in a turn
- **WHEN** the caller's turn reads "my card is 4111 1111 1111 1111"
- **THEN** the stored message reads "my card is [card number removed]"

#### Scenario: An order number stays
- **WHEN** a turn reads "order 1001234567890" and those digits fail the Luhn check
- **THEN** the turn is stored as it was sent

### Requirement: A filing too large is refused whole
A filing with more than 500 turns, a turn longer than 10,000 characters, or a record longer than 8,000 characters SHALL be refused with the code `too_large` and SHALL file nothing, so the AI service can file the call again in its short form.

#### Scenario: A very long call
- **WHEN** the AI service files a call with 600 turns
- **THEN** it is refused with `too_large` and no conversation is created

### Requirement: The answer of a filing tells the AI service what was done
A successful filing SHALL answer with the conversation's number, the contact's id, whether the call was found from an earlier filing, how the contact was found (`phone`, `email`, `created`, `anonymous` or `ambiguous`), and the labels added to the account's list by this filing. A refusal SHALL answer with one of the codes of this capability (`not_connected`, `invalid_label`, `too_large`, `invalid_call`) and SHALL NOT echo the call's content.

#### Scenario: The answer of a new call
- **WHEN** a new call matched by number is filed
- **THEN** the answer names the new conversation's number, the contact's id, "found: false" and "matched by: phone"

#### Scenario: A filing without a call id
- **WHEN** a filing carries no call id
- **THEN** it is refused with `invalid_call` and no conversation is created

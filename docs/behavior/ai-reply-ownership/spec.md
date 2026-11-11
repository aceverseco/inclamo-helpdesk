# ai-reply-ownership

Behavior contract for this source revision.

### Requirement: The agent's protected reply is posted only while the conversation is the agent's
The helpdesk SHALL offer the connected AI agent a reply call, with the bot's token, for conversations of the connected inboxes. The call SHALL post the text as the agent's public reply when the conversation is Pending at the moment of posting. When the conversation is not Pending (a person took it or replied publicly, the agent or a person handed it over, or it was resolved), the call SHALL post nothing and SHALL answer `409` with `error` `conversation_not_pending`. Checking the conversation and posting the reply SHALL be one step: a take-over SHALL NOT be able to fall between them. A reply posted this way SHALL look and behave for the shopper and the team exactly like a reply posted through the native message call. The same token rules as the agent's other calls SHALL apply: another token is `401`, a conversation outside the connected inboxes or one that does not exist is `403` with nothing about it in the answer.

#### Scenario: Agent replies in a Pending conversation

- **WHEN** the agent sends its reply through the protected call while the conversation is Pending
- **THEN** the shopper sees the reply in the widget, the team sees it as the agent's message, and the answer is `201` with the message's id

#### Scenario: A person took the conversation before the reply

- **WHEN** a team member is assigned to a Pending conversation (for example with "Take over") and the agent's reply arrives through the protected call afterwards
- **THEN** nothing is posted, the answer is `409` with `error` `conversation_not_pending`, and the conversation stays the team member's

#### Scenario: A person replied before the agent

- **WHEN** a team member replies publicly in a Pending conversation and the agent's reply arrives through the protected call afterwards
- **THEN** nothing is posted and the answer is `409` with `error` `conversation_not_pending`

#### Scenario: Take-over and reply at the same moment

- **WHEN** a team member's assignment or public reply and the agent's protected reply reach the helpdesk at the same time
- **THEN** either the agent's reply is posted and the take-over happens after it, or the take-over happens and the reply is refused with `409`; a reply never appears after the take-over

#### Scenario: Empty reply

- **WHEN** the agent sends the protected call without text
- **THEN** the answer is `422` with `error` `empty_reply` and nothing is posted

#### Scenario: Another token

- **WHEN** the protected call is made with a person's token or the token of a disconnected account
- **THEN** the answer is `401` and nothing is posted

### Requirement: A person's take-over is effective at once
A Pending conversation of a connected inbox SHALL become Open in the same moment a team member replies publicly in it or is assigned to it, not later. The AI service SHALL still receive that the conversation's status changed. A private note of the team SHALL NOT change its status. A conversation outside the connected inboxes SHALL NOT be changed.

#### Scenario: Status right after the take-over

- **WHEN** a team member is assigned to a Pending conversation of a connected inbox and its status is read immediately afterwards
- **THEN** the conversation is Open and the AI service receives `conversation_status_changed`

#### Scenario: Private note

- **WHEN** a team member leaves a private note in a Pending conversation
- **THEN** the conversation stays Pending and the agent's protected reply is still posted

### Requirement: The contract states the protected reply and its refusal
The AI connector document SHALL describe the protected reply call, its answers and that `409 conversation_not_pending` means the agent's turn did not happen and is not retried. It SHALL state that the native message call stays available and is not protected against a take-over. The addition SHALL NOT change the contract number, because no existing field or call changes.

#### Scenario: An AI service written against the document

- **WHEN** an AI service follows the document and its reply is refused with `409 conversation_not_pending`
- **THEN** it does not retry the reply, does not hand the conversation over again, and stops acting on that turn

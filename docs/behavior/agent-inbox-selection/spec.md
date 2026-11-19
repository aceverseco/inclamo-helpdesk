# agent-inbox-selection

Behavior contract for this source revision.

While an account is connected to the AI agent, an administrator changes on the
"AI agent" page which inboxes the agent answers in, without disconnecting. The
helpdesk tells the AI service the whole new list first and changes nothing of
its own unless the AI service accepts it. The call is §1.4 of
`docs/ai-connector.md`; the address the page uses is
`PATCH /api/v1/accounts/{account_id}/inclamo/ai/connection` with
`{ "inbox_ids": [...] }`, the whole list after the change. The inboxes the agent
answers in are the chosen ones that still carry the agent's bot: an inbox the
team deletes, or gives another bot in Chatwoot's own inbox settings, stops
being the agent's at once.

### Requirement: An administrator changes the agent's inboxes on the AI agent page

While the account is connected to the AI agent, the "AI agent" page SHALL show every inbox of the account except the "Phone" inbox, mark the ones the agent answers in, and let an administrator save a new choice without disconnecting. After a saved change the agent's bot, its credentials, the "Phone" inbox, the labels and the delivery times SHALL be the same as before it. Only an administrator SHALL be able to change the choice. This SHALL work the same for a connection made with a code and for one made by the store app, on every installation.

#### Scenario: An inbox is added to a connection made with a code

- **WHEN** an administrator of an account connected with a code ticks the email inbox on the "AI agent" page and saves
- **THEN** the page shows the email inbox among the agent's inboxes, the account is still connected, and the time of connection has not changed

#### Scenario: An inbox is added to a connection made by the store app

- **WHEN** an administrator of an account the store app connected ticks one more inbox and saves
- **THEN** the page shows both inboxes and still says the connection was made by the store app

#### Scenario: An agent of the team tries to change the inboxes

- **WHEN** a user who is not an administrator sends a change of the agent's inboxes
- **THEN** it is refused and the agent's inboxes are unchanged

#### Scenario: The account is not connected

- **WHEN** a change of the agent's inboxes is sent for an account that is not connected
- **THEN** it is refused as not connected and nothing is created

### Requirement: The agent answers first in an added inbox from the moment it is added

After an inbox is added, a new conversation in it SHALL be held for the agent exactly as in an inbox chosen at connection, and the agent SHALL be able to read and answer it. Conversations that existed in the inbox before it was added SHALL keep their status and their assignee.

#### Scenario: A shopper writes after the inbox was added

- **WHEN** an inbox is added and then a shopper starts a conversation in it
- **THEN** the conversation is Pending, the AI service receives the message, and the agent's reply appears in the conversation

#### Scenario: A conversation that was open before

- **WHEN** an inbox with an open conversation assigned to a person is added
- **THEN** that conversation is still open and assigned to the same person

### Requirement: Removing an inbox gives its conversations to the team

When an inbox is removed from the agent's inboxes, every conversation of that inbox the agent holds SHALL go to the team as on a handover, and from that moment new conversations of that inbox SHALL go to the team. The agent SHALL NOT be able to read, answer or act on conversations of an inbox that was removed. Conversations of the inboxes that stay SHALL NOT be touched. Before saving a change that removes an inbox, the page SHALL say how many conversations will go to the team.

#### Scenario: The agent holds two conversations in the removed inbox

- **WHEN** the agent holds two pending conversations in the storefront inbox and one in the email inbox, and an administrator removes the storefront inbox
- **THEN** the two storefront conversations are open for the team, the email conversation is still held for the agent, and a new storefront conversation goes to the team

#### Scenario: The agent asks for a conversation of a removed inbox

- **WHEN** the agent asks for the messages of a conversation in an inbox that was removed
- **THEN** the helpdesk refuses and gives nothing

#### Scenario: The page warns before removing

- **WHEN** an administrator unticks an inbox in which the agent holds two conversations
- **THEN** the page says two conversations will go to the team before the change is saved

### Requirement: The agent may be left with no chat inbox

An administrator SHALL be able to remove every chat inbox from a connected agent. The account SHALL stay connected, finished calls SHALL still be filed in the "Phone" inbox, and no conversation of any inbox SHALL be held for the agent. An inbox SHALL be addable again later.

#### Scenario: The only inbox is removed

- **WHEN** an administrator removes the storefront inbox, the agent's only chat inbox
- **THEN** the page shows the account as connected with no chat inbox, a finished call is filed in "Phone", and a shopper's new message goes to the team

### Requirement: Only an inbox the agent can take is added

An inbox SHALL be addable only when it belongs to the account, is not the "Phone" inbox and has no other bot or Dialogflow. A change that names any other inbox SHALL be refused whole, with the reason, and SHALL change nothing, including the other inboxes of the same change. On the page such an inbox SHALL be shown and SHALL NOT be tickable.

#### Scenario: An inbox that has another bot

- **WHEN** a change names the email inbox, which has another bot, together with a valid inbox
- **THEN** the change is refused as naming an inbox with another bot, and neither inbox is added

#### Scenario: The Phone inbox

- **WHEN** a change names the "Phone" inbox
- **THEN** the change is refused and the agent's inboxes are unchanged

#### Scenario: A storefront inbox made again and ticked by hand

- **WHEN** the team deleted the storefront inbox, a new one was made while the agent was not connected, the agent was connected by code later, and an administrator ticks the new one and saves
- **THEN** the agent answers first in the new storefront inbox

### Requirement: A storefront inbox made again gets the agent by itself

When the store's storefront inbox is made again after a deletion and the account's agent is connected, the helpdesk SHALL add the new inbox to the agent's inboxes at that moment, by the same change an administrator's tick makes and under the same rule that the AI service agrees first. When the AI service refuses, does not answer or does not know the call, the new inbox SHALL stay with the team, making the inbox SHALL still succeed, and the "AI agent" page SHALL say that the agent could not be added to it. An administrator SHALL be able to remove the agent from that inbox on the page like from any other. No other new inbox SHALL get the agent by itself.

#### Scenario: Made again while the agent is connected

- **WHEN** the team deleted the storefront inbox, the agent is connected, and the store app asks for the storefront inbox again
- **THEN** a new storefront inbox exists, the agent answers first in it, and the AI service was told the new list once

#### Scenario: The AI service does not accept

- **WHEN** the storefront inbox is made again and the AI service refuses the new list
- **THEN** the new inbox exists and is answered by the team, and the "AI agent" page says the agent could not be added to it

#### Scenario: Another new inbox

- **WHEN** an administrator creates an email inbox while the agent is connected
- **THEN** the agent does not answer in it until an administrator ticks it

### Requirement: The AI service agrees to the new list before anything changes

The helpdesk SHALL tell the AI service the whole new list before changing anything of its own, and SHALL change the agent's inboxes only when the AI service accepts. When the AI service refuses, does not answer or does not know the call, nothing SHALL change: the agent answers in the same inboxes as before, no conversation is handed to the team, and the administrator SHALL be told which of the three happened, with the AI service's own message when it gave one. A change that names the list the agent already has SHALL succeed without asking the AI service.

#### Scenario: The AI service refuses

- **WHEN** an administrator saves a change and the AI service refuses it with a message
- **THEN** the page shows that message, the agent's inboxes are unchanged, and the agent's pending conversations are still held for it

#### Scenario: The AI service does not answer

- **WHEN** an administrator saves a change and the AI service does not answer in time
- **THEN** the page says the AI service did not answer and the agent's inboxes are unchanged

#### Scenario: The AI service does not know the call

- **WHEN** an administrator saves a change and the AI service answers that it has no such call
- **THEN** the page says this AI service cannot change inboxes and that reconnecting is the way, and the agent's inboxes are unchanged

#### Scenario: The same list is saved again

- **WHEN** an administrator saves the list the agent already has
- **THEN** the change succeeds and the AI service is not asked

### Requirement: A change is never left half done

Two changes of the same account, or a change and a connection or disconnection, SHALL NOT run at once: the second SHALL be refused as busy. When the AI service accepted a list and the helpdesk then could not apply it, the helpdesk SHALL keep its earlier inboxes whole, SHALL ask the AI service to take the earlier list back, and SHALL show on the "AI agent" page that the last change was not completed until a later change succeeds.

#### Scenario: Two administrators save at the same moment

- **WHEN** two changes for the same account arrive together
- **THEN** one is applied and the other is refused as busy, and the agent's inboxes are the first one's choice

#### Scenario: The helpdesk fails after the AI service accepted

- **WHEN** the AI service accepts a change and the helpdesk cannot apply it
- **THEN** the agent's inboxes in the helpdesk are the earlier ones, the AI service was asked to take the earlier list back, and the page says the last change was not completed

### Requirement: The store app sees the agent's inboxes as they are

For an account the store app provisioned, the status of the agent's connection the app reads SHALL list the inboxes the agent answers in after a change made on the "AI agent" page. The app SHALL NOT be able to change them.

#### Scenario: The app asks after a change on the page

- **WHEN** an administrator adds the email inbox on the page and the app then asks how the connection is doing
- **THEN** the answer lists the storefront inbox and the email inbox

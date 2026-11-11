# ai-agent-connection

Behavior contract for this source revision.

### Requirement: The AI agent page is the door to the agent

Account settings SHALL have an "AI agent" page, shown to administrators only. Without a connection it SHALL say what the agent does and how to get it, and SHALL offer a field for a connection code and a choice of inboxes. While an account is not connected, no agent bot of ours SHALL exist in it, and no conversation SHALL be held for the agent.

#### Scenario: Administrator opens the page without a connection

- **WHEN** an administrator of an account that was never connected opens "AI agent"
- **THEN** the page describes the agent, links to where it is obtained, and offers the code field and the inboxes of the account; the account has no agent bot

#### Scenario: Agents do not see the page

- **WHEN** a user with the agent role opens the account settings
- **THEN** there is no "AI agent" page in the list, and its address answers that the user is not allowed

### Requirement: An administrator connects the account with a code

Connecting SHALL take a connection code issued by the AI service and at least one inbox. A code that does not read, or that names an address other than HTTPS, SHALL be refused before any request is made. The helpdesk SHALL register with the AI service the account, the agent's credentials and the chosen inboxes. Only after the AI service accepts SHALL the chosen inboxes be handed to the agent, the "Phone" inbox exist, and the agent's labels exist in the account. When the AI service refuses or does not answer, the page SHALL show its reason or "the AI service did not answer", and the account SHALL be as it was before.

#### Scenario: Administrator connects a website inbox

- **WHEN** an administrator enters a valid code, picks the website inbox and presses "Connect"
- **THEN** the page shows the connection as connected with that inbox, the account has an API inbox "Phone", and the account's labels include `inclamo_handover` and `inclamo_urgent` with their descriptions

#### Scenario: The AI service refuses the code

- **WHEN** an administrator enters a code that the AI service refuses as expired
- **THEN** the page shows the AI service's message, and the account has no agent bot, no "Phone" inbox and no new labels

#### Scenario: A code that does not read

- **WHEN** an administrator enters text that is not a connection code
- **THEN** the page says the code is not valid and the AI service receives no request

#### Scenario: An inbox with another bot cannot be picked

- **WHEN** an administrator opens the page in an account whose email inbox already has another bot
- **THEN** the email inbox is listed as having another bot and cannot be picked

### Requirement: The agent answers first in a connected inbox

A new conversation in a connected inbox SHALL be Pending while the agent handles it, and the agent's replies SHALL appear in the shopper's chat and in the conversation under the agent's name. Every message of a conversation in a connected inbox SHALL be delivered to the AI service signed with the agent's secret. That includes the shopper's, the agent's and the team's, and private notes marked private. A conversation of the "Phone" inbox SHALL NOT be handed to the agent.

#### Scenario: Shopper writes in the widget

- **WHEN** a shopper writes "Hello" in the widget of a connected inbox
- **THEN** the AI service receives the message with a valid signature, the agent's reply appears in the widget and in the conversation, and the conversation is in Pending

#### Scenario: The team sees the agent's conversations under Pending

- **WHEN** an agent of the team opens the conversation list while the agent handles a conversation
- **THEN** the conversation is listed under Pending and not under Open

### Requirement: The shopper's files reach the agent

Each file a shopper sends in the widget SHALL reach the AI service with the message that carries it: its type, content type, size and an address. A file sent without text SHALL be delivered like any other message. The agent SHALL be able to read, for a conversation of a connected inbox, its public messages in order with their files, and the number of files in all the shopper's public messages of that conversation.

#### Scenario: One photo

- **WHEN** a shopper sends one photo in the widget
- **THEN** the AI service receives a message with one attachment of type image, and the photo is shown in the conversation to the team

#### Scenario: Two photos

- **WHEN** a shopper sends two photos one after the other
- **THEN** the AI service receives two messages with one image each, and the conversation's history read by the agent counts two files from the shopper

#### Scenario: Photo without text

- **WHEN** a shopper sends a photo with no text
- **THEN** the AI service receives the message with empty text and one image, the agent's reply naming one file appears, and the conversation stays in Pending

### Requirement: The agent reads only connected conversations, without private notes

The helpdesk SHALL give the agent a conversation's public messages, oldest first, each marked as the shopper's, the agent's or the team's, with its files, only for conversations of connected inboxes and only with the connected agent's credentials. Private notes and activity messages SHALL NOT be given.

#### Scenario: Agent reads a conversation with a private note

- **WHEN** the agent reads a connected conversation in which the shopper wrote, the agent replied, and a team member left a private note
- **THEN** it gets the shopper's and the agent's messages in order and not the note

#### Scenario: Agent asks for a conversation of another inbox

- **WHEN** the agent asks for the messages of a conversation in an inbox that is not connected
- **THEN** the helpdesk refuses and gives nothing

### Requirement: The agent's labels are shown and keep the team's

The agent SHALL be able to add labels whose names start with `inclamo_` to a connected conversation without removing any label already on it. A label the account does not have SHALL be created when the agent first adds it, so that it is shown on the conversation. Names that do not start with `inclamo_` SHALL be refused.

#### Scenario: Agent adds a label for a request type

- **WHEN** the agent adds `inclamo_intent_test` to a conversation that the team labelled `vip`
- **THEN** the conversation shows both `vip` and `inclamo_intent_test`, and `inclamo_intent_test` is among the account's labels

### Requirement: The conversation goes to the team when the agent hands over or a person steps in

A pending conversation of a connected inbox SHALL become Open when the agent hands it over, when a team member replies publicly in it, or when a team member is assigned to it. From then on the agent's rules SHALL treat it as the team's. A private note of the team SHALL NOT change its status. The agent SHALL be able to set the conversation's priority and leave a private note for the team. A resolved conversation in which the shopper writes again SHALL return to the agent as Pending.

#### Scenario: Agent hands over with a note

- **WHEN** the shopper asks for a person and the agent hands the conversation over with a note
- **THEN** the conversation is in Open, shows `inclamo_handover`, and the team sees the agent's note as a private note

#### Scenario: Urgent request

- **WHEN** the agent marks a conversation urgent and hands it over
- **THEN** the conversation is in Open with priority Urgent and the label `inclamo_urgent`

#### Scenario: Team member replies in a pending conversation

- **WHEN** a team member sends a public reply in a conversation the agent is handling
- **THEN** the conversation is in Open and the AI service receives that its status changed

#### Scenario: Team member leaves a private note

- **WHEN** a team member leaves a private note in a conversation the agent is handling
- **THEN** the conversation stays in Pending

#### Scenario: Shopper writes again after the agent resolved

- **WHEN** the agent resolves a conversation and the shopper later writes in it again
- **THEN** the conversation is in Pending and the AI service receives the new message

### Requirement: The team gets the conversation when the AI service cannot take it

When a message of a pending conversation cannot be delivered to the AI service, the conversation SHALL become Open with a note saying the agent could not take it. The "AI agent" page SHALL show the connection as failing with the time and kind of the last failure until a delivery succeeds again. The page SHALL NOT show any content of the conversation.

#### Scenario: The AI service is down

- **WHEN** the AI service answers every delivery with an error and a shopper writes in the widget
- **THEN** the conversation is in Open with Chatwoot's note that the bot could not take it, and the page shows the connection as failing with the error's time

#### Scenario: The AI service is back

- **WHEN** after a failure the AI service takes the next delivery
- **THEN** the page shows the connection as connected again

### Requirement: An administrator disconnects the account

Disconnecting SHALL ask for confirmation and then: hand every pending conversation of the connected inboxes to the team, stop all deliveries to the AI service, make the agent's credentials unusable, and tell the AI service. When telling the AI service fails, the page SHALL say so. The "Phone" inbox, its conversations and the labels SHALL stay. After disconnecting, new conversations SHALL open as they did before the connection.

#### Scenario: Administrator disconnects

- **WHEN** an administrator disconnects an account while the agent handles one conversation, and a shopper then starts a new one
- **THEN** the handled conversation is in Open, the new one is in Open, the AI service receives nothing about the new one, and the agent's credentials are refused

#### Scenario: Agent's credentials after disconnecting

- **WHEN** the AI service tries to reply in a conversation with the credentials it had before the disconnection
- **THEN** the helpdesk refuses and no message is added

# app-agent-auto-connection

Behavior contract for this source revision.

The store app is the Shopify app run by the operator of a hosted helpdesk. On
its signed request the helpdesk connects the AI agent to a store's provisioned
account without anybody typing a connection code: the app hands over the AI
service's address and a one-time pairing token, and the helpdesk runs the same
connection the "AI agent" page runs with a code. The helpdesk, not the app,
decides where the agent answers: in the store's storefront chat, or nowhere
(calls only). The app can also ask how the connection is doing and disconnect
it. The agent's credentials go only to an AI service address the operator
listed in `INCLAMO_APP_AGENT_SERVICE_URLS`. The calls themselves are described
in `docs/app-agent-connection.md`; the signature, the request id and the
limits are those of `docs/app-provisioning.md`.

### Requirement: The app connects the agent to a store's account

On a valid signed request from the app naming a store, an AI service address and a one-time pairing token, the helpdesk SHALL connect the store's account to the AI agent exactly as a connection made with a code on the "AI agent" page: the agent's bot, the "Phone" inbox and the agent's labels exist, the AI service has accepted the registration, and the agent answers first in the inboxes the helpdesk chose. No connection code SHALL be typed by anyone. The helpdesk SHALL wait at most 10 seconds for the AI service. When the AI service refuses or does not answer, nothing SHALL be left in the account: no bot, no new "Phone" inbox, no new labels; a refusal SHALL carry the AI service's own message and error code.

#### Scenario: A provisioned account is connected

- **WHEN** the app sends a valid request for a store whose account is active, not connected and has its storefront inbox
- **THEN** the answer says the agent was connected and lists the storefront inbox and the "Phone" inbox, and a shopper's new message in the storefront inbox is held for the agent

#### Scenario: The AI service refuses

- **WHEN** the app sends a valid request and the AI service refuses the pairing token as expired
- **THEN** the answer carries the AI service's refusal, and the account has no agent bot, no "Phone" inbox and no new labels

#### Scenario: The AI service does not answer

- **WHEN** the app sends a valid request and the AI service gives no answer in time
- **THEN** the answer says the AI service did not answer, and the account has no agent bot, no "Phone" inbox and no new labels

### Requirement: Only a provisioned, active account is connected this way

The request SHALL be accepted only under the same checks as a provisioning request (signature, time, one-time request id, limits), and only for a store that has an active provisioned account. A store without an account and a store whose account is suspended SHALL be refused with a reason, and nothing SHALL be created. An account that was not provisioned by the app SHALL NOT be reachable through this channel. An installation without provisioning SHALL answer these calls as any unknown address.

#### Scenario: A store without an account

- **WHEN** the app sends a valid request for a store that has no account
- **THEN** it is refused as having no account and nothing is created

#### Scenario: A suspended account

- **WHEN** the app sends a valid request for a store whose account is suspended
- **THEN** it is refused as suspended and the account has no agent bot

#### Scenario: A request with a wrong signature

- **WHEN** a request for a store with an active account arrives signed with another secret
- **THEN** it is refused as not authorised and the account is not connected

### Requirement: The helpdesk chooses where the agent answers

The app's request SHALL NOT choose inboxes: a list of inboxes in the request SHALL have no effect. At connection the helpdesk SHALL attach the agent to the account's storefront inbox when the account has one and it has no other bot, and to no other inbox. When the account has no storefront inbox, or it has another bot, the account SHALL be connected for calls only: calls are filed in "Phone" and no conversation of any inbox is held for the agent. The answer SHALL list the inboxes the agent answers in.

#### Scenario: The agent starts in the storefront chat

- **WHEN** the app sends a valid request for an account that has its storefront inbox and an email inbox
- **THEN** the agent answers in the storefront inbox only, and a new message in the email inbox goes to the team as before

#### Scenario: The request names inboxes

- **WHEN** the app sends a valid request that lists the account's email inbox as the agent's inbox
- **THEN** the account is connected, the answer lists the storefront inbox only, and the email inbox has no agent

#### Scenario: The storefront inbox has another bot

- **WHEN** the app sends a valid request for an account whose storefront inbox already has another bot
- **THEN** the account is connected with the "Phone" inbox only, the answer lists no chat inbox, and the other bot still answers in the storefront inbox

#### Scenario: Connected for calls only

- **WHEN** the app sends a valid request for an account that has no storefront inbox
- **THEN** the account is connected with the "Phone" inbox only, a finished call is filed in it, and a shopper's new message in any website inbox of the account goes to the team as before

### Requirement: Asking again changes nothing

A request for an account that is already connected to the same AI service address SHALL be answered with the existing connection as it is now, SHALL say it already existed, SHALL NOT register again, SHALL NOT use the pairing token and SHALL NOT change the inboxes the agent answers in. This holds for a connection made on the "AI agent" page too. A request that names another AI service address for a connected account SHALL be refused as already connected and SHALL change nothing.

#### Scenario: The request is repeated

- **WHEN** the app sends a second request with the same address for a connected account
- **THEN** the answer describes the same connection and says it already existed, the AI service received no second registration, and the agent's bot is the same

#### Scenario: A storefront inbox appears after the connection

- **WHEN** an account was connected for calls only, then gets a storefront inbox, and the app sends the request again with the same address
- **THEN** the answer says the connection already existed and lists no chat inbox, and a shopper's new message in the storefront inbox goes to the team

#### Scenario: Another address for a connected account

- **WHEN** the app sends a request naming another allowed AI service address for an account that is connected
- **THEN** it is refused as already connected and the agent's bot and inboxes are unchanged

### Requirement: The agent's credentials go only to an allowed AI service

The helpdesk SHALL register only with an AI service address the operator listed for the installation; the operator may list several. A request naming any other address, or an address that is not HTTPS, SHALL be refused before any request leaves the helpdesk and before anything is created. An installation with no listed address SHALL refuse every such request. A connection code pasted on the "AI agent" page is not limited by this list.

#### Scenario: An address that is not listed

- **WHEN** the app sends a correctly signed request naming an AI service address the operator did not list
- **THEN** it is refused as naming an address that is not allowed, no request was sent to that address, and the account has no agent bot

### Requirement: The app can ask how the connection is doing

The app SHALL be able to ask, with a signed request, about the connection of a store's account, and SHALL be told its state (never connected, connected, failing, disconnected), whether it was made by the app or on the page, the inboxes the agent answers in at that moment, the "Phone" inbox, when it was connected, when the agent last answered, and the time and kind of the last failed delivery. The answer SHALL NOT include the bot's token, its secret, the pairing token or any conversation's content.

#### Scenario: A connected account

- **WHEN** the app asks about a store whose account is connected and whose last delivery succeeded
- **THEN** the answer gives the state "connected", the inboxes and the delivery times, and holds no token or secret

#### Scenario: Deliveries are failing

- **WHEN** the app asks about a store whose last delivery to the AI service failed
- **THEN** the answer gives the state "failing" with the time and the kind of the failure

#### Scenario: An account that was never connected

- **WHEN** the app asks about a store whose account never had a connection
- **THEN** the answer gives the state "never connected" and no inboxes

### Requirement: The app can disconnect the agent

On the app's signed request the helpdesk SHALL disconnect the store's account from the agent as the "AI agent" page does: the agent's pending conversations go to the team, the bot and its token are removed at once, the AI service is told, and the "Phone" inbox, its conversations and the labels stay. The answer SHALL say whether the AI service could be told. A request for an account that is not connected SHALL be answered as done.

#### Scenario: The app disconnects

- **WHEN** the app sends a valid disconnection request for a connected account that has two pending conversations with the agent
- **THEN** both conversations are open for the team, the agent's token is refused from that moment, and the "Phone" inbox with its conversations is still there

#### Scenario: Disconnecting twice

- **WHEN** the app sends the disconnection request again
- **THEN** it is answered as done and nothing changes

### Requirement: A suspended account has no agent

When a store's account is suspended on the app's removal notice, the helpdesk SHALL disconnect the agent as part of the suspension, with the same effects as a disconnection; an AI service that cannot be told SHALL NOT stop the suspension. Restoring the account SHALL NOT connect the agent; the account stays not connected until the app asks again.

#### Scenario: The app is removed from a connected store

- **WHEN** the app sends the removal notice for a store whose account is connected
- **THEN** the account is suspended, the agent's token is refused, and the AI service was told the connection is gone

#### Scenario: The store installs the app again

- **WHEN** the suspended account of a store is restored and the app has not asked to connect
- **THEN** the account's state is "disconnected", no bot exists in it, and a shopper's new message goes to the team

### Requirement: The "AI agent" page keeps working and names the app

The "AI agent" page SHALL keep connecting with a connection code and at least one inbox on every installation, with or without provisioning. For a connection the app made, the page SHALL show it like any other connection and SHALL say it was connected by the store app instead of naming a person; a connection without an inbox SHALL be shown as taking calls only. An administrator SHALL be able to disconnect such a connection on the page, and SHALL be able to connect again there with a code and inboxes of their choice; the app SHALL NOT undo that choice.

#### Scenario: An installation without provisioning

- **WHEN** an administrator of a self-hosted installation opens "AI agent" and connects with a valid code and one inbox
- **THEN** the account is connected as before this change

#### Scenario: A connection made by the app

- **WHEN** an administrator opens "AI agent" in an account the app connected
- **THEN** the page shows the connected inboxes and the delivery state, and says the connection was made by the store app

#### Scenario: The administrator disconnects a connection the app made

- **WHEN** an administrator presses "Disconnect" on such a connection and confirms
- **THEN** the account is disconnected, and the app's next status request answers "disconnected"

#### Scenario: The administrator moves the agent to other inboxes

- **WHEN** an administrator disconnects a connection the app made and connects on the page with a code and the email inbox only
- **THEN** the agent answers in the email inbox only, and the app's next status request lists the email inbox and says the connection was made on the page

### Requirement: Every attempt is recorded without secrets

Each connection, status and disconnection request of the app SHALL be recorded with its time, the store's domain and its outcome. The record SHALL NOT hold the pairing token, the bot's token or secret, or the signature.

#### Scenario: A refused connection is recorded

- **WHEN** the AI service refuses a connection the app asked for
- **THEN** a record exists with the time, the store's domain and the outcome "agent_refused", and without any token

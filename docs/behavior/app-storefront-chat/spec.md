# app-storefront-chat

Behavior contract for this source revision.

The store app is the Shopify app run by the operator of a hosted helpdesk. A
store whose helpdesk account was created on the app's request gets a website
inbox for its storefront chat, made together with the account. On the app's
signed request the helpdesk tells it the public values the chat widget needs,
so the app can show the widget through its own theme extension. The inbox is
an ordinary website inbox that belongs to the account's team. The calls
themselves are described in `docs/app-storefront-chat.md`.

### Requirement: A new account has its storefront inbox

When the helpdesk creates an account on the store app's request, it SHALL create in the same step a website inbox for the storefront, named after the store, with the store's own Shopify address as its website address. The account and the inbox SHALL be created together or not at all. The request and the answer that create the account SHALL NOT change because of it. An account that is restored after a suspension, or that already existed, SHALL NOT be given a new inbox by that request.

#### Scenario: The account is created

- **WHEN** the app's request creates an account for a store
- **THEN** the account has one website inbox named after the store, and the app's request for the storefront chat answers that it already existed and gives its website token

#### Scenario: A restored account whose inbox was deleted

- **WHEN** a store's suspended account, whose team had deleted the storefront inbox, is restored by the app's request
- **THEN** the account is active and has no storefront inbox until the app asks for one

### Requirement: The app's request finds or makes the storefront inbox

On a valid request from the store app for a store that has an active provisioned account, the helpdesk SHALL answer with the storefront inbox's website token and the address the widget is loaded from. When the account has no storefront inbox, the request SHALL make one, named after the account, with the storefront address the app gives or, when it gives none, the store's own Shopify address. The inbox SHALL be usable at once: a widget loaded with the answered values SHALL open a conversation in it. A request that gives a storefront address which does not read as an HTTPS address SHALL be refused and SHALL create nothing.

#### Scenario: An account without a storefront inbox

- **WHEN** the app sends a valid request for a store whose account has no storefront inbox, naming the storefront address
- **THEN** the answer says the inbox was created and gives its website token and the widget's address, and the inbox carries the named address

#### Scenario: No storefront address is given

- **WHEN** the app sends a valid request without a storefront address for a store whose account has no storefront inbox
- **THEN** the inbox is created with the store's own Shopify address

#### Scenario: A shopper writes through the answered values

- **WHEN** a page loads the widget with the answered website token and address and a shopper sends a message
- **THEN** a conversation with that message appears in the store's inbox

#### Scenario: The storefront address does not read

- **WHEN** the app sends a request whose storefront address is present and is not an HTTPS address
- **THEN** the request is refused with a reason and the account has no new inbox

### Requirement: An account has one storefront inbox

The helpdesk SHALL keep at most one inbox per account as the storefront inbox made this way. A request for an account that has its storefront inbox SHALL answer with the same inbox and the same token, SHALL say it already existed, and SHALL NOT create an inbox or change its name, its address or any of its settings. Two requests arriving together SHALL end with one inbox. Website inboxes the team made themselves SHALL NOT be counted, changed or reported.

#### Scenario: The request is repeated

- **WHEN** the app sends a second valid request for a store that already has its storefront inbox
- **THEN** the answer gives the same website token and says the inbox already existed, and the account still has one storefront inbox

#### Scenario: The team changed the inbox

- **WHEN** an administrator renamed the storefront inbox and changed its greeting, and the app sends the request again
- **THEN** the inbox keeps the administrator's name and greeting and the answer gives the same token

#### Scenario: The team has a website inbox of their own

- **WHEN** an account without a storefront inbox has a website inbox an administrator created by hand, and the app sends its request
- **THEN** a separate storefront inbox is created, the administrator's inbox is unchanged, and its token is not in the answer

#### Scenario: Two requests at the same moment

- **WHEN** two valid requests arrive together for a store whose account has no storefront inbox
- **THEN** both are answered with the same website token and the account has one storefront inbox

### Requirement: Only public values leave the helpdesk

The answer SHALL hold the inbox's website token, the address the widget is loaded from, the inbox's identifier and its state, and nothing else of the inbox. It SHALL NOT hold the inbox's identity-verification key, its settings, its conversations, its contacts or its members.

#### Scenario: The answer is read

- **WHEN** the app receives the answer for a storefront inbox
- **THEN** it holds the website token, the widget's address, the inbox identifier and the state, and no identity-verification key, conversation, contact or member

### Requirement: The storefront inbox is an ordinary website inbox

The storefront inbox SHALL appear to the account's team as any website inbox: in the inbox list, in the website widget editor and in the native inbox settings, with the same rights. This capability SHALL NOT attach a bot to it: whether the AI agent answers in it is decided by the agent's connection and by the team on the "AI agent" page, and while no agent is connected its conversations SHALL go to the team. Settings the team publishes for it SHALL apply to the widget on the storefront on its next load, without a new request from the app and without a change in the theme.

#### Scenario: An administrator changes the launcher

- **WHEN** an administrator saves a new launcher position for the storefront inbox in the website widget editor
- **THEN** a newly loaded widget with the same token shows the launcher in the new position

#### Scenario: No agent is connected

- **WHEN** a shopper writes in the storefront inbox of an account whose AI agent has not been connected
- **THEN** the conversation is open for the team and is held for no bot

#### Scenario: An agent of the account sees the inbox

- **WHEN** a member of the storefront inbox opens the conversation list
- **THEN** the inbox is listed and its conversations open as in any website inbox

### Requirement: The app can ask about the storefront chat

The app SHALL be able to ask, with a signed request, whether a store has its storefront inbox, and SHALL be told its website token, the widget's address, the inbox identifier and the state, or that there is none. The state SHALL say whether a widget loaded now would be served: "active" when the account is active, "suspended" when it is not.

#### Scenario: A store with its storefront inbox

- **WHEN** the app asks about a store whose account is active and has its storefront inbox
- **THEN** the answer gives the token, the widget's address, the inbox identifier and the state "active"

#### Scenario: A store without one

- **WHEN** the app asks about a store whose account has no storefront inbox
- **THEN** the answer says there is none

### Requirement: A deleted storefront inbox is reported, not silently replaced

When the team deletes the storefront inbox, the helpdesk SHALL answer a status request as none, and a widget loaded with the old token SHALL NOT be served. A new inbox SHALL be made only on a new request that asks for one; it SHALL have a new token and none of the old inbox's conversations.

#### Scenario: An administrator deletes the inbox

- **WHEN** an administrator deletes the storefront inbox and the app asks about the store
- **THEN** the answer says there is none, and a page that still loads the widget with the old token shows no chat

#### Scenario: The app asks for the inbox again

- **WHEN** the app sends the request for a store whose storefront inbox was deleted
- **THEN** a new inbox is created, the answer says created and gives a token different from the old one

### Requirement: A suspended account has no storefront chat

While a store's account is suspended, a widget loaded with its token SHALL NOT be served and SHALL NOT accept messages, and a request to make the inbox SHALL be refused as the account is not active. The inbox, its token and its conversations SHALL be kept; when the account is restored the same token SHALL serve the widget again.

#### Scenario: The app was removed

- **WHEN** a store's account is suspended and a page loads the widget with its token
- **THEN** the widget is refused and no conversation is created

#### Scenario: The store returns

- **WHEN** the account is restored and a page loads the widget with the same token
- **THEN** the widget opens and a shopper who wrote before the suspension finds their earlier conversation

#### Scenario: A request for a suspended account

- **WHEN** the app sends the request for a store whose account is suspended
- **THEN** it is refused with the reason that the account is not active and nothing is created

### Requirement: The storefront chat calls follow the provisioning channel's rules

Requests about the storefront chat SHALL be accepted only under the same conditions as the other provisioning requests: signed with the shared secret over the time, the method, the path and the body, with a key used once; limited; recorded with the time, the store's domain and the outcome and without personal data; and absent on an installation that has no shared secret. A request for a store that has no provisioned account SHALL be answered that there is no account and SHALL create nothing.

#### Scenario: A request without a valid signature

- **WHEN** a request for a store's storefront inbox arrives with a signature made with another secret
- **THEN** it is refused as not authorised and the account has no new inbox

#### Scenario: A store without an account

- **WHEN** the app sends a correctly signed request for a store that never had an account
- **THEN** the answer says there is no account, and no account and no inbox are created

#### Scenario: A self-hosted installation

- **WHEN** a request arrives at a storefront chat address of an installation that has no shared secret
- **THEN** it is answered as not found and nothing is created

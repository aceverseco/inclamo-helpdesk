# in-product-support

Behavior contract for this source revision.

### Requirement: Support is available across installation types

Every authenticated account member SHALL have an accessible Support Inclamo entry for creating and viewing support requests on both hosted and self-hosted installations. Availability SHALL NOT depend on a paid plan, an administrator-only role or a pinned widget. Technical setup failures SHALL be distinguished from entitlement restrictions.

#### Scenario: Self-hosted agent requests help

- **WHEN** an ordinary agent opens Support Inclamo on a self-hosted installation with no previously established support connection
- **THEN** the system initiates the supported connection setup and permits the request without requiring a hosted subscription or a central Chatwoot token from the agent

#### Scenario: Support endpoint is unavailable

- **WHEN** the installation cannot reach the support service
- **THEN** the interface states the connectivity problem, preserves the current draft and offers retry
- **AND** it does not claim that support is restricted to hosted users

### Requirement: A short request form

The request form SHALL offer problem, question and suggestion categories, require a description and make screenshots and attachments optional. The author and originating account SHALL come from the authenticated context. The author SHALL NOT be required to re-enter already known name, email or installation information.

#### Scenario: Submit a question without a screenshot

- **WHEN** an account member selects question, enters a description and submits
- **THEN** the request is accepted with the authenticated author and account without requiring a screenshot or extra identity fields

#### Scenario: Invalid description or attachment

- **WHEN** a description is empty or an attachment violates the displayed type/size limit
- **THEN** the form identifies the problem without losing valid text or other attachments
- **AND** the server enforces the same attachment limits

### Requirement: Screenshot capture and review

The request form SHALL support capturing the current interface on supported desktop browsers, pasting an image where supported and uploading a screenshot file. Before submission the author SHALL be able to preview, remove, crop, highlight with an arrow or rectangle, and irreversibly cover sensitive regions of the submitted image. Capture failure, cancellation or unsupported browsers SHALL NOT prevent submitting text or uploaded files.

#### Scenario: Annotate and redact a capture

- **WHEN** the author captures the interface, adds an arrow and covers a sensitive region
- **THEN** the preview shows the final image
- **AND** only the final flattened image is submitted, without the original pixels underneath redaction

#### Scenario: Capture is denied or unavailable

- **WHEN** the author declines browser capture permission or uses a browser without capture support
- **THEN** the description remains available and the author can upload a file or submit without a screenshot

### Requirement: Controlled diagnostic context

The form SHALL disclose the automatically included application version, timestamp, browser and sanitized application location before sending. The author SHALL control optional attachment of a current-conversation reference, order information or conversation content. The default submission SHALL NOT contain a conversation transcript, order payload, cookies, credentials, network bodies or session replay. Data collection for a support request SHALL begin with an explicit support interaction.

#### Scenario: Review a report while viewing a customer conversation

- **WHEN** an author opens the request form from a conversation
- **THEN** the form shows the basic technical context and offers a removable optional conversation reference
- **AND** conversation messages and order details are not silently attached

#### Scenario: Sanitized location

- **WHEN** the current location contains query values or fragments that could carry credentials or customer data
- **THEN** the submitted context omits them and retains only the supported sanitized route information

### Requirement: Native central Chatwoot conversations

Each new support issue SHALL create one ordinary conversation in the configured central support inbox, with an incoming message containing its description and approved attachments. The conversation SHALL expose category, originating installation/account and application version for support triage. Existing central assignment, labels, public replies and private notes SHALL continue to work.

#### Scenario: A request reaches support

- **WHEN** the central service accepts a new submitted issue
- **THEN** support staff receive one conversation with the description, final screenshot and triage attributes
- **AND** the author receives a stable support reference independent of local customer-conversation identifiers

### Requirement: Trustworthy installation attribution

Support staff SHALL immediately see whether a request originated from Inclamo hosting or a self-hosted installation. Hosted attribution SHALL require a match to trusted hosted registration and SHALL NOT be granted from a browser-supplied flag, email domain or self-hosted claim. Every request SHALL retain its originating installation and account even if the same person reports from multiple accounts.

#### Scenario: A self-hosted request claims hosted status

- **WHEN** an unregistered self-hosted client submits a payload claiming to be hosted
- **THEN** the central conversation is classified as self-hosted
- **AND** its actual registered source is retained for support staff

#### Scenario: Same reporter in two installations

- **WHEN** one email address is used to report issues from two installations
- **THEN** each request retains its own source and access boundary regardless of any contact merging in Chatwoot

### Requirement: Author and account-administrator access

The author and current administrators of the originating account SHALL be able to list, read, download authorized attachments and add public replies to that account's support request. Other ordinary members SHALL NOT access it. An administrator's reply SHALL identify that administrator and SHALL NOT impersonate the author. All checks SHALL apply to APIs and attachment access as well as the interface.

#### Scenario: Administrator helps with an agent's issue

- **WHEN** an account administrator opens a request created by a member of that account and replies
- **THEN** the administrator can read the public thread and send an attributed reply
- **AND** the author remains identified as the original reporter

#### Scenario: Another member guesses the reference

- **WHEN** an ordinary member other than the author, or an administrator of another account, requests the thread or an attachment using its reference
- **THEN** access is denied without exposing message content or attachment links

#### Scenario: Membership is revoked

- **WHEN** a former member or former administrator tries to access a request after losing the necessary account access
- **THEN** current authorization is enforced rather than the role recorded when the request was created

### Requirement: Public replies and request status return to the product

My Requests SHALL show authorized threads, public messages, attachments, unread replies and the central conversation's current status. Support replies SHALL be delivered to the existing thread. Central private notes, staff-only activity and internal diagnostics SHALL NOT be returned to the requester interface. Status labels SHALL preserve Chatwoot's meaning; pending SHALL NOT be mislabeled as waiting for the customer.

#### Scenario: Public reply and private note

- **WHEN** a support agent adds a private note and then a public reply
- **THEN** the requester receives only the public reply and its permitted attachments
- **AND** the thread gains an unread indication until that user reads it

#### Scenario: Resolve and follow up

- **WHEN** support resolves a request and its author later sends a follow-up
- **THEN** the follow-up stays in the same thread and the displayed status follows the central conversation's reopen behavior

### Requirement: Email notifications link back to the thread

New public support replies SHALL trigger an email notification to the author's verified email when available. The email SHALL link to the authenticated request view without embedding private notes, screenshots or order data. A missing verified email or failed email delivery SHALL NOT block the in-product conversation. Email replies as a second conversation channel are outside this release.

#### Scenario: Notify an offline author

- **WHEN** a public support reply arrives for an author with a verified email
- **THEN** a notification email links to the same request
- **AND** duplicate event delivery does not send duplicate notifications

#### Scenario: Email is unavailable

- **WHEN** no verified email is available or the email service fails
- **THEN** the reply remains visible in My Requests with its unread state

### Requirement: Retry without duplicate conversations or messages

Submission SHALL expose whether a request is queued, delivered or failed. A stable submission identity SHALL survive retries. Duplicate submissions, transport timeouts and repeated reply events SHALL NOT create duplicate central conversations, messages or email notifications. A partial attachment failure SHALL NOT be silently presented as complete delivery.

#### Scenario: Acknowledgement is lost

- **WHEN** central conversation creation succeeds but the acknowledgement is lost and delivery is retried
- **THEN** the retry reconciles to the existing conversation and original message
- **AND** the interface eventually reports the actual delivery state

#### Scenario: Screenshot delivery fails after text delivery

- **WHEN** the text has reached support but the approved screenshot has not
- **THEN** the interface identifies the incomplete attachment delivery and retries it against the existing thread without duplicating the issue

### Requirement: Support transport is isolated from customer work

Support service failure SHALL NOT prevent viewing or replying to ordinary customer conversations. Central support credentials SHALL remain on central infrastructure. A client installation's credential SHALL authorize only its own registered source and request mappings, and client-visible data SHALL be limited by the author/admin access rule.

#### Scenario: Central support outage during a shift

- **WHEN** support connectivity fails while an agent is handling a customer conversation
- **THEN** support shows its own recoverable error while native conversation actions and the unsent customer reply remain intact

#### Scenario: An installation credential is reused against another source

- **WHEN** an installation requests another installation's support data with its own credential
- **THEN** the central service denies the request

### Requirement: Accessible support interaction

Support forms, annotation controls and request threads SHALL support the existing light/dark appearance, keyboard focus behavior and responsive layouts. Annotation SHALL be optional so that text and file submission remain usable without drawing gestures.

#### Scenario: Submit from a narrow screen using keyboard controls

- **WHEN** an author opens support on a narrow layout and enters a description with an uploaded image
- **THEN** the author can review and submit without using capture or drawing tools
- **AND** closing support returns to the prior customer workflow without losing its draft

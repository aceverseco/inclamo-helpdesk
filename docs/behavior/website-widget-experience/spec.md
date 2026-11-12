# website-widget-experience

Behavior contract for this source revision.

### Requirement: Configurable launcher and merchant identity

Administrators SHALL be able to choose a supplied launcher icon or upload a valid PNG, JPEG, WebP or sanitized SVG image up to 1 MB, independently of the logo inside the chat. The widget SHALL support the existing color, greeting, round/expanded launcher and label options plus left/right placement, bounded horizontal/bottom offsets and light/dark/automatic appearance. Removing a custom icon or failure to load it SHALL restore a usable default icon. Merchant identity SHALL remain independent of the staff workspace logo.

#### Scenario: Merchant publishes a custom launcher

- **WHEN** the administrator saves a valid custom icon and a new visitor page loads
- **THEN** the launcher uses that image, retains its open/close/unread behavior and leaves the separately configured header logo intact

#### Scenario: Launcher image is unavailable

- **WHEN** the configured launcher image cannot be loaded
- **THEN** the visitor sees a usable default launcher and can open the chat

### Requirement: Ordered suggested intents

Administrators SHALL be able to add, edit, enable, disable, remove and reorder up to six enabled suggested-intent buttons with stable identities, labels up to 60 characters and plain-text starter messages up to 500 characters. Visitors SHALL see only enabled entries in the saved order. These buttons SHALL request assistance through ordinary messages and SHALL NOT imply completion of a business operation.

#### Scenario: Visitor chooses an intent

- **WHEN** a visitor with no required pre-chat form selects “Where is my order?”
- **THEN** its configured message is submitted through the normal conversation flow and appears to the receiving operator or connected bot

#### Scenario: No intents are configured

- **WHEN** a website inbox has no enabled suggested intents
- **THEN** its home screen retains the standard option to start a conversation without an empty intent section

### Requirement: Starters preserve native conversation rules

Intent selection SHALL obey pre-chat validation, conversation resolution restrictions, single-conversation behavior and bot/human routing. A pending submission SHALL prevent duplicate rapid clicks. Failed or uncertain submission SHALL show a recoverable state without silently creating another conversation.

#### Scenario: Pre-chat form is required

- **WHEN** a new visitor selects an intent while required pre-chat fields are enabled
- **THEN** the normal form appears with the starter message available for editing, no message is sent until valid submission, and submission creates one initial message

#### Scenario: Visitor cancels the form

- **WHEN** the visitor cancels after selecting an intent
- **THEN** no starter message is sent

#### Scenario: Existing conversation or bot is present

- **WHEN** a starter is selected for an existing conversation or an inbox with a connected bot
- **THEN** native continuation, resolved-conversation and handoff rules apply rather than an independent conversation lifecycle

### Requirement: Quick help links and knowledge access

Administrators SHALL be able to manage and order up to six enabled quick links to published articles in the connected account Help Center or HTTPS resources, with labels up to 60 characters. Article links SHALL use the existing article-view experience and external links SHALL open safely. Unpublished or unavailable article entries SHALL not be presented as working links. Following a help link SHALL NOT create a conversation.

#### Scenario: Visitor reads a help article

- **WHEN** the visitor selects a configured published article
- **THEN** the article opens with a route back to the widget and no ticket is created by that action

#### Scenario: Invalid link is configured

- **WHEN** an administrator tries to publish a script URL, non-HTTPS external URL or inaccessible article reference
- **THEN** the editor rejects the link with a useful validation error

### Requirement: Page visibility with SPA continuity

The editor SHALL support all-pages, include-paths and exclude-paths modes with up to 20 exact/prefix pathname rules, ignoring query strings and fragments. Visibility SHALL update on client-side navigation without resetting visitor history. Excluded pages SHALL suppress the launcher and automatic campaign/unread opening; an explicit site-owned programmatic open SHALL remain available. Domain restrictions SHALL continue to apply independently.

#### Scenario: Visitor navigates to an excluded page

- **WHEN** a visitor navigates from an included page to an excluded pathname without a full reload
- **THEN** the widget closes and its launcher and automatic prompts are hidden while conversation state is retained for a later included page

### Requirement: Native language and theme behavior

The editor SHALL expose a supported fixed locale or browser-language mode with fallback to the account's supported locale. Built-in widget strings SHALL use existing translations. Merchant-authored labels and messages SHALL remain as entered, and the editor SHALL explain that they are not automatically translated. Appearance SHALL respect the saved light/dark/automatic setting unless explicitly overridden by the site.

#### Scenario: Browser language is unsupported

- **WHEN** browser-language mode encounters an unsupported locale
- **THEN** native widget text falls back to the account locale and merchant-authored messages remain unchanged

### Requirement: Accessible and responsive interaction

Launcher, starters, quick links and close controls SHALL have accessible names and work with keyboard navigation and visible focus. Closing the widget SHALL return focus to the launcher where present. At viewport widths down to 320 CSS pixels, including RTL, the launcher and close controls SHALL remain reachable and the chat SHALL not require horizontal scrolling. Offsets SHALL respect available viewport and safe-area space.

#### Scenario: Mobile viewport with large offsets

- **WHEN** the widget opens at 320 CSS pixels with the largest supported offsets
- **THEN** the visitor can read, send and close the conversation without an off-screen control or horizontal scrolling

### Requirement: Native transport and bounded visitor overhead

The widget SHALL retain native message delivery, uploads, session continuity and operator/bot handoff. Configuration customization SHALL add no polling, duplicate widget connection or configuration request on each UI render. Added compressed JavaScript across the visitor SDK and initial widget load SHALL be at most 20 KiB relative to the recorded baseline, excluding separately fetched merchant images.

#### Scenario: Customized widget is idle

- **WHEN** an installed customized widget remains idle and its UI rerenders
- **THEN** it introduces no additional periodic configuration requests or duplicate messaging connection compared with the unchanged native widget

#### Scenario: Visitor returns to the site

- **WHEN** an identified or anonymous visitor reloads the website after a conversation
- **THEN** native history and identity handling continue working with the configured home screen

# website-widget-settings

Behavior contract for this source revision.

### Requirement: Discoverable website widget editor

The system SHALL expose a Website widget entry in Workspace tools and account settings, with a website-inbox selector and Appearance, Home screen, Behavior and Installation sections. It SHALL retain existing inbox settings links and distinguish website widgets from operator workspace widgets.

#### Scenario: Administrator opens a configured website

- **WHEN** an administrator follows Website widget and selects a website inbox
- **THEN** the editor displays that inbox's current settings and preview, with the selection preserved in a reloadable URL

#### Scenario: No website inbox exists

- **WHEN** an administrator opens the editor in an account without a website inbox
- **THEN** an empty state offers the native website-channel creation flow without showing settings from another account

### Requirement: Account and role boundaries

Only administrators authorized for the selected account SHALL read or change its widget administration settings, upload launcher assets or use its draft preview. The public widget SHALL receive only visitor-facing configuration.

#### Scenario: Unauthorized configuration request

- **WHEN** a non-administrator or an administrator from a different account requests or updates the inbox configuration
- **THEN** access is denied and no settings or assets are changed or disclosed

#### Scenario: Public configuration is inspected

- **WHEN** a visitor loads a website widget
- **THEN** its presentation configuration contains no account-management credentials, identity-validation secret, private customer information or draft settings

### Requirement: Shared publication without snippet replacement

Valid changes saved in the editor SHALL become the shared published settings for that website inbox. The next widget page load SHALL use them without a new installation snippet, subject to documented explicit SDK overrides. Unsaved changes SHALL remain private to the editing session. Saving SHALL NOT forcibly reload active conversations.

#### Scenario: Another administrator sees the saved result

- **WHEN** one administrator saves a launcher, home-screen or behavior change and another opens the inbox in a different browser
- **THEN** both see the same published settings and a newly loaded widget uses those settings

#### Scenario: Draft is abandoned

- **WHEN** an administrator edits and previews settings but leaves without saving
- **THEN** the installed widget and other administrators retain the previous published settings

### Requirement: Validated and consistent saves

The editor SHALL validate field values, action limits and uploaded images before publication, return understandable field errors and retain unsaved input after failures. A failed save SHALL NOT partly publish the submitted configuration. A stale save SHALL report a conflict instead of silently replacing a newer version.

#### Scenario: Invalid or active uploaded content

- **WHEN** an administrator submits a malformed image, an upload over 1 MB, or SVG containing active content or external references
- **THEN** publication is rejected with an error and the previous public launcher remains available

#### Scenario: Conflicting administrator changes

- **WHEN** an administrator saves an older editor state after another administrator has published changes
- **THEN** the editor identifies the conflict and preserves the unsaved input for review

### Requirement: Native settings remain authoritative and reachable

Existing color, channel logo, greeting, portal selection, availability, reply time, pre-chat form, feature flags, CSAT, email continuity, bot configuration and domain/identity controls SHALL remain available through shared controls or explicit links to their native settings. Changes to shared fields SHALL agree between the native inbox page and the new editor. A link to another settings screen SHALL clearly indicate where changes on that screen are saved.

#### Scenario: Native inbox settings are edited

- **WHEN** an administrator changes a shared field through the existing inbox page and then opens the widget editor
- **THEN** the editor reflects that saved value without restoring a duplicate stale copy

### Requirement: Side-effect-free preview

The editor SHALL preview unsaved appearance and home-screen changes using the same presentation behavior as the installed widget, with desktop/mobile, home/conversation and online/offline states. Preview data SHALL be visibly synthetic. Preview interactions SHALL NOT create visitor contacts, conversations, messages, persistent visitor sessions, campaign events or bot calls.

#### Scenario: Administrator tries a starter in preview

- **WHEN** the administrator selects a suggested intent in the draft preview
- **THEN** the preview demonstrates the resulting screen locally without delivering a message or changing customer records

### Requirement: Existing installation compatibility

Existing website tokens, snippets, custom launchers and valid explicit SDK options SHALL continue working. For SDK-configurable presentation fields, explicit site values SHALL override saved inbox values, which SHALL override native defaults. The editor SHALL explain this precedence and provide a clean snippet and one-time removal guidance for legacy overrides. Browser-local legacy builder values SHALL NOT be silently published.

#### Scenario: Existing snippet supplies a position

- **WHEN** an installed snippet explicitly requests the left position while the saved inbox position is right
- **THEN** the installed widget remains on the left and installation guidance explains how to use the saved position instead

#### Scenario: Existing inbox has no extension settings

- **WHEN** an unchanged inbox loads after the upgrade
- **THEN** its native branding, pre-chat behavior, session history and existing SDK options continue working with no new starter buttons by default

### Requirement: Configuration failure preserves the chat

Invalid or missing optional extension settings SHALL fall back to native widget defaults without preventing the existing chat from loading or sending messages.

#### Scenario: Optional presentation configuration is unusable

- **WHEN** a widget receives unusable extension settings but valid native channel settings
- **THEN** it renders the native chat and default launcher instead of a broken or empty interface

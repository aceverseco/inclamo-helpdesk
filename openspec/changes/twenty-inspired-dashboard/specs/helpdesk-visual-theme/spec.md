## Purpose

Give Inclamo Helpdesk a coherent appearance based on Twenty's visual language while preserving the familiar operator workflows and capabilities inherited from Chatwoot CE.

## ADDED Requirements

### Requirement: One consistent dashboard appearance

The authenticated Inclamo dashboard SHALL use one default visual theme with a shared palette, typography, borders and control appearance based on the recorded Twenty reference. The operator workspace and Inclamo settings SHALL use these rules consistently, including normal, selected, hover, focus, disabled, loading and error states where applicable. A separate product-theme selection or customer setup step SHALL NOT be required.

#### Scenario: Operator workspace uses the common appearance
- **WHEN** an agent opens a conversation with its customer and order sidebar
- **THEN** the navigation, conversation list, conversation header, composer, sidebar and order-action dialog use the common visual rules
- **AND** selected conversations, unread messages, internal notes and unavailable actions remain distinguishable

#### Scenario: Inclamo settings belong to the same interface
- **WHEN** an administrator opens the order-permissions page and then the preset-rules page
- **THEN** headings, rows, fields, switches and action states follow the same visual rules as the operator workspace
- **AND** neither page introduces its own independent palette or control appearance

### Requirement: Existing appearance preference controls light and dark modes

The dashboard SHALL provide matching light and dark palettes through the existing Chatwoot appearance preference. An existing stored preference and the existing system-preference behavior, where offered, SHALL retain their meaning. Changing appearance SHALL preserve the open conversation and any unsent reply.

#### Scenario: Existing preference survives navigation and reload
- **WHEN** a user with a stored light or dark preference opens the dashboard, navigates to settings and reloads
- **THEN** each surface uses the corresponding Inclamo palette, including dialogs and dropdowns
- **AND** no additional theme preference is requested

#### Scenario: Changing appearance preserves an unsent reply
- **WHEN** an agent changes the existing appearance preference with an unsent reply in the composer
- **THEN** the workspace and any subsequently opened dialog use the selected palette
- **AND** the open conversation and the unsent reply remain unchanged

### Requirement: Operator behavior remains intact

Visual adaptation SHALL preserve existing routes, access restrictions, conversation selection, reply/internal-note modes, reply variables, attachments, shortcuts and order-action confirmation behavior. It SHALL preserve current status and failure information and SHALL NOT make restricted actions available through changes to their appearance.

#### Scenario: Reply workflow retains its behavior
- **WHEN** an agent selects a conversation, switches reply modes, inserts an order variable, attaches a file and sends a message using an existing send control
- **THEN** the same mode, variable value and attachment are submitted through the existing workflow
- **AND** the sent message appears in the conversation as before

#### Scenario: Order-action dialog preserves restrictions and feedback
- **WHEN** an agent opens an order action that is unavailable, in progress or refused
- **THEN** the existing restriction, progress or refusal remains visible and enforceable
- **AND** confirming an available action retains its existing confirmation and duplicate-submission protection

### Requirement: Controls remain usable with a keyboard and long content

In-scope controls SHALL keep their accessible names, visible keyboard focus and existing keyboard operation. Dialogs SHALL retain focus containment and return focus to their trigger on close. Long names, translated labels and order details SHALL remain readable or reachable without covering primary actions at supported viewport sizes. Newly introduced or changed text/control color pairs SHALL retain sufficient contrast in both palettes.

#### Scenario: Keyboard navigation through a dialog
- **WHEN** an agent opens an order-action dialog with the keyboard, moves among its controls and closes it using its existing keyboard behavior
- **THEN** the focused control is visible at every step, focus remains in the dialog while it is open, and closing returns focus to its trigger

#### Scenario: Narrow workspace with long content
- **WHEN** an agent opens a conversation containing a long customer name, long order lines and translated labels at a narrow supported viewport
- **THEN** the existing responsive layout keeps primary actions reachable and content scrollable or wrapped
- **AND** the theme does not introduce new clipping or overlapping controls

#### Scenario: Light and dark control states remain legible
- **WHEN** the workspace and Inclamo settings show normal text, secondary text, status indicators, focused controls and errors in each palette
- **THEN** the changed text and control color pairs meet the contrast criteria recorded in the visual acceptance checklist
- **AND** errors and selected states remain understandable through existing labels or indicators as well as color

### Requirement: Theme changes stay within the authenticated dashboard

The theme SHALL apply to the authenticated dashboard. It SHALL NOT change the appearance or behavior of the website widget, public help centre, survey, sign-in or superadmin surfaces. Routes and layouts within the dashboard that are not specially redesigned SHALL remain functional when they inherit the common colors and typography.

#### Scenario: Public and administration surfaces retain their appearance
- **WHEN** a user opens the website widget, public help centre, survey, sign-in page and superadmin separately from the dashboard
- **THEN** those surfaces retain their pre-change appearance and behavior

#### Scenario: Other dashboard pages remain usable
- **WHEN** an administrator opens contacts, inbox settings and the automation editor
- **THEN** those pages remain usable with the common foundation
- **AND** no page-specific layout replacement or missing control is introduced by the theme

### Requirement: Appearance is available without another product

The helpdesk's appearance SHALL be supplied by its own deployed assets. Loading or using the themed dashboard SHALL NOT require a running Twenty CRM, Builder, or external theme service.

#### Scenario: Other products are unreachable
- **WHEN** the user opens and operates the dashboard while Twenty CRM, Builder and external theme/font hosts are unreachable
- **THEN** the theme and required fonts load from the helpdesk's own assets or its bundled fallback
- **AND** helpdesk interactions continue normally

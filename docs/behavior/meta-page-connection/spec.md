# meta-page-connection

Behavior contract for this source revision.

What a workspace administrator is asked to grant, and what the inbox can do, when a Facebook Page and the Instagram account linked to it are connected through Meta login.

### Requirement: Page connection requests Instagram messaging permissions

When an administrator starts connecting a Facebook Page, the helpdesk SHALL request from Meta, in one login dialog, the Page messaging permissions and the Instagram messaging permissions `instagram_basic` and `instagram_manage_messages`. The request SHALL be the same from the inbox settings and from the onboarding inbox form.

#### Scenario: First-time client connects a Page with a linked Instagram account

- **WHEN** an administrator whose Meta user has never granted the app anything connects a Page that has a linked Instagram professional account and accepts all requested permissions
- **THEN** the created inbox receives direct messages sent to that Instagram account and delivers agent replies to them

#### Scenario: Connection from the onboarding form

- **WHEN** an administrator connects a Page from the onboarding inbox form
- **THEN** the same permissions are requested as from the inbox settings

### Requirement: Messenger works without Instagram

The helpdesk SHALL create a working Messenger inbox when the Instagram permissions are declined or the Page has no linked Instagram account.

#### Scenario: Administrator declines the Instagram permissions

- **WHEN** an administrator accepts the Page permissions and declines the Instagram permissions
- **THEN** the inbox is created, Messenger messages arrive and replies are delivered, and no error is shown for the missing Instagram access

#### Scenario: Page without Instagram

- **WHEN** an administrator connects a Page that has no linked Instagram account
- **THEN** the inbox is created and works for Messenger

### Requirement: Reauthorization requests the same permissions as connection

When an administrator reauthorizes an existing Page inbox, the helpdesk SHALL request the same permission set as a new connection, whether or not the inbox already has an Instagram account.

#### Scenario: Instagram added after the first connection

- **WHEN** an administrator reauthorizes a Page inbox that was connected before an Instagram account was linked to the Page, and accepts all permissions
- **THEN** direct messages of the linked Instagram account start arriving in that inbox

## Why
The integrated acceptance review found two concrete defects: direct anonymous access to draft help articles, and no current refund amount in the cancellation confirmation. These remain part of the authorized helpdesk acceptance work.

## What Changes
- Restrict unpublished public articles and preserve editor preview using a short-lived signed URL issued to an authenticated account member.
- Show the current refund effect before cancelling, with retry on preview failure and an explicit no-refund state.

## Capabilities
### New Capabilities
- `acceptance-ux-corrections`: Protected draft preview and cancellation confirmation clarity.
### Modified Capabilities
None.

## Impact
A small pinned editor patch, overlay controllers and public-controller extension, cancellation preview endpoint and dialog, targeted regressions and browser acceptance.

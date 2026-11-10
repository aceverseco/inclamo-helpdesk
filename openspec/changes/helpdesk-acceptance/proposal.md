## Why

The helpdesk features were developed on separate branches. Passing each feature's checks does not establish that the combined product works or that a shopper sees the correct outcome. Before a merchant pilot, the founder requested integrated functional, visual, permissions, onboarding and Shopify acceptance checks.

## What Changes

- Assemble the existing overlay features in an isolated integration branch and image.
- Repair regressions exposed by their combined tests, preserving existing behavior contracts and production data.
- Exercise real development-store orders and independently read back the results through the seeding app.
- Review the merchant and shopper interfaces, recovery from failures, and permission enforcement.
- Record competitor capability gaps and missing evidence; do not count test names or inherited Chatwoot features as verified acceptance.

## Capabilities

### New Capabilities

None. This is integration, corrective maintenance and acceptance tooling (`skip_specs: true`).

### Modified Capabilities

None. New onboarding behavior, finer staff permissions and AI order policy need separate behavior changes. A pending founder question about the AI authority model is not answered by this acceptance work.

## Impact

Overlay code, shims, fixtures, browser tests and test documentation. Use an isolated helpdesk database and tagged orders in a development Shopify store. The current dev instance and original feature worktrees remain separate. No pilot merchant dependency is required.

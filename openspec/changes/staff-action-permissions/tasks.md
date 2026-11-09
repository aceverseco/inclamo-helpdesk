## 1. Authorization
- [x] 1.1 Add explicit action grants with a compatible migration; verify model tests cover defaults, legacy grants, removal and account isolation.
- [x] 1.2 Add administrator-only per-action updates and response maps; verify invalid inputs, concurrency-safe updates and non-admin/cross-account rejection.
- [x] 1.3 Enforce individual and compound rights in the runner, previews, macros and retries; verify denied operations never mutate Shopify.

## 2. Interface and acceptance
- [x] 2.1 Build a reusable action-rights editor and update conversation controls; verify per-action visibility and failed-save rollback in frontend tests.
- [x] 2.2 Exercise address-only, refund denial, revocation and administrator behavior in the isolated browser/Shopify stack; independently verify the order results and cleanup.

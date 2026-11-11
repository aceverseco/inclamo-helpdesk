# Product repository

This public repository contains product source, tests, build tooling and finished
documentation. Keep internal plans, task state, reviews, operational inventories
and design prototypes in the maintainer's separate planning workspace. Do not
initialize an internal planning tree here or add links to private workspace paths.

Update `docs/behavior/<capability>/spec.md` with the corresponding code and tests
when product behavior changes. The public checkout must build and test without
access to internal plans. Generated review artifacts belong in ignored `build/`.

Before submitting changes, run:

```sh
node --test scripts/check-repository-boundary.test.mjs
node scripts/check-repository-boundary.mjs
node scripts/check-e2e-coverage.mjs
```

Run the backend, frontend and end-to-end checks relevant to implementation
changes, as described in `.github/workflows/ci.yml` and the product guides.
Do not remove requirements or add coverage exceptions just to hide a failing test.

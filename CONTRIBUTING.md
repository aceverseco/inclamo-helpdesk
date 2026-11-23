# Contributing

External pull requests are **not accepted** at this stage of the project.
Issues, bug reports and discussions are welcome.

Rules that apply to all code in this repository:

- Chatwoot's `enterprise/` directory is never used, patched or shipped here.
- Features live in our own code (`custom/` overlay and our services).
  Chatwoot's files are not edited. Where one has to behave differently, our
  file stands in for it and is recorded in `custom/CHATWOOT_FILES`; a line or
  two inside a screen that stays Chatwoot's may be a patch in `patches/`,
  within `patches/LIMIT`. `docs/chatwoot-files.md` says which to choose.

## Docs labels and release tags

The documentation, the FAQ and `llms.txt` of inclamo.com are updated from a queue of GitHub
issues, filled by two workflows: `docs-label` (a required check) and `docs-signal`. The script
behind both is `.github/scripts/docs_signal.py`.

### 1. Put one `docs:*` label on the pull request

| Label | When | What the docs agent does |
|---|---|---|
| `docs:new` | The merchant or their team sees something new: a screen, a setting, a channel, an action on an order | A new docs page, screenshots, a check of the FAQ and `llms.txt` |
| `docs:update` | The behaviour of something that exists changes: steps, names, limits, texts | An edit of the existing page and its screenshots |
| `docs:api` | The public API or a webhook changes: an endpoint, a field, the authorization | An edit of the API reference; together with `docs:new` / `docs:update` or alone |
| `docs:none` | Nothing visible: refactoring, tests, CI, internal services, dependencies | Nothing |

Example: "Let a store's staff member into the helpdesk from the store app" is `docs:new`: the
merchant gets a new way in.

Without a label the check `docs-label` fails. `docs:none` does not go with any other `docs:*`
label. The check runs again on every label change and every edit of the description; a draft is
not checked until it leaves draft.

### 2. For `docs:new`, `docs:update`, `docs:api`: fill the `## Docs` section of the description

The template of a new pull request has it:

```markdown
## Docs
- What the user sees: Store staff can open the helpdesk from the Shopify app without a separate login.
- Where: Shopify admin → Apps → Inclamo → "Open helpdesk"
- Availability: on deploy            <!-- on deploy | behind setting: <name> | not exposed -->
- Screenshots: yes — the Inclamo app home and the helpdesk inbox after sign-in
- API: none                          <!-- or: POST /api/v1/accounts/{id}/... changed field X -->
```

Write facts for the merchant, in English, one to three sentences. The docs agent takes the text
from here and does not make it up. The check fails without the section, without one of the five
lines, with an empty `What the user sees`, or with another `Availability` than the three above.

### 3. Merge as usual

After the merge of a pull request with `docs:new`, `docs:update` or `docs:api`:

- an issue `Docs: <title of the PR> (#N)` labelled `docs-pending` (and the PR's docs labels) opens
  in this repository, with the link to the PR, the merge commit, its `## Docs` section and the
  changed contract files (behaviour contracts, archived OpenSpec changes, API descriptions);
- the maintainer gets a Slack message with the link.

A second run for the same pull request opens no second issue.

### 4. Deployed to production: tag the deployed commit

Documentation is published only about what is deployed.

**Helpdesk.** The version lives in `custom/INCLAMO_VERSION`. Before a deployment raise it in
its own pull request (`docs:none`) and merge it. Then tag the commit you deploy:

```sh
git tag -a v0.2.0 <sha-of-the-deployed-commit> -m "Production 2026-11-25"
git push origin v0.2.0
```

The tag must be `v` + `custom/INCLAMO_VERSION`, or the `Image` workflow fails. The tag publishes
the image to GHCR; that image is what goes on the server
([Releasing a version](docs/install.md#releasing-a-version)).

On the tag, every open `docs-pending` issue whose merge commit the tag contains gets the label
`released` and the comment `Released in <tag>`; the others wait for the next tag. Once a week the
docs agent opens a pull request on the site for the `released` issues (the others it prepares as a
draft only); when that pull request is merged, it closes the issue with a link to it and removes
`docs-pending`.

### Common cases

- **A feature behind a setting that is off by default:** `docs:new`,
  `Availability: behind setting: <name>`. The docs describe the setting too.
- **A fix of a bug the merchant saw:** `docs:update` if the documented behaviour changes,
  otherwise `docs:none`.
- **One pull request changes both the interface and the API:** `docs:update` + `docs:api`.
- **The label was forgotten before the merge:** put it on the merged pull request and run the
  workflow by hand: `gh workflow run docs-signal -f pr=<N>` (or Actions → docs-signal → Run
  workflow).

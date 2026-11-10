# Preserved workspace, 2026-11-10

This branch preserves 300 modified/new source and evidence files from the
working tree based on `2052c27`. Generated dependencies, local environment files
and build output are excluded by the repository's existing ignore rules.
The original working directory was left untouched.

Publication sanitation replaces recorded order-status URLs in test fixtures
with a wholly synthetic example URL, including the path and authentication
query. No original customer-access key is retained in those fixture links.

This is **unfinished work**, not a release branch. It includes the completed
historical Twenty theme evidence, the newer Inclamo branded workspace draft,
its prototype, and earlier uncommitted feature work. The branded workspace's
remaining tasks and final visual acceptance are still open.

Use [feat/helpdesk-acceptance](https://github.com/aceverseco/inclamo-helpdesk/tree/feat/helpdesk-acceptance)
for the integrated functional baseline and service integration instructions.
Before applying this design there, reconcile duplicated feature changes,
patch numbering and upstream patch seams; run component and isolated synthetic
visual acceptance on that combined tree. Do not overwrite the integrated
branch with this older workspace or deploy this snapshot as a verified build.

#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
project=${SUPPORT_PROJECT:-inclamo-workspace-support}
output=${E2E_OUTPUT:-"$root/workspace-support-output"}
mkdir -p "$output"
docker build -t inclamo-workspace-support-browser -f "$root/e2e/workspace-support/Dockerfile.browser" "$root"
docker run --rm --init --ipc=host --network "${project}_default" -v "$output:/out" -e E2E_OUTPUT=/out inclamo-workspace-support-browser npx playwright test --config playwright.workspace-support.config.mjs "$@"

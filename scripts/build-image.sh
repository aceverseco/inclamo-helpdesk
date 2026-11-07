#!/bin/sh
# Builds the Inclamo Helpdesk image with Chatwoot's own Dockerfile from the
# assembled tree. usage: scripts/build-image.sh [image-name]
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
version=$(cat "$here/custom/INCLAMO_VERSION")
tag=$(cat "$here/custom/CHATWOOT_VERSION")
image=${1:-"inclamo-helpdesk:$version-cw${tag#v}"}

"$here/scripts/assemble.sh" "$here/build/chatwoot"
docker build --file "$here/build/chatwoot/docker/Dockerfile" --tag "$image" "$here/build/chatwoot"
echo "built $image"

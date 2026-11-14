#!/bin/sh
# Assembles the tree our image and our tests are built from:
#   Chatwoot Community Edition at the pinned tag
#   + the seam patches in patches/ (each must apply cleanly)
#   + the overlay in custom/ and the two loader files in shims/.
#
# usage: scripts/assemble.sh [target-dir]      (default: build/chatwoot)
# A target that already holds a Chatwoot checkout at the pinned tag is reused.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
tag=$(cat "$here/custom/CHATWOOT_VERSION")
target=${1:-"$here/build/chatwoot"}

if [ ! -d "$target/.git" ]; then
  mkdir -p "$(dirname "$target")"
  git clone --quiet --depth 1 --branch "$tag" https://github.com/chatwoot/chatwoot.git "$target"
fi

cd "$target"
found="v$(cat VERSION_CW 2>/dev/null || echo unknown)"
if [ "$found" != "$tag" ]; then
  echo "assemble: $target holds Chatwoot $found, expected $tag" >&2
  exit 1
fi

# Back to the pristine tag, keeping installed dependencies.
git reset --quiet --hard HEAD
git clean --quiet -fd -e vendor/bundle -e node_modules
rm -rf custom

# Community Edition, the same way upstream builds its own -ce image.
rm -rf enterprise spec/enterprise
printf '\nENV CW_EDITION="ce"\n' >> docker/Dockerfile

# Screens the overlay stands in for: Chatwoot's own file is not patched, so a
# change of theirs would pass unnoticed. Stop when one differs from the record.
if [ -f "$here/patches/overlay-screens.txt" ]; then
  grep -v '^#' "$here/patches/overlay-screens.txt" | while read -r blob path ours; do
    [ -n "$blob" ] || continue
    if [ ! -f "$here/$ours" ]; then
      echo "assemble: $ours, which stands in for $path, is missing" >&2
      exit 1
    fi
    found_blob=$(git rev-parse --quiet --verify "HEAD:$path" || echo missing)
    if [ "$found_blob" != "$blob" ]; then
      echo "assemble: Chatwoot $tag changed $path, which $ours stands in for (patches/overlay-screens.txt)" >&2
      exit 1
    fi
  done
fi

# Seam patches. A patch that no longer applies stops the build.
for patch in "$here"/patches/*.patch; do
  [ -e "$patch" ] || continue
  if ! git apply --check "$patch"; then
    echo "assemble: patch does not apply to Chatwoot $tag: $(basename "$patch")" >&2
    exit 1
  fi
  git apply "$patch"
  echo "assemble: applied $(basename "$patch")"
done

# The overlay and its two loader files.
cp -R "$here/custom" custom
cp -R "$here/shims/." .

echo "assemble: Chatwoot $tag + overlay $(cat "$here/custom/INCLAMO_VERSION") in $target"

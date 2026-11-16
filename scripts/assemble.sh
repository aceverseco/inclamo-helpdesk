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

# Chatwoot files the overlay stands in for (custom/CHATWOOT_FILES). Each one is
# checked against the recorded blob id: when Chatwoot changes such a file, the
# build stops instead of shipping our stand-in over a change nobody read.
#   two columns  - shims/<path> takes the file's place; Chatwoot's own file is
#                  kept beside it, untouched, as <name>.chatwoot.<ext>, so the
#                  stand-in can build on it;
#   three columns - the file stays where it is and the named overlay file is
#                  used in its place by other means (a view path, a module).
files="$here/custom/CHATWOOT_FILES"
replaced=$(mktemp)
trap 'rm -f "$replaced"' EXIT
grep -v '^#' "$files" | while read -r blob path ours; do
  [ -n "$blob" ] || continue
  stand_in=${ours:-shims/$path}
  if [ ! -f "$here/$stand_in" ]; then
    echo "assemble: $stand_in, which stands in for $path, is missing" >&2
    exit 1
  fi
  found_blob=$(git rev-parse --quiet --verify "HEAD:$path" || echo missing)
  if [ "$found_blob" != "$blob" ]; then
    echo "assemble: Chatwoot $tag changed $path, which $stand_in stands in for (custom/CHATWOOT_FILES)" >&2
    exit 1
  fi
  if [ -z "$ours" ]; then
    echo "$path" >> "$replaced"
  fi
done

# A file of shims/ may take the place of a Chatwoot file only when recorded.
(cd "$here/shims" && find . -type f | sed 's|^\./||') | while read -r path; do
  if git cat-file -e "HEAD:$path" 2>/dev/null && ! grep -qxF "$path" "$replaced"; then
    echo "assemble: shims/$path would overwrite a Chatwoot file that custom/CHATWOOT_FILES does not record" >&2
    exit 1
  fi
done

while read -r path; do
  mv "$path" "${path%.*}.chatwoot.${path##*.}"
done < "$replaced"

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

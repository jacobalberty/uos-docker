#!/usr/bin/env bash
# Print the next free tag for a UniFi OS version:  <version>, then <version>-1, <version>-2, ...
# usage: next-tag.sh <image-without-tag> <unifi-os-version>
# Requires an authenticated docker/buildx. A registry error other than "not found" aborts,
# so an outage or bad credentials can never be mistaken for "tag is free".
set -euo pipefail
image=${1:?usage: next-tag.sh <image> <version>}
version=${2:?usage: next-tag.sh <image> <version>}

exists() {
  local err
  if err=$(docker buildx imagetools inspect "$image:$1" 2>&1 >/dev/null); then
    return 0
  fi
  if grep -qiE 'not found|manifest unknown|name unknown|404' <<<"$err"; then
    return 1
  fi
  echo "registry lookup for $image:$1 failed: $err" >&2
  exit 2
}

if ! exists "$version"; then
  echo "$version"
  exit 0
fi
n=1
while exists "$version-$n"; do
  n=$((n + 1))
done
echo "$version-$n"

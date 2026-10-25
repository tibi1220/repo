#!/usr/bin/env bash
# Builds the APT repo into _site/.
#
# For every repo listed in tweaks.json it downloads the .deb assets of all
# published (non-draft, non-prerelease) releases and copies the repo's
# depiction/ folder, then generates Packages*, Release, and signs it.
#
# Requires: gh (authenticated), jq, dpkg-scanpackages, dpkg-deb, bzip2, gzip,
# xz, zstd, openssl, gpg.
#
# Env:
#   REQUIRE_SIGNING=1  fail instead of warn when the signing key is unavailable
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
OUT=$ROOT/_site
WORK=$ROOT/.work

rm -rf "$OUT" "$WORK"
mkdir -p "$OUT/debs" "$OUT/depictions" "$WORK"
trap 'rm -rf "$WORK"' EXIT

cp -R static/. "$OUT/"

for repo in $(jq -r '.tweaks[].repo' tweaks.json); do
  echo "==> $repo"
  dl=$WORK/dl/${repo//\//_}
  mkdir -p "$dl"

  # Download every .deb attached to a published release
  gh api --paginate "repos/$repo/releases" \
    --jq '.[] | select((.draft or .prerelease) | not) | .assets[] | select(.name | endswith(".deb")) | "\(.id) \(.name)"' |
    while read -r id name; do
      echo "  deb  $name"
      gh api -H 'Accept: application/octet-stream' "repos/$repo/releases/assets/$id" > "$dl/$name"
    done

  # File debs under a canonical name so assets from different repos can't collide
  for deb in "$dl"/*.deb; do
    [[ -e $deb ]] || continue
    pkg=$(dpkg-deb -f "$deb" Package)
    ver=$(dpkg-deb -f "$deb" Version)
    arch=$(dpkg-deb -f "$deb" Architecture)
    dest=$OUT/debs/$pkg/${pkg}_${ver#*:}_${arch}.deb
    if [[ -e $dest ]]; then
      echo "error: duplicate package $pkg $ver ($arch) from $repo" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$dest")"
    mv "$deb" "$dest"
  done

  # Depiction lives in the tweak repo's depiction/ folder, keyed by the control file's Package
  src=$WORK/src/${repo//\//_}
  gh repo clone "$repo" "$src" -- --quiet --depth 1 --filter=blob:none --sparse
  git -C "$src" sparse-checkout set --no-cone /control /depiction/
  if [[ -d $src/depiction && -f $src/control ]]; then
    pkg=$(sed -n 's/^Package:[[:space:]]*//p' "$src/control" | head -n 1)
    if [[ -n $pkg ]]; then
      echo "  depiction  $pkg"
      cp -R "$src/depiction" "$OUT/depictions/$pkg"
    fi
  fi
done

cd "$OUT"

dpkg-scanpackages --multiversion debs /dev/null > Packages
bzip2 -kf9 Packages
gzip -kf9n Packages
xz -kf9 Packages
zstd -qkf19 Packages

indexes=(Packages Packages.bz2 Packages.gz Packages.xz Packages.zst)
{
  cat "$ROOT/config/release-header"
  echo "Date: $(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S UTC')"
  for algo in MD5Sum:md5 SHA1:sha1 SHA256:sha256 SHA512:sha512; do
    echo "${algo%%:*}:"
    for f in "${indexes[@]}"; do
      printf ' %s %s %s\n' \
        "$(openssl dgst -"${algo#*:}" -r "$f" | cut -d ' ' -f 1)" \
        "$(wc -c < "$f" | tr -d ' ')" \
        "$f"
    done
  done
} > Release

fpr=$(tr -d '[:space:]' < "$ROOT/config/signing-key")
if [[ -n $fpr ]] && gpg --batch --list-secret-keys "$fpr" > /dev/null 2>&1; then
  gpg --batch --yes --local-user "$fpr" --armor --detach-sign -o Release.gpg Release
  gpg --batch --yes --local-user "$fpr" --clearsign -o InRelease Release
  echo "==> Signed Release with $fpr"
elif [[ ${REQUIRE_SIGNING:-0} == 1 ]]; then
  echo "error: signing key ${fpr:-(none in config/signing-key)} not available" >&2
  exit 1
else
  echo "warning: signing key not available, Release is unsigned" >&2
fi

echo "==> Built $(grep -c '^Package:' Packages || true) package entries into _site/"

#!/usr/bin/env bash
set -euo pipefail

manifest="${1:-com.obsproject.Studio.Plugin.Teleport.yaml}"
app_dir="$(cd "$(dirname "$manifest")" && pwd)"
manifest_path="${app_dir}/$(basename "$manifest")"
tmpdir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

repo_url="$(
  awk '
    /url:[[:space:]]*https:\/\/github.com\/fzwoch\/obs-teleport.git/ {
      sub(/^[[:space:]]*url:[[:space:]]*/, "")
      gsub(/["'\'']/, "")
      print
      exit
    }
  ' "$manifest_path"
)"

tag="$(
  awk '
    /url:[[:space:]]*https:\/\/github.com\/fzwoch\/obs-teleport.git/ { found = 1; next }
    found && /^[[:space:]]*tag:/ {
      sub(/^[[:space:]]*tag:[[:space:]]*/, "")
      gsub(/["'\'']/, "")
      print
      exit
    }
  ' "$manifest_path"
)"

if [[ -z "$repo_url" || -z "$tag" ]]; then
  echo "Could not find obs-teleport git source and tag in ${manifest_path}" >&2
  exit 1
fi

version="${tag#v}"
generator_version="${FLATPAK_GO_MOD_VERSION:-v0.1.0}"

git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" "$repo_url" "$tmpdir/obs-teleport"

(
  cd "$tmpdir"
  go run "github.com/dennwc/flatpak-go-mod@${generator_version}" "$tmpdir/obs-teleport"
)

cp "$tmpdir/modules.txt" "$app_dir/modules.txt"
sed "s/main.version=[^\" ]*/main.version=${version}/" "$manifest_path" > "$tmpdir/manifest.versioned.yaml"
sed 's/^/      /' "$tmpdir/go.mod.yml" > "$tmpdir/go-sources.indented.yml"

awk -v block="$tmpdir/go-sources.indented.yml" '
  /^[[:space:]]*#[[:space:]]*BEGIN generated Go modules/ {
    print
    while ((getline line < block) > 0) {
      print line
    }
    close(block)
    in_generated = 1
    next
  }
  /^[[:space:]]*#[[:space:]]*END generated Go modules/ {
    in_generated = 0
    print
    next
  }
  !in_generated {
    print
  }
' "$tmpdir/manifest.versioned.yaml" > "$tmpdir/manifest.updated.yaml"

chmod --reference="$manifest_path" "$tmpdir/manifest.updated.yaml"
mv "$tmpdir/manifest.updated.yaml" "$manifest_path"

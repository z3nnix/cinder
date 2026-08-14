#!/usr/bin/env bash

set -euo pipefail

repo="z3nnix/cinder"

if [[ $EUID -ne 0 ]]; then
    echo "err: installer must be run as root"
    exit 1
fi

echo ":: wait few seconds.."

url="$(
    curl -fsSL "https://api.github.com/repos/${repo}/releases?per_page=1" |
        grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*/cinder"' |
        head -n1 |
        sed -E 's/.*"([^"]+)"$/\1/'
)"

[ -n "$url" ] || { echo "er: latest release asset not found" >&2; exit 1; }

curl -fsSL "$url" -o /usr/bin/cinder
chmod +x /usr/bin/cinder
echo ":: installed: $(/usr/bin/cinder --version)"

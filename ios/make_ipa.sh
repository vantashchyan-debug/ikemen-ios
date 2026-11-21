#!/usr/bin/env bash
# Linux/macOS: add your game to the engine .ipa built by GitHub Actions.
#
#   ios/make_ipa.sh <Ikemen_GO-engine.ipa | artifact.zip> [game_dir] [out.ipa]
#
# game_dir defaults to ../ikemen (next to this repo), out to ./Ikemen_GO.ipa
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
IN="${1:?usage: $0 <engine.ipa|artifact.zip> [game_dir] [out.ipa]}"
GAME="${2:-$HERE/../../ikemen}"
OUT="${3:-$PWD/Ikemen_GO.ipa}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# GitHub wraps artifacts in a .zip: dig the .ipa out of it.
if [[ "$IN" == *.zip ]]; then
	python3 -I -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$IN" "$TMP/artifact"
	IN="$(find "$TMP/artifact" -name '*.ipa' | head -1)"
	[ -n "$IN" ] || { echo "no .ipa inside the artifact" >&2; exit 1; }
fi

python3 -I "$HERE/package_game.py" --ipa "$IN" --game "$GAME" --out "$OUT"
echo
echo "Install with Sideloadly/AltStore: $OUT"

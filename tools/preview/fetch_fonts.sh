#!/usr/bin/env bash
# Downloads the fonts the UI preview renderer maps Roblox font families to.
# Nunito is SIL OFL 1.1 (https://github.com/google/fonts/tree/main/ofl/nunito).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
font_dir="$repo_root/.tools/fonts"
mkdir -p "$font_dir"

fetch() {
	local url="$1" dest="$font_dir/$2"
	if [[ -s "$dest" ]]; then
		echo "have $2"
		return
	fi
	curl -fsSL --retry 3 -o "$dest.part" "$url"
	mv "$dest.part" "$dest"
	echo "fetched $2"
}

fetch "https://github.com/google/fonts/raw/main/ofl/nunito/Nunito%5Bwght%5D.ttf" "Nunito[wght].ttf"
fetch "https://github.com/google/fonts/raw/main/ofl/nunito/OFL.txt" "Nunito-OFL.txt"

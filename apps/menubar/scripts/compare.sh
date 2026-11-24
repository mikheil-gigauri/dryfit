#!/usr/bin/env bash
# The app next to its approved mock (docs/design/dryfit-states.html): renders the mock's states (Chromium)
# and the app's scenes of the same name (Tests/DryfitMenuTests/Snapshots.swift), then writes
# mock | app | diff for each, light and dark, and prints the share of pixels that differ.
#
#   npm run menubar:compare -- [state …]     every scene the app draws when none is given
#   MOCK=skip npm run menubar:compare -- …   reuse the last mock renders
#
# Output in apps/menubar/.build/compare/{mock,app,diff}. A state is done when what's left is text
# antialiasing and data the app computes differently; anything else is a deviation to fix or to list.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=.build/compare
mkdir -p "$OUT/mock" "$OUT/app" "$OUT/diff"
xcrun swiftc -O scripts/compare.swift -o "$OUT/compare" 2>/dev/null
scenes=$(IFS=,; echo "$*")
rm -f "$OUT"/app/*.png
env DRYFIT_SNAPSHOTS="$PWD/$OUT/app" ${scenes:+DRYFIT_SCENES="$scenes"} xcrun swift test --filter Snapshots >"$OUT/test.log" 2>&1 \
  || { tail -30 "$OUT/test.log" >&2; exit 1; }
ls "$OUT"/app/*.light.png >/dev/null 2>&1 || { echo "compare: the app drew no scene named ${scenes:-…}" >&2; exit 1; }
if [[ -z "$scenes" ]]; then
  set -- $(ls "$OUT"/app/*.light.png | xargs -n1 basename | sed 's/\.light\.png$//')
  # States the mock draws that no app scene shows yet: unchecked until a LiveScenes scene has their id.
  missing=$(grep -o '<section id="[^"]*"' ../../docs/design/dryfit-states.html | sed 's/.*id="//; s/"$//' \
    | while read -r id; do [[ -f "$OUT/app/$id.light.png" ]] || printf '%s ' "$id"; done)
fi
if [[ "${MOCK:-}" != skip ]]; then node scripts/mock-render.mjs "$OUT/mock" "$@" >/dev/null; fi
for state in "$@"; do
  for theme in light dark; do
    name="$state.$theme"
    if [[ ! -f "$OUT/app/$name.png" ]]; then printf '%-22s no app scene\n' "$name"; continue; fi
    if [[ ! -f "$OUT/mock/$name.png" ]]; then printf '%-22s no mock state\n' "$name"; continue; fi
    printf '%-22s %s\n' "$name" "$("$OUT/compare" "$OUT/mock/$name.png" "$OUT/app/$name.png" "$OUT/diff/$name.png")"
  done
done
echo "mock | app | diff images: apps/menubar/$OUT/diff/"
if [[ -n "${missing:-}" ]]; then echo "no app scene yet for: $missing"; fi

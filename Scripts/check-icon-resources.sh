#!/bin/zsh
# Regenerates icon resources into a temporary catalog and byte-compares them with the committed catalog.
# Default mode never writes committed resources; `--update` is the only way to intentionally regenerate them.
set -euo pipefail
ROOT="${0:A:h:h}"
: ${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}; export DEVELOPER_DIR
CATALOG="${ICON_CATALOG:-$ROOT/Resources/Assets.xcassets}"

UPDATE=0
case "${1:-}" in
  "") ;;
  --update) UPDATE=1 ;;
  *)
    printf 'Usage: %s [--update]\n' "${0:t}" >&2
    exit 2
    ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
GENERATED="$WORK/Assets.xcassets"
xcrun swift "$ROOT/Scripts/generate-icons.swift" "$GENERATED"

list_files() {
  (cd "$1" && find . -type f ! -name .DS_Store | sed 's|^\./||' | LC_ALL=C sort)
}

if (( UPDATE )); then
  mkdir -p "$CATALOG"
  list_files "$GENERATED" | while IFS= read -r relative; do
    mkdir -p "$CATALOG/${relative:h}"
    cp "$GENERATED/$relative" "$CATALOG/$relative"
  done
  printf 'Updated icon resources in %s\n' "$CATALOG"
  exit 0
fi

DRIFT=0
list_files "$GENERATED" > "$WORK/generated.txt"
while IFS= read -r relative; do
  if [[ ! -f "$CATALOG/$relative" ]]; then
    printf 'Icon resource missing: %s\n' "$relative" >&2
    DRIFT=1
  elif ! cmp -s "$GENERATED/$relative" "$CATALOG/$relative"; then
    printf 'Icon resource drift: %s\n' "$relative" >&2
    DRIFT=1
  fi
done < "$WORK/generated.txt"
list_files "$CATALOG" | while IFS= read -r relative; do
  if ! grep -Fxq -- "$relative" "$WORK/generated.txt"; then
    printf 'Icon resource not produced by generator: %s\n' "$relative" >&2
    DRIFT=1
  fi
done
if (( DRIFT )); then
  printf 'Committed icon resources differ from Scripts/generate-icons.swift; run Scripts/build-app.sh --update to regenerate intentionally.\n' >&2
  exit 1
fi
printf 'Icon resources match generator output.\n'

#!/usr/bin/env bash
# Renders the App Store screenshots from the real SwiftUI views and drops
# them in tasks/screenshots/. See tasks/screenshots.md.
#
#   scripts/screenshots.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/tasks/screenshots"
# The test host is sandboxed; its tmp dir is inside the app container.
RENDERED="$HOME/Library/Containers/com.chaninlaw.Mewt/Data/tmp/MewtScreenshots"

mkdir -p "$OUT"
find "$RENDERED" -name '*.png' -delete 2>/dev/null || true

echo "Rendering…"
TEST_RUNNER_MEWT_SCREENSHOTS=1 xcodebuild test \
  -project "$ROOT/Mewt.xcodeproj" \
  -scheme Mewt \
  -destination 'platform=macOS' \
  -only-testing:MewtTests/ScreenshotTests \
  -quiet

shopt -s nullglob
shots=("$RENDERED"/*.png)
if (( ${#shots[@]} == 0 )); then
  echo "No screenshots were rendered (looked in $RENDERED)" >&2
  exit 1
fi

status=0
for f in "${shots[@]}"; do
  name="$(basename "$f")"
  cp "$f" "$OUT/$name"
  info="$(sips -g pixelWidth -g pixelHeight -g hasAlpha -g space "$OUT/$name")"
  w="$(awk '/pixelWidth/ {print $2}' <<<"$info")"
  h="$(awk '/pixelHeight/ {print $2}' <<<"$info")"
  alpha="$(awk '/hasAlpha/ {print $2}' <<<"$info")"
  space="$(awk '/space/ {print $2}' <<<"$info")"
  if [[ "$w" == 2880 && "$h" == 1800 && "$alpha" == no && "$space" == RGB ]]; then
    echo "✓ $name  ${w}×${h} RGB no-alpha"
  else
    echo "✗ $name  ${w}×${h} alpha=$alpha space=$space" >&2
    status=1
  fi
done
echo "Saved to $OUT"
exit $status

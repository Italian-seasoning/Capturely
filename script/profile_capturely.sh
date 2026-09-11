#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_EXECUTABLE="$ROOT/dist/Capturely.app/Contents/MacOS/Capturely"
PROFILE_DIR="$ROOT/dist/Profiles"
TIME_LIMIT="${1:-30s}"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ "$TIME_LIMIT" != *s ]]; then
  TIME_LIMIT="${TIME_LIMIT}s"
fi

mkdir -p "$PROFILE_DIR"

PID="$(pgrep -f "$APP_EXECUTABLE" | head -1 || true)"
if [[ -z "$PID" ]]; then
  echo "Capturely is not running from $APP_EXECUTABLE" >&2
  echo "Launch it first with: open \"$ROOT/dist/Capturely.app\"" >&2
  exit 1
fi

PREFIX="$PROFILE_DIR/capturely-$STAMP"

echo "Profiling Capturely pid $PID for $TIME_LIMIT"
ps -p "$PID" -o pid,pcpu,pmem,etime,state,command | tee "$PREFIX.ps-before.txt"

sample "$PID" 8 -file "$PREFIX.sample.txt" >/dev/null

xcrun xctrace record \
  --template 'Time Profiler' \
  --attach "$PID" \
  --time-limit "$TIME_LIMIT" \
  --output "$PREFIX.timeprofiler.trace" \
  --quiet \
  --no-prompt

ps -p "$PID" -o pid,pcpu,pmem,etime,state,command | tee "$PREFIX.ps-after.txt" || true
xcrun xctrace export --input "$PREFIX.timeprofiler.trace" --toc > "$PREFIX.timeprofiler-toc.xml"

echo "Wrote:"
echo "  $PREFIX.sample.txt"
echo "  $PREFIX.timeprofiler.trace"
echo "  $PREFIX.timeprofiler-toc.xml"

#!/usr/bin/env bash
# Build index.pdf from index.md using pandoc + headless Google Chrome.
# Usage: ./build-pdf.sh                        -> index.md      -> index.pdf
#        ./build-pdf.sh private_cv.md          -> private_cv.md -> private_cv.pdf
#        ./build-pdf.sh private_cv.md out.pdf  -> explicit output name
set -euo pipefail
cd "$(dirname "$0")"

IN="${1:-index.md}"
OUT="${2:-${IN%.md}.pdf}"
STYLE="$(sed -n 's/^style:[[:space:]]*//p' _config.yml)"
STYLE="${STYLE:-davewhipp}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# Light preprocessing:
#  1. drop HTML comments (so their "-->" isn't mistaken for an arrow),
#  2. fix the bare email href,
#  3. turn "-->" into a real arrow,
#  4. use en dashes for ranges inside the backtick dates.
perl -CSD -0pe 's/<!--.*?-->//gs;
           s/href="dmckenzie\@mines.edu"/href="mailto:dmckenzie\@mines.edu"/g;
           s/\s*-->\s*/ \x{2192} /g;
           s/`([^`]*)`/ my $d=$1; $d =~ s{--}{\x{2013}}g; "`$d`" /ge;' \
  "$IN" > "$BUILD/index.md"

# Markdown -> HTML fragment. native_divs is disabled so <div id="webaddress">
# stays raw HTML instead of getting wrapped in <p>.
pandoc "$BUILD/index.md" \
  -f markdown-native_divs-native_spans \
  -t html5 \
  -o "$BUILD/body.html"

cat > "$BUILD/index.html" <<HTML
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Daniel McKenzie's CV</title>
  <link href="media/${STYLE}-print.css" rel="stylesheet">
  <link href="media/pdf-tweaks.css" rel="stylesheet">
</head>
<body>
  <div id="main">
    <div id="content">
$(cat "$BUILD/body.html")
    </div>
  </div>
</body>
</html>
HTML
cp -R media "$BUILD/media"

# Chrome sometimes fails to exit after writing the PDF, so run it in the
# background and stop it once the file has appeared.
rm -f "$PWD/$OUT"
"$CHROME" --headless=new --disable-gpu --disable-extensions --no-first-run \
  --user-data-dir="$BUILD/chrome-profile" \
  --no-pdf-header-footer \
  --print-to-pdf="$PWD/$OUT" \
  "file://$BUILD/index.html" >/dev/null 2>&1 &
CHROME_PID=$!
for _ in $(seq 1 60); do
  if [ -s "$PWD/$OUT" ]; then sleep 1; break; fi
  if ! kill -0 "$CHROME_PID" 2>/dev/null; then break; fi
  sleep 1
done
kill "$CHROME_PID" 2>/dev/null || true
wait "$CHROME_PID" 2>/dev/null || true
[ -s "$PWD/$OUT" ] || { echo "Chrome did not produce $OUT" >&2; exit 1; }

echo "Wrote $OUT"

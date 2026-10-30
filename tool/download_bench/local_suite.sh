#!/bin/bash
# שחזור מקומי ל-#149: שרת מקומי עם תקרת קצב לכל חיבור, ומולו curl ומסלולי הכלי.
# usage: tool/download_bench/local_suite.sh <range|norange> <perConnBytesPerSec>
# הקצבים מודפסים ב-MiB/s (חלוקה ב-1,048,576). CURL= לנתיב curl אחר.
B="$(cd "$(dirname "$0")" && pwd)"
WORK="${BENCH_WORK:-${TMPDIR:-/tmp}/download_bench}"; DL="$WORK/dl"
MODE=$1; RATE=$2
BIG=268435456; SMALL=73400320
mkdir -p "$WORK"; cd "$B"
LOG="$WORK/server_${MODE}_${RATE}.log"
dart run bin/server.dart 8149 "$MODE" "$RATE" $BIG $SMALL > "$LOG" 2>&1 &
SPID=$!
for i in $(seq 1 120); do grep -q READY "$LOG" 2>/dev/null && break; sleep 1; done
SHA_BIG=$(grep -o "SHA $BIG [0-9a-f]*" "$LOG" | cut -d" " -f3)
SHA_SMALL=$(grep -o "SHA $SMALL [0-9a-f]*" "$LOG" | cut -d" " -f3)
U="http://127.0.0.1:8149/f/$BIG/big.bin"
C="${CURL:-curl}"
echo "### mode=$MODE perConnRate=$RATE"
echo "--- curl probe (as assistant: --range 0-0)"
"$C" -s -o /dev/null -r 0-0 --max-filesize 1024 -w 'probe http=%{http_code}\n' "$U"
echo "--- curl single"; "$B/curl_bench.sh" single "$U" $BIG "$SHA_BIG" "$DL/c1" | grep SUMMARY
if [ "$MODE" = range ]; then
  echo "--- curl 4 segments"; "$B/curl_bench.sh" seg4 "$U" $BIG "$SHA_BIG" "$DL/c4" | grep SUMMARY
fi
for c in 1 2 4; do
  echo "--- tool PatchDownloader maxConnections=$c (1 file)"
  rm -rf "$DL/pd"; mkdir -p "$DL/pd"
  dart run bin/bench.dart pd "$DL/pd" $c "$U,$BIG,$SHA_BIG" 2>&1 | grep -E "REQ#|DONE|SUMMARY"
done
echo "--- tool otzaria_downloads.downloadFile (installer path)"
rm -rf "$DL/df"; mkdir -p "$DL/df"
dart run bin/bench.dart df "$DL/df" "$U,$BIG,$SHA_BIG" 2>&1 | grep -E "SUMMARY"
echo "--- tool scheduler: 1 big + 3 x 70MiB, maxConnections=2 (exporter config)"
rm -rf "$DL/m"; mkdir -p "$DL/m"
dart run bin/bench.dart pd "$DL/m" 2 "$U,$BIG,$SHA_BIG" \
  "http://127.0.0.1:8149/f/$SMALL/s1.bin,$SMALL,$SHA_SMALL" \
  "http://127.0.0.1:8149/f/$SMALL/s2.bin,$SMALL,$SHA_SMALL" \
  "http://127.0.0.1:8149/f/$SMALL/s3.bin,$SMALL,$SHA_SMALL" 2>&1 | grep -E "DONE|SUMMARY|END#"
rm -rf "$DL"
kill $SPID 2>/dev/null
if command -v taskkill >/dev/null; then taskkill //F //T //PID $SPID >/dev/null 2>&1; fi
echo "server log: $LOG"

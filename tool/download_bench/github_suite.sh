#!/bin/bash
# מדידה מול GitHub ל-#149: נכס ציבורי (בלי טוקן); כתובות CDN נחתכות לפני ההדפסה.
# usage: tool/download_bench/github_suite.sh   (קצבים ב-MiB/s; CURL= לנתיב curl אחר)
B="$(cd "$(dirname "$0")" && pwd)"
DL="${BENCH_WORK:-${TMPDIR:-/tmp}/download_bench}/gh"
U="https://github.com/Otzaria/otzaria/releases/download/0.9.98.2%2B807/app-release.apk"
SIZE=107427011; SHA=5acf62dc7eb3a86443d5e62ea783e1056d9bdd26ad3eb51b3014e17dda3080b8
date -u +"### github run %Y-%m-%dT%H:%M:%SZ"
"${CURL:-curl}" --version | head -1
echo "--- probe (-r 0-0)"; "$B/probe_curl.sh" "$U" 0-0 | grep -iE "^HTTP/|content-range|final_http"
echo "--- curl single"; "$B/curl_bench.sh" single "$U" $SIZE $SHA "$DL/c1" | grep SUMMARY
echo "--- curl 4 segments"; "$B/curl_bench.sh" seg4 "$U" $SIZE $SHA "$DL/c4" | grep SUMMARY
cd "$B"
for c in 2 4; do
  echo "--- tool PatchDownloader maxConnections=$c"; rm -rf "$DL/pd"; mkdir -p "$DL/pd"
  dart run bin/bench.dart pd "$DL/pd" $c "$U,$SIZE,$SHA" 2>&1 | grep -E "SUMMARY"
done
echo "--- tool downloadFile"; rm -rf "$DL/df"; mkdir -p "$DL/df"
dart run bin/bench.dart df "$DL/df" "$U,$SIZE,$SHA" 2>&1 | grep SUMMARY
rm -rf "$DL"

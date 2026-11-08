#!/bin/bash
# מדידת שלבי העדכון במחשב הלא־מקוון, בקוד הייצור (LibraryUpdateApplier), על
# עותק של seforim.db. המסד המקורי והמראה נקראים בלבד.
# usage: tool/download_bench/apply_suite.sh <label> <mirror/library dir> <seforim.db> <workRoot>
# workRoot: תיקייה על הכונן שעליו המסד של אוצריא (שם נוצרת run_<pid>_<n> ונמחקת).
# ROUTES (ברירת מחדל "delta;full"; גם auto) ו-RUNS=3. סדר המסלולים מתחלף בכל
# סבב. JSON (ברירת מחדל: workRoot/apply-results.jsonl). אוצריא חייבת להיות סגורה.
# ZSTD_LIBRARY_PATH: בלי הגדרה נלקחת libzstd של Git for Windows אם קיימת.
set -u -o pipefail
B="$(cd "$(dirname "$0")" && pwd)"
L=$1; MIRROR=$2; DB=$3; ROOT=$4
RUNS=${RUNS:-3}
case $RUNS in ''|*[!0-9]*) RUNS=bad ;; esac
[ "$RUNS" != bad ] && [ "$((10#$RUNS))" -ge 1 ] || { echo "RUNS must be a positive integer" >&2; exit 1; }
[ -f "$MIRROR/releases.json" ] || { echo "no releases.json in $MIRROR" >&2; exit 1; }
[ -f "$DB" ] || { echo "no DB at $DB" >&2; exit 1; }
IFS=';' read -r -a RLIST <<< "${ROUTES:-delta;full}"
if [ -z "${ZSTD_LIBRARY_PATH:-}" ] && [ -f "/c/Program Files/Git/mingw64/bin/libzstd.dll" ]; then
  export ZSTD_LIBRARY_PATH="C:/Program Files/Git/mingw64/bin/libzstd.dll"
fi
mkdir -p "$ROOT" || exit 1
# absolute before the cd below: relative paths would land inside the repo
ROOT=$(cd "$ROOT" && pwd) || exit 1
MIRROR=$(cd "$MIRROR" && pwd) || exit 1
DB="$(cd "$(dirname "$DB")" && pwd)/$(basename "$DB")" || exit 1
JSON=${JSON:-$ROOT/apply-results.jsonl}
case $JSON in /*|[A-Za-z]:*) ;; *) JSON="$PWD/$JSON" ;; esac
cd "$B/../../library_manager" || exit 1
N=0
NR=${#RLIST[@]}
for k in $(seq 1 "$RUNS"); do
  for i in $(seq 0 $((NR - 1))); do
    R=${RLIST[$(( (i + k - 1) % NR ))]}
    N=$((N + 1))
    echo "## $L route=$R run=$k"
    out=$(APPLY_MIRROR="$MIRROR" APPLY_DB="$DB" APPLY_WORK="$ROOT/run_$$_$N" \
      APPLY_ROUTE="$R" APPLY_LABEL="$L" APPLY_JSON="$JSON" \
      flutter test "$B/apply/apply_bench.dart" -r expanded 2>&1)
    rc=$?
    line=$(echo "$out" | grep "^APPLYRESULT")
    if [ $rc -ne 0 ] || [ -z "$line" ]; then
      echo "$out" | tail -20 >&2
      echo "SUITE INCOMPLETE: route=$R run=$k failed" >&2
      exit 1
    fi
    echo "$line"
  done
done
echo "results: $JSON  (dart run bin/compare.dart <file>)"

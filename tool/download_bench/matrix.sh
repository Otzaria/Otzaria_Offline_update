#!/bin/bash
# מטריצת מדידה לכל כלי, יעד מקומי מול USB (#149/#153/#166).
# usage: tool/download_bench/matrix.sh <label> <url> <size> <sha256> <localDir> <usbDir>
# RUNS=3 (ברירת מחדל) ריצות לכל תא. כל ריצה יוצרת תיקיית scratch חדשה
# (run_<pid>_<n>) בתוך localDir/usbDir שהכלי מסמן בקובץ בעלות ומוחק בסוף;
# שום דבר אחר בתיקיות האלה לא נוגע. ריצה שנכשלה עוצרת את כל המטריצה בקוד
# יציאה שאינו אפס, בלי להדפיס מטריצה חלקית כתקינה. מודפסות שורות RESULT/ASSET.
# כל RESULT נוסף גם כשורת JSON ל-JSON (ברירת מחדל: localDir/bench-results.jsonl);
# סיכום והשוואה: dart run bin/compare.dart <a.jsonl> [<b.jsonl>].
# VARIANTS: רשימה מופרדת ב-';' (ברירת המחדל למטה). סדר הווריאנטים מסתובב בכל
# סבב, כדי שאף אחד לא ירוץ תמיד ראשון על מטמון קר או כונן נח.
# BENCH: ברירת המחדל בונה bundle מקומפל (dart build cli); תחת `dart run` הזיכרון
# וה-CPU כוללים את המהדר ולכן מדווחים n/a. ‏.dill אינו עובד: sqlite3 נטען מ-build hook.
# INSECURE=1: מעביר --insecure (תעודה עצמית של bin/server.dart, רק מ-loopback).
set -u -o pipefail
B="$(cd "$(dirname "$0")" && pwd)"
L=$1; U=$2; SZ=$3; SHA=$4; LOC=$5; USB=$6
RUNS=${RUNS:-3}
case $RUNS in ''|*[!0-9]*) RUNS=bad ;; esac
[ "$RUNS" != bad ] && [ "$((10#$RUNS))" -ge 1 ] || { echo "RUNS must be a positive integer" >&2; exit 1; }
VARIANTS=${VARIANTS:-"pd 1;pd 2;pd 4;pd policy;stage 1;stage 2;stage 4;assist 4;df"}
IFS=';' read -r -a VLIST <<< "$VARIANTS"
[ ${#VLIST[@]} -ge 1 ] || { echo "VARIANTS is empty" >&2; exit 1; }
for v in "${VLIST[@]}"; do
  case $v in
    "pd "[1-8]|"pd auto"|"pd policy"|"stage "[1-8]|"stage auto"|"assist "[1-8]|df) ;;
    *) echo "bad VARIANTS entry '$v' (e.g. 'pd 2', 'stage 2', 'assist 4', 'df')" >&2; exit 1 ;;
  esac
done
cd "$B" || exit 1
if [ -z "${BENCH:-}" ]; then
  dart build cli -t bin/bench.dart -o .dart_tool/bench_bundle >/dev/null \
    || { echo "dart build cli failed" >&2; exit 1; }
  # relative on purpose: $BENCH is word-split, and $B may contain spaces
  BENCH=$(ls .dart_tool/bench_bundle/bundle/bin/bench* | head -1)
fi
mkdir -p "$LOC" "$USB" || exit 1
JSON=${JSON:-$LOC/bench-results.jsonl}
spec="$U,$SZ,$SHA"
N=0
SCRATCH=()
fail() {
  echo "MATRIX INCOMPLETE: $*" >&2
  cleanup
  exit 1
}
cleanup() {
  local s rc=0
  for s in "${SCRATCH[@]:-}"; do
    [ -n "$s" ] || continue
    $BENCH scratch-rm "$s" >/dev/null 2>&1 || { echo "could not remove $s" >&2; rc=1; }
  done
  SCRATCH=()
  return $rc
}
trap 'cleanup' EXIT
newscratch() { # root -> sets NEWDIR to a fresh owned scratch dir
  N=$((N + 1))
  local d="$1/run_$$_$N"
  $BENCH scratch "$d" >/dev/null || fail "cannot create $d"
  SCRATCH+=("$d")
  NEWDIR=$d
}
policy_args() { # dir -> sets POLICY_ARGS from library_manager's real decision
  local o line
  o=$(cd "$B/../../library_manager" && POLICY_DIR="$1" flutter test "$B/policy/policy_decision.dart" 2>&1) \
    || fail "policy decision failed: $(echo "$o" | tail -5)"
  line=$(echo "$o" | grep -o "POLICY conns=.*" | head -1)
  [ -n "$line" ] || fail "no POLICY line"
  echo "$line"
  POLICY_ARGS="--decided=$(echo "$line" | sed 's/.*conns=\([0-9]*\).*/\1/') --reason=$(echo "$line" | sed 's/.*reason=\([^ ]*\).*/\1/')"
}
run() { # tool args... (cache dir/out dir are placeholders @CACHE@ @OUT@)
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [ $rc -ne 0 ]; then
    echo "$out" | tail -15 >&2
    fail "exit $rc: $*"
  fi
  echo "$out" | grep -E "^RESULT|^ASSET" || fail "no RESULT line: $*"
}
for k in $(seq 1 "$RUNS"); do
  for T in local usb; do
    if [ $T = local ]; then ROOT="$LOC"; else ROOT="$USB"; fi
    echo "## $L $T run=$k"
    NV=${#VLIST[@]}
    for i in $(seq 0 $((NV - 1))); do
      variant=${VLIST[$(( (i + k - 1) % NV ))]}
      set -- $variant
      J=(--json="$JSON" --label="$L")
      [ "${INSECURE:-}" = 1 ] && J+=(--insecure)
      newscratch "$LOC"; LS=$NEWDIR; newscratch "$ROOT"; DS=$NEWDIR
      case $1 in
        assist) run $BENCH assist "$LS/cache" "$DS/out" --segments=$2 --target=$T "${J[@]}" "$spec" ;;
        stage) run $BENCH stage "$LS/cache" "$DS/out" $2 --target=$T "${J[@]}" "$spec" ;;
        pd) POLICY_ARGS=; [ "$2" = policy ] && policy_args "$DS/pd"
            run $BENCH pd "$DS/pd" $2 --target=$T $POLICY_ARGS "${J[@]}" "$spec" ;;
        df) run $BENCH df "$DS/df" --target=$T "${J[@]}" "$spec" ;;
        *) fail "unknown variant '$variant'" ;;
      esac
      cleanup || fail "cleanup failed"
    done
  done
done

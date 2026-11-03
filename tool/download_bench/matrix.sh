#!/bin/bash
# מטריצת מדידה לכל כלי, יעד מקומי מול USB (#149/#153/#166).
# usage: tool/download_bench/matrix.sh <label> <url> <size> <sha256> <localDir> <usbDir>
# RUNS=3 (ברירת מחדל) ריצות לכל תא. כל ריצה יוצרת תיקיית scratch חדשה
# (run_<pid>_<n>) בתוך localDir/usbDir שהכלי מסמן בקובץ בעלות ומוחק בסוף;
# שום דבר אחר בתיקיות האלה לא נוגע. ריצה שנכשלה עוצרת את כל המטריצה בקוד
# יציאה שאינו אפס, בלי להדפיס מטריצה חלקית כתקינה. מודפסות שורות RESULT/ASSET.
set -u -o pipefail
B="$(cd "$(dirname "$0")" && pwd)"
L=$1; U=$2; SZ=$3; SHA=$4; LOC=$5; USB=$6
RUNS=${RUNS:-3}
case $RUNS in ''|*[!0-9]*) RUNS=bad ;; esac
[ "$RUNS" != bad ] && [ "$((10#$RUNS))" -ge 1 ] || { echo "RUNS must be a positive integer" >&2; exit 1; }
BENCH=${BENCH:-dart run bin/bench.dart}   # or: dart <file.dill>, from dart compile kernel
cd "$B" || exit 1
mkdir -p "$LOC" "$USB" || exit 1
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
    for variant in "assist 4" "pd 1" "pd 2" "pd 4" "pd policy" "df"; do
      set -- $variant
      newscratch "$LOC"; LS=$NEWDIR; newscratch "$ROOT"; DS=$NEWDIR
      case $1 in
        assist) run $BENCH assist "$LS/cache" "$DS/out" --segments=$2 --target=$T "$spec" ;;
        pd) POLICY_ARGS=; [ "$2" = policy ] && policy_args "$DS/pd"
            run $BENCH pd "$DS/pd" $2 --target=$T $POLICY_ARGS "$spec" ;;
        df) run $BENCH df "$DS/df" --target=$T "$spec" ;;
      esac
      cleanup || fail "cleanup failed"
    done
  done
done

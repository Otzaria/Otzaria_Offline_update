#!/usr/bin/env bash
# יומן השינויים למשתמש (`launcher_app/assets/יומן שינויים.md`), שמוצג ב"מה
# התחדש". פריטים חדשים נכתבים **בראש הקובץ, בלי כותרת** — את מספר הגרסה ה-CI
# קובע רק בזמן הפרסום, ולכן הכותרת נחתמת כאן.
#
#   tool/changelog.sh check          # יש פריטים שעוד לא יצאו? אחרת נכשל
#   tool/changelog.sh stamp 0.23     # חותם `* **0.23**` מעליהם (אידמפוטנטי)
#
# awk בלי `{n,m}`: ה-mawk של ubuntu וה-awk של macOS אינם תומכים בזה באותה מידה.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
file="$root/launcher_app/assets/יומן שינויים.md"
heading='^[[:space:]]*([#]+[[:space:]]*|[*-][[:space:]]*)?[*]*v?[0-9]+([.][0-9]+)+([-+][^[:space:]*]+)?[*]*[[:space:]]*$'

# השורה הראשונה שאינה ריקה: "heading", "items" או "empty".
top_kind() {
  awk -v re="$heading" '
    /^[[:space:]]*$/ { next }
    { print ($0 ~ re) ? "heading" : "items"; found = 1; exit }
    END { if (!found) print "empty" }
  ' "$file"
}

case "${1:-}" in
  check)
    if [ "$(top_kind)" != "items" ]; then
      echo "::error::אין בראש '$file' פריטים חדשים בלי כותרת — יש לכתוב מה התחדש לפני הפרסום (AGENTS.md §3)" >&2
      exit 1
    fi
    ;;
  stamp)
    version="${2:?usage: changelog.sh stamp <version>}"
    [ "$(top_kind)" = "items" ] || exit 0
    awk -v line="* **$version**" '
      !done && !/^[[:space:]]*$/ { print line; done = 1 }
      { print }
    ' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
    ;;
  *)
    echo "usage: changelog.sh check | stamp <version>" >&2
    exit 2
    ;;
esac

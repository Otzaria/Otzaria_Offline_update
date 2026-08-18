#!/usr/bin/env bash
# מציב את גרסת הלאנצ'ר בשני המקומות שחייבים להסכים: `launcher_app/pubspec.yaml`
# (ממנו `build_stub.ps1` צורב את גרסת ה-payload ואת משאב הגרסה של ה-exe) ו-
# `launcher_version.dart` (הגרסה שהתוכנה מדווחת על עצמה). אי-התאמה ביניהם
# מפילה את `launcher_version_test.dart`.
#
# מריץ אותו ה-CI לפני כל בנייה של הלאנצ'ר — ראו `.github/workflows/ci.yml`.
# פועל מכל תיקייה (הנתיבים נגזרים ממקום הסקריפט) ובלי `sed -i`, שאינו נייד
# בין GNU ל-BSD — הג'וב של macOS מריץ אותו גם הוא.
#
# הגרסה בת שני חלקים (`0.2`), ורק החלק השני עולה מגרסה לגרסה. ב-pubspec
# נכתב `0.2.0`: pub מסרב לגרסה שאינה MAJOR.MINOR.PATCH. השלישייה הזאת היא
# פרט טכני בלבד — מה שהתוכנה מדווחת ומה שמתויג הוא `0.2`.
#
#   tool/set_launcher_version.sh 0.2
set -euo pipefail

version="${1:?usage: set_launcher_version.sh <version>}"
if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+$'; then
  echo "set_launcher_version.sh: '$version' is not MAJOR.MINOR" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
pubspec="$root/launcher_app/pubspec.yaml"
dart="$root/launcher_app/lib/src/self_update/launcher_version.dart"

replace() { # <file> <regex> <replacement>
  local file="$1"
  sed -E "s|$2|$3|" "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

# `^version:` בלי הזחה — התלויות שבהמשך הקובץ מוזחות, ולכן אין התנגשות.
replace "$pubspec" '^version:.*' "version: $version.0"
replace "$dart" "^const String launcherVersion = '.*';" \
  "const String launcherVersion = '$version';"

# מאמת שההצבה אכן נכנסה: sed שלא התאים לכלום אינו מחזיר שגיאה, וקובץ שנשאר
# עם הגרסה הקודמת היה מייצר release שמדווח על עצמו מספר אחר.
grep -qx "version: $version.0" "$pubspec"
grep -qx "const String launcherVersion = '$version';" "$dart"
echo "$version"

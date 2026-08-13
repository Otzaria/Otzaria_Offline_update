# אורז את ההפצה ל-Windows לקובץ exe בודד: ה-stub נושא בתוכו את ערמת הקבצים
# כ-resource ומחלץ אותה לידו בהרצה הראשונה.
# מריצים אחרי `flutter build windows --release`, עם pwsh 7.
#
#   עדכוני אוצריא.exe   ← זה כל מה שמפיצים, וזה מה שהמשתמש לוחץ תמיד
#   app-files\          ← נוצרת לידו בהרצה הראשונה: launcher_app.exe +
#                         ה-DLL + data\ + OtzariaData\
$ErrorActionPreference = 'Stop'

# שם הקובץ שהמשתמש רואה — זהה לכותרת החלון ול-ProductName שב-Runner.rc.
$appFileName = 'עדכוני אוצריא.exe'
$payloadDirName = 'app-files'  # חייב להתאים ל-kPayloadDir שב-stub.c

$launcherRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $launcherRoot 'build\windows\x64\runner\Release'
$stageDir = Join-Path $PSScriptRoot 'build\payload'
$payloadFile = Join-Path $PSScriptRoot 'build\payload.otz'  # הנתיב שב-stub.rc
$exePath = Join-Path $launcherRoot "build\$appFileName"

if (-not (Test-Path $releaseDir)) {
  throw "Release build not found at $releaseDir — run ``flutter build windows --release`` first."
}

if (Test-Path $stageDir) { Remove-Item -Recurse -Force $stageDir }
$payloadDir = Join-Path $stageDir $payloadDirName
New-Item -ItemType Directory -Force $payloadDir | Out-Null
Copy-Item (Join-Path $releaseDir '*') $payloadDir -Recurse

# הנתיבים בתוך המכל הם יחסיים ל-$stageDir, כלומר "app-files/..." — וזה מה
# שגורם ל-stub לחלץ ליד עצמו את התיקייה כולה.
if (Test-Path $payloadFile) { Remove-Item -Force $payloadFile }
& (Join-Path $PSScriptRoot 'pack_payload.ps1') -SourceDir $stageDir -OutFile $payloadFile

& (Join-Path $PSScriptRoot 'build_stub.ps1')

Copy-Item (Join-Path $PSScriptRoot 'build\stub.exe') $exePath -Force

$sizeMb = [math]::Round((Get-Item $exePath).Length / 1MB, 1)
Write-Host "Packaged $exePath ($sizeMb MB)"

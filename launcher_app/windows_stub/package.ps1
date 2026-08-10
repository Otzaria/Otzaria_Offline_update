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
$payloadZip = Join-Path $PSScriptRoot 'build\payload.zip'  # הנתיב שב-stub.rc
$exePath = Join-Path $launcherRoot "build\$appFileName"

if (-not (Test-Path $releaseDir)) {
  throw "Release build not found at $releaseDir — run ``flutter build windows --release`` first."
}

if (Test-Path $stageDir) { Remove-Item -Recurse -Force $stageDir }
$payloadDir = Join-Path $stageDir $payloadDirName
New-Item -ItemType Directory -Force $payloadDir | Out-Null
Copy-Item (Join-Path $releaseDir '*') $payloadDir -Recurse

# CreateFromDirectory ולא Compress-Archive: מהיר בהרבה על ~2000 קבצים.
# includeBaseDirectory=$false על $stageDir נותן רשומות בצורת "app-files/...",
# שזה מה ש-tar במחלץ מצפה לו.
if (Test-Path $payloadZip) { Remove-Item -Force $payloadZip }
[System.IO.Compression.ZipFile]::CreateFromDirectory(
  $stageDir, $payloadZip,
  [System.IO.Compression.CompressionLevel]::Optimal, $false)

& (Join-Path $PSScriptRoot 'build_stub.ps1')

Copy-Item (Join-Path $PSScriptRoot 'build\stub.exe') $exePath -Force

$sizeMb = [math]::Round((Get-Item $exePath).Length / 1MB, 1)
Write-Host "Packaged $exePath ($sizeMb MB)"

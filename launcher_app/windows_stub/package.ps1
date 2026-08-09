# אורז את ההפצה ל-Windows: קובץ הרצה אחד בשורש, וכל השאר בתיקיית משנה.
# מריצים אחרי `flutter build windows --release`, עם pwsh 7.
#
#   עדכוני אוצריא.exe   ← ה-stub, זה מה שהמשתמש לוחץ
#   app-files\          ← launcher_app.exe + ה-DLL + data\ + OtzariaData\
$ErrorActionPreference = 'Stop'

# שם הקובץ שהמשתמש רואה — זהה לכותרת החלון ול-ProductName שב-Runner.rc.
$appFileName = 'עדכוני אוצריא.exe'
$payloadDirName = 'app-files'  # חייב להתאים ל-kPayloadDir שב-stub.c

$launcherRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $launcherRoot 'build\windows\x64\runner\Release'
$stageDir = Join-Path $launcherRoot 'build\portable'
$zipPath = Join-Path $launcherRoot 'launcher_app-windows-portable.zip'

if (-not (Test-Path $releaseDir)) {
  throw "Release build not found at $releaseDir — run ``flutter build windows --release`` first."
}

& (Join-Path $PSScriptRoot 'build_stub.ps1')

if (Test-Path $stageDir) { Remove-Item -Recurse -Force $stageDir }
$payloadDir = Join-Path $stageDir $payloadDirName
New-Item -ItemType Directory -Force $payloadDir | Out-Null

Copy-Item (Join-Path $releaseDir '*') $payloadDir -Recurse
Copy-Item (Join-Path $PSScriptRoot 'build\stub.exe') (Join-Path $stageDir $appFileName)

if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath

Write-Host "Packaged $zipPath"

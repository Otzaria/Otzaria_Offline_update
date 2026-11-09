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
# הרצה מקומית של ה-Release משאירה בו נתוני משתמש; חילוץ היה דורס בהם את של המשתמש.
$strayData = Join-Path $payloadDir 'OtzariaData'
if (Test-Path -LiteralPath $strayData) { Remove-Item -Recurse -Force -LiteralPath $strayData }

# הקוד רץ מהכונן: בלי טעינה מלאה לזיכרון כל דף קוד נקרא ממנו לפי דרישה,
# וכונן עמוס בהורדה מקפיא את הממשק. חתום לא מסומנים — החתימה הייתה נשברת.
$runFromSwap = 0x0C00  # REMOVABLE_RUN_FROM_SWAP | NET_RUN_FROM_SWAP
# Where-Object ולא -Include: עם -LiteralPath ב-PowerShell 5.1 הוא אינו מסנן דבר.
$images = Get-ChildItem -LiteralPath $payloadDir -Recurse -File |
  Where-Object { $_.Extension -in '.exe', '.dll' }
foreach ($image in $images) {
  if ((Get-AuthenticodeSignature -LiteralPath $image.FullName).Status -ne 'NotSigned') {
    Write-Host "Left signed image unmarked: $($image.Name)"
    continue
  }
  $bytes = [IO.File]::ReadAllBytes($image.FullName)
  $pe = if ($bytes.Length -ge 0x40 -and $bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) { [BitConverter]::ToInt32($bytes, 0x3C) } else { -1 }
  if ($pe -lt 0 -or $pe + 24 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes, $pe) -ne 0x00004550) {
    throw "Not a PE image: $($image.FullName)"
  }
  $at = $pe + 22
  $flags = [BitConverter]::ToUInt16($bytes, $at) -bor $runFromSwap
  [BitConverter]::GetBytes([uint16]$flags).CopyTo($bytes, $at)
  [IO.File]::WriteAllBytes($image.FullName, $bytes)
}
$flutterDll = [IO.File]::ReadAllBytes((Join-Path $payloadDir 'flutter_windows.dll'))
$flutterFlags = [BitConverter]::ToUInt16($flutterDll, [BitConverter]::ToInt32($flutterDll, 0x3C) + 22)
if (($flutterFlags -band $runFromSwap) -ne $runFromSwap) { throw 'flutter_windows.dll was not marked run-from-swap.' }
Write-Host 'Marked the payload images run-from-swap'

# ה-CRT של Visual C++ נוסע איתנו. `launcher_app.exe` ושלושה מה-DLL של
# ה-plugins מייבאים אותו בטעינה, ופלאטר **אינו** מעתיק אותו לתיקיית ה-Release
# — כך שבלי זה התוכנה אינה עולה כלל על מכונה שאין בה Redistributable מותקן.
# זו בדיוק המכונה שלנו: הלאנצ'ר רץ על המחשב **המקוון**, שבו אוצריא — שההתקנה
# שלה מביאה את ה-CRT — לא מותקנת מעולם.
$requiredCrtDlls = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
  throw "vswhere.exe not found at $vswhere — Visual Studio with C++ tools is required."
}
$vsPath = & $vswhere -latest -products '*' `
  -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
  -property installationPath
if (-not $vsPath) { throw 'No Visual Studio installation with C++ tools was found.' }

# תיקיות ה-Redist נקראות לפי גרסת ה-toolset (14.44.35112), ומיון טקסטואלי
# היה מעדיף 14.9 על 14.44 — ולכן מיון כ-[version].
$crtDir = Get-ChildItem -LiteralPath (Join-Path $vsPath 'VC\Redist\MSVC') -Directory |
  Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
  Sort-Object { [version]$_.Name } -Descending |
  ForEach-Object {
    Get-ChildItem -LiteralPath (Join-Path $_.FullName 'x64') -Directory `
      -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue
  } |
  Select-Object -First 1
if (-not $crtDir) {
  throw "No Microsoft.VC*.CRT folder under $vsPath\VC\Redist\MSVC — install the 'C++ Redistributable' component of Visual Studio."
}
Copy-Item (Join-Path $crtDir.FullName '*.dll') $payloadDir -Force

# האריזה נכשלת ברעש ולא מפיצה exe שאינו עולה: זו התקלה שהתגלתה בשטח, והיא
# שקטה לגמרי — הבנייה מצליחה, ה-exe נוצר, והוא פשוט לא רץ אצל המשתמש.
$missingCrt = @($requiredCrtDlls | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $payloadDir $_))
  })
if ($missingCrt.Count -gt 0) {
  throw "CRT DLLs missing from the payload: $($missingCrt -join ', ') (source: $($crtDir.FullName))."
}
Write-Host "Bundled the Visual C++ CRT from $($crtDir.Name)"

# הנתיבים בתוך המכל הם יחסיים ל-$stageDir, כלומר "app-files/..." — וזה מה
# שגורם ל-stub לחלץ ליד עצמו את התיקייה כולה.
if (Test-Path $payloadFile) { Remove-Item -Force $payloadFile }
& (Join-Path $PSScriptRoot 'pack_payload.ps1') -SourceDir $stageDir -OutFile $payloadFile

& (Join-Path $PSScriptRoot 'build_stub.ps1')

Copy-Item (Join-Path $PSScriptRoot 'build\stub.exe') $exePath -Force

$sizeMb = [math]::Round((Get-Item $exePath).Length / 1MB, 1)
Write-Host "Packaged $exePath ($sizeMb MB)"

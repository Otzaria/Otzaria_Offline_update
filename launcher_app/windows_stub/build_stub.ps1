# מקמפל את ה-stub שיושב בשורש הכונן. דורש Visual Studio עם כלי C++
# (קיים על windows-latest ב-GitHub Actions). להרצה עם pwsh 7 — הקבצים כאן
# הם UTF-8 בלי BOM, ו-Windows PowerShell 5.1 יקרא אותם בקוד־עמוד המערכת.
$ErrorActionPreference = 'Stop'

$sourceDir = $PSScriptRoot
$outDir = Join-Path $sourceDir 'build'
New-Item -ItemType Directory -Force $outDir | Out-Null

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
  throw "vswhere.exe not found at $vswhere — Visual Studio with C++ tools is required."
}
$vsPath = & $vswhere -latest -products '*' `
  -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
  -property installationPath
if (-not $vsPath) { throw 'No Visual Studio installation with C++ tools was found.' }

$vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw "vcvars64.bat not found at $vcvars." }

# דרך קובץ bat ולא `cmd /c "..."`: cmd מפרק מחרוזת עם מרכאות מקוננות
# בכללים משלו, וזה נשבר על נתיבים עם רווחים.
#
# /MT (CRT סטטי) הכרחי: ה-stub יושב מחוץ ל-app-files ולכן לא רואה את
# vcruntime140.dll שהבנייה של Flutter מעתיקה לתיקיית ה-Release.
# /utf-8 מאפשר את הטקסט העברי במקור ומונע C4819. אין כאן /WX בכוונה,
# בניגוד לרנר של Flutter: אזהרה בקובץ עזר של 70 שורות לא שווה CI אדום
# שבו הארטיפקט כולו לא נבנה.
$batPath = Join-Path $outDir '_build.bat'
@"
@echo off
call "$vcvars" >nul || exit /b 1
rc /nologo /fo "$outDir\stub.res" "$sourceDir\stub.rc" || exit /b 1
cl /nologo /utf-8 /W4 /O1 /MT /Fo"$outDir\stub.obj" /Fe"$outDir\stub.exe" ^
   "$sourceDir\stub.c" "$outDir\stub.res" ^
   /link /SUBSYSTEM:WINDOWS kernel32.lib user32.lib || exit /b 1
"@ | Set-Content -Path $batPath -Encoding oem

cmd /c $batPath
if ($LASTEXITCODE -ne 0) { throw "stub build failed with exit code $LASTEXITCODE." }
if (-not (Test-Path (Join-Path $outDir 'stub.exe'))) { throw 'stub.exe was not produced.' }

Write-Host "Built $outDir\stub.exe"

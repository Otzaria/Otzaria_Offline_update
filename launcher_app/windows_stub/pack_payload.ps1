# אורז את ערמת הקבצים לקובץ `payload.otz` שה-stub מטמיע ומחלץ **בעצמו**.
#
# למה לא zip: את ה-zip חילץ `tar.exe` של Windows — תהליך חיצוני שקיים רק
# מ-Windows 10 1803, ושמקבל את הנתיבים שלו דרך שורת פקודה בקוד-עמוד ANSI.
# שתי התלויות האלה הן מה ששבר חילוץ על כוננים ניידים (ראו stub.c). הפורמט
# כאן נקרא ע"י ה-stub עצמו דרך Compression API של Windows, בלי תהליך חיצוני,
# בלי קובץ זמני ובלי שאף נתיב יעבור המרת קידוד.
#
# מבנה הקובץ — little-endian, זהה לקריאה שב-`ExtractPayload`:
#
#   "OTZPAY1\0"      8 בתים
#   uint32 algorithm  אלגוריתם ה-Compression API (LZMS)
#   uint32 fileCount
#   uint64 rawSize    גודל הגוש אחרי פרישה
#   בתים דחוסים...
#
# הגוש הפרוש: טבלה של fileCount רשומות (uint32 pathBytes, uint32 dataBytes,
# ואחריהן הנתיב ב-UTF-8 עם `/`), ואחריה תוכן הקבצים באותו סדר.
param(
  [Parameter(Mandatory = $true)][string]$SourceDir,
  [Parameter(Mandatory = $true)][string]$OutFile
)
$ErrorActionPreference = 'Stop'

# חייב להתאים ל-kPayloadMagic ול-COMPRESS_ALGORITHM_LZMS שב-stub.c.
$magic = [Text.Encoding]::ASCII.GetBytes("OTZPAY1`0")
$algorithm = 5

Add-Type -Namespace Otz -Name Cab -MemberDefinition @'
[DllImport("cabinet.dll", SetLastError = true)]
public static extern bool CreateCompressor(uint algorithm, IntPtr allocRoutines, out IntPtr handle);
[DllImport("cabinet.dll", SetLastError = true)]
public static extern bool Compress(IntPtr handle, byte[] uncompressed, IntPtr uncompressedSize,
    byte[] compressed, IntPtr compressedBufferSize, out IntPtr compressedDataSize);
[DllImport("cabinet.dll", SetLastError = true)]
public static extern bool CloseCompressor(IntPtr handle);
'@

# הנתיב היחסי נבנה תוך כדי הירידה בעץ, ולא בחיתוך תחילית מ-FullName: השתיים
# יכולות להגיע בצורות שונות של אותו נתיב (שם 8.3 מול השם המלא — `$env:TEMP`
# מחזיר 8.3 כשיש תווים שאינם ASCII בשם המשתמש), והחיתוך אז מזיז את השם.
function Get-PayloadEntries([string]$dir, [string]$prefix) {
  foreach ($entry in Get-ChildItem -LiteralPath $dir -Force | Sort-Object -Property Name) {
    $relative = if ($prefix -eq '') { $entry.Name } else { "$prefix/$($entry.Name)" }
    if ($entry.PSIsContainer) {
      Get-PayloadEntries $entry.FullName $relative
    } else {
      [pscustomobject]@{ Relative = $relative; Path = $entry.FullName; Length = $entry.Length }
    }
  }
}

$root = (Get-Item -LiteralPath $SourceDir).FullName.TrimEnd('\')
$files = @(Get-PayloadEntries $root '')
if ($files.Count -eq 0) { throw "No files under $root." }

# הטבלה והתוכן נבנים לתוך אותו זרם, בשני מעברים על אותה רשימה בדיוק.
$blob = New-Object IO.MemoryStream
$writer = New-Object IO.BinaryWriter($blob)
$writer.Write([uint32]$files.Count)
foreach ($file in $files) {
  $pathBytes = [Text.Encoding]::UTF8.GetBytes($file.Relative)
  if ($file.Length -gt [uint32]::MaxValue) {
    throw "$($file.Relative) is larger than 4GB — the container stores 32-bit sizes."
  }
  $writer.Write([uint32]$pathBytes.Length)
  $writer.Write([uint32]$file.Length)
  $writer.Write($pathBytes)
}
foreach ($file in $files) {
  $writer.Write([IO.File]::ReadAllBytes($file.Path))
}
$writer.Flush()
$raw = $blob.ToArray()
$writer.Dispose()

$handle = [IntPtr]::Zero
if (-not [Otz.Cab]::CreateCompressor($algorithm, [IntPtr]::Zero, [ref]$handle)) {
  throw "CreateCompressor failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}
try {
  # שוליים לגודל: על נתונים שאינם נדחסים הפלט עלול לעלות במעט על הקלט.
  $buffer = New-Object byte[] ($raw.Length + 1MB)
  $written = [IntPtr]::Zero
  $ok = [Otz.Cab]::Compress($handle, $raw, [IntPtr]$raw.Length,
    $buffer, [IntPtr]$buffer.Length, [ref]$written)
  if (-not $ok) {
    throw "Compress failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
  }
} finally { [void][Otz.Cab]::CloseCompressor($handle) }

$compressedSize = $written.ToInt64()
$out = New-Object IO.MemoryStream
$header = New-Object IO.BinaryWriter($out)
$header.Write($magic)
$header.Write([uint32]$algorithm)
$header.Write([uint32]$files.Count)
$header.Write([uint64]$raw.Length)
$header.Write($buffer, 0, $compressedSize)
$header.Flush()
[IO.File]::WriteAllBytes($OutFile, $out.ToArray())
$header.Dispose()

$rawMb = [math]::Round($raw.Length / 1MB, 1)
$outMb = [math]::Round((Get-Item $OutFile).Length / 1MB, 1)
Write-Host "Packed $($files.Count) files: $rawMb MB -> $outMb MB ($OutFile)"

# Pickle Pete - Epic Level-Ups mod
# Patches LevelUpButton.SetupProps in GameAssembly.dll so every level-up reward is Epic.
#
#   powershell -ExecutionPolicy Bypass -File EpicLevelUps.ps1            # install
#   powershell -ExecutionPolicy Bypass -File EpicLevelUps.ps1 -Restore   # uninstall
#
# Game updates replace GameAssembly.dll; just run the script again afterwards.
param(
    [string]$GameDir = 'G:\SteamLibrary\steamapps\common\Pickle Pete',
    [switch]$Restore
)
$ErrorActionPreference = 'Stop'

$dll    = Join-Path $GameDir 'GameAssembly.dll'
$backup = "$dll.epiclevelups.bak"

if (Get-Process -Name 'Pickle Pete' -ErrorAction SilentlyContinue) { throw 'Close Pickle Pete first.' }
if (-not (Test-Path $dll)) { throw "Not found: $dll" }

if ($Restore) {
    if (-not (Test-Path $backup)) { throw "No backup found at $backup" }
    Copy-Item $backup $dll -Force
    Remove-Item $backup -Confirm:$false
    'Restored original GameAssembly.dll.'
    return
}

function ToText([byte[]]$b) { [Text.Encoding]::GetEncoding(28591).GetString($b) }

# Original code:
#   B9 02 00 00 00     mov ecx, 2            ; openFromMutation -> Rare
#   EB 09              jmp +9
#   33 C9              xor ecx, ecx
#   E8 ?? ?? ?? ??     call Database.GetRandomRarity
#   8B C8              mov ecx, eax
#   89 8B 10 01 00 00  mov [rbx+110h], ecx   ; this.rarity = ecx
$head = [byte[]](0xB9,0x02,0x00,0x00,0x00,0xEB,0x09,0x33,0xC9,0xE8)
$tail = [byte[]](0x8B,0xC8,0x89,0x8B,0x10,0x01,0x00,0x00)
# Patched code: both paths load Epic (3); the call is replaced by nops
$new  = [byte[]](0xB9,0x03,0x00,0x00,0x00,0xEB,0x09,0xB9,0x03,0x00,0x00,0x00,0x0F,0x1F,0x40,0x00)

$bytes = [IO.File]::ReadAllBytes($dll)
$text  = ToText $bytes

if ($text.IndexOf((ToText ($new + $tail[2..7])), [StringComparison]::Ordinal) -ge 0) { 'Already patched.'; return }

$hits = @()
$i = 0
while (($i = $text.IndexOf((ToText $head), $i, [StringComparison]::Ordinal)) -ge 0) {
    if ($text.Substring($i + $head.Length + 4, $tail.Length) -ceq (ToText $tail)) { $hits += $i }
    $i++
}
if ($hits.Count -ne 1) { throw "Expected exactly one match for the level-up rarity code, found $($hits.Count) - the game code changed." }

if (-not (Test-Path $backup)) { Copy-Item $dll $backup }

[Array]::Copy($new, 0, $bytes, $hits[0], $new.Length)
[IO.File]::WriteAllBytes($dll, $bytes)
'Patched level-up rarity at file offset 0x{0:X}. Backup: {1}' -f $hits[0], $backup

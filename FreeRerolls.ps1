# Pickle Pete - Free Rerolls mod
# Patches the "Balancing" ScriptableObject in sharedassets0.assets so rerolls cost 0.
#
#   powershell -ExecutionPolicy Bypass -File FreeRerolls.ps1            # install
#   powershell -ExecutionPolicy Bypass -File FreeRerolls.ps1 -Restore   # uninstall
#
# Game updates replace sharedassets0.assets; just run the script again afterwards.
param(
    [string]$GameDir = 'G:\SteamLibrary\steamapps\common\Pickle Pete',
    [switch]$Restore
)
$ErrorActionPreference = 'Stop'

$asset  = Join-Path $GameDir 'Pickle Pete_Data\sharedassets0.assets'
$backup = "$asset.freererolls.bak"

if (Get-Process -Name 'Pickle Pete' -ErrorAction SilentlyContinue) { throw 'Close Pickle Pete first.' }
if (-not (Test-Path $asset)) { throw "Not found: $asset" }

if ($Restore) {
    if (-not (Test-Path $backup)) { throw "No backup found at $backup" }
    Copy-Item $backup $asset -Force
    Remove-Item $backup -Confirm:$false
    'Restored original sharedassets0.assets.'
    return
}

# Field index (4 bytes each, counted from the end of m_Name) -> BalancingSO field
$intFields   = @{ 18 = 'RerollBaseCost' }
$floatFields = @{
    19 = 'ShopRerollWaveGrowth'
    20 = 'ShopRerollRepeatGrowth'
    21 = 'LevelUpRerollWaveGrowth'
    22 = 'LevelUpRerollRepeatGrowth'
    58 = 'EndlessShopRerollWaveGrowth'
    59 = 'EndlessShopRerollRepeatGrowth'
    60 = 'EndlessLevelUpRerollWaveGrowth'
    61 = 'EndlessLevelUpRerollRepeatGrowth'
}

$bytes = [IO.File]::ReadAllBytes($asset)
$text  = [Text.Encoding]::GetEncoding(28591).GetString($bytes)

# m_Name is serialized as int32 length + chars, padded to 4 bytes
$needle = [string][char]9 + "`0`0`0" + 'Balancing' + "`0`0`0"
$at = $text.IndexOf($needle, [StringComparison]::Ordinal)
if ($at -lt 0) { throw 'Balancing asset not found - the game layout changed.' }
if ($text.IndexOf($needle, $at + 1, [StringComparison]::Ordinal) -ge 0) { throw 'Balancing asset is ambiguous - the game layout changed.' }
$base = $at + $needle.Length

# Sanity checks so a changed layout fails loudly instead of corrupting other values
$waveCap = [BitConverter]::ToInt32($bytes, $base + 4 * 17)
$cost    = [BitConverter]::ToInt32($bytes, $base + 4 * 18)
if ($waveCap -lt 1 -or $waveCap -gt 1000 -or $cost -lt 0 -or $cost -gt 1000) {
    throw "Unexpected values (EconomyWaveCap=$waveCap, RerollBaseCost=$cost) - the game layout changed."
}
foreach ($i in $floatFields.Keys) {
    $v = [BitConverter]::ToSingle($bytes, $base + 4 * $i)
    if ($v -lt 0 -or $v -gt 100) { throw "Unexpected value for $($floatFields[$i]) ($v) - the game layout changed." }
}

if (-not (Test-Path $backup)) { Copy-Item $asset $backup }

foreach ($i in (@($intFields.Keys) + @($floatFields.Keys) | Sort-Object)) {
    $name = if ($intFields.ContainsKey($i)) { $intFields[$i] } else { $floatFields[$i] }
    $o    = $base + 4 * $i
    $old  = if ($intFields.ContainsKey($i)) { [BitConverter]::ToInt32($bytes, $o) } else { [BitConverter]::ToSingle($bytes, $o) }
    [Array]::Clear($bytes, $o, 4)
    '{0,-34} {1} -> 0' -f $name, $old
}

[IO.File]::WriteAllBytes($asset, $bytes)
"Patched. Backup: $backup"

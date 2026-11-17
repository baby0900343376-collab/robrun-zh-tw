# ROB RUN 繁體中文化 — install.ps1 / uninstall.ps1 共用函式

$ErrorActionPreference = 'Stop'

$Script:Bundles = @(
    'inbuild_assets_all.bundle',
    'localization-locales_assets_all.bundle',
    'localization-string-tables-english(unitedstates)(en-us)_assets_all.bundle',
    'localization-string-tables-french(fr)_assets_all.bundle',
    'localization-string-tables-german(de)_assets_all.bundle',
    'localization-string-tables-portuguese(pt)_assets_all.bundle',
    'localization-string-tables-russian(russia)(ru-ru)_assets_all.bundle',
    'localization-string-tables-spanish(es)_assets_all.bundle'
)
# 新檔名必須和原檔名一樣長，才能在 catalog 裡直接替換位元組
$Script:OrigSuffix = '_all.bundle'
$Script:ModSuffix  = '_zht.bundle'

$Script:WorkDir = Join-Path $env:LOCALAPPDATA 'ROBRUN_zhTW'
$Script:LogFile = Join-Path $Script:WorkDir 'log.txt'
$Script:Errors  = 0

function Write-Log([string]$Text) {
    try {
        if (-not (Test-Path -LiteralPath $Script:WorkDir)) { New-Item -ItemType Directory -Path $Script:WorkDir -Force | Out-Null }
        Add-Content -LiteralPath $Script:LogFile -Value ("[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $Text) -Encoding UTF8
    } catch { }
}
function Show-Title([string]$Text) { Write-Host ''; Write-Host "== $Text ==" -ForegroundColor Cyan; Write-Log "== $Text" }
function Show-Ok([string]$Text)    { Write-Host "  [完成] $Text" -ForegroundColor Green; Write-Log "OK  $Text" }
function Show-Warn([string]$Text)  { Write-Host "  [注意] $Text" -ForegroundColor Yellow; Write-Log "WARN $Text" }
function Show-Err([string]$Text)   { $Script:Errors++; Write-Host "  [錯誤] $Text" -ForegroundColor Red; Write-Log "ERR $Text" }
function Show-Info([string]$Text)  { Write-Host "    $Text" -ForegroundColor Gray; Write-Log "    $Text" }

function Stop-WithError([string]$Text) {
    Show-Err $Text
    Write-Host ''
    Write-Host "  詳細記錄：$Script:LogFile" -ForegroundColor DarkGray
    exit 1
}

function Get-ModName([string]$Name) { $Name.Substring(0, $Name.Length - $Script:OrigSuffix.Length) + $Script:ModSuffix }

function Test-IsGameDir([string]$Dir) {
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    try { return [System.IO.File]::Exists([System.IO.Path]::Combine($Dir, 'ROB RUN.exe')) } catch { return $false }
}

function Get-SteamLibraries {
    $libs = New-Object System.Collections.Generic.List[string]
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        $steam = $null
        try { $steam = (Get-ItemProperty -Path $key -ErrorAction Stop).SteamPath } catch { }
        if (-not $steam) { try { $steam = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallPath } catch { } }
        if (-not $steam) { continue }
        $steam = $steam -replace '/', '\'
        if (-not $libs.Contains($steam)) { $libs.Add($steam) }
        $vdf = [System.IO.Path]::Combine($steam, 'steamapps', 'libraryfolders.vdf')
        if ([System.IO.File]::Exists($vdf)) {
            foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($vdf), '"path"\s*"([^"]+)"')) {
                $p = $m.Groups[1].Value -replace '\\\\', '\'
                if (-not $libs.Contains($p)) { $libs.Add($p) }
            }
        }
    }
    return $libs
}

function Find-GameDir([string]$Hint) {
    if ($Hint) {
        $h = $Hint.Trim().Trim('"')
        if ($h.ToLower().EndsWith('.exe')) { $h = [System.IO.Path]::GetDirectoryName($h) }
        if (Test-IsGameDir $h) { return $h }
    }
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($lib in Get-SteamLibraries) { $candidates.Add([System.IO.Path]::Combine($lib, 'steamapps', 'common', 'Rob Run')) }
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        try { if (-not $drive.IsReady) { continue } } catch { continue }
        foreach ($rel in 'SteamLibrary\steamapps\common\Rob Run', 'Steam\steamapps\common\Rob Run',
                         'Program Files (x86)\Steam\steamapps\common\Rob Run', 'Program Files\Steam\steamapps\common\Rob Run',
                         'Games\Steam\steamapps\common\Rob Run', 'Games\SteamLibrary\steamapps\common\Rob Run') {
            $candidates.Add([System.IO.Path]::Combine($drive.RootDirectory.FullName, $rel))
        }
    }
    foreach ($c in $candidates) { if (Test-IsGameDir $c) { return $c } }
    return $null
}

function Read-GameDirFromUser {
    Show-Warn '找不到遊戲資料夾。'
    Show-Info '請在 Steam 對遊戲按右鍵 → 管理 → 瀏覽本機檔案，把開啟的資料夾路徑貼到下面（或把資料夾拖進這個視窗）。'
    for ($i = 0; $i -lt 3; $i++) {
        $answer = Read-Host '  遊戲資料夾'
        if ([string]::IsNullOrWhiteSpace($answer)) { return $null }
        $answer = $answer.Trim().Trim('"')
        if ($answer.ToLower().EndsWith('.exe')) { $answer = [System.IO.Path]::GetDirectoryName($answer) }
        if (Test-IsGameDir $answer) { return $answer }
        Show-Warn "這個資料夾裡沒有 ROB RUN.exe：$answer"
    }
    return $null
}

function Get-GamePaths([string]$GameDir, [string]$CacheRoot) {
    $aa = [System.IO.Path]::Combine($GameDir, 'ROB RUN_Data', 'StreamingAssets', 'aa')
    $win = [System.IO.Path]::Combine($aa, 'StandaloneWindows64')
    if (-not $CacheRoot) { $CacheRoot = [System.IO.Path]::Combine($env:USERPROFILE, 'AppData', 'LocalLow', 'Kefir', 'ROB RUN') }
    [pscustomobject]@{
        Aa       = $aa
        Win      = $win
        Catalog  = [System.IO.Path]::Combine($aa, 'catalog.bin')
        Settings = [System.IO.Path]::Combine($aa, 'settings.json')
        CacheDir = [System.IO.Path]::Combine($CacheRoot, 'com.unity.addressables')
    }
}

# 找出遊戲用的 catalog 名稱（例如 catalog_0.1.0），快取檔就叫這個名字
function Get-CatalogName($Paths) {
    if ([System.IO.File]::Exists($Paths.Settings)) {
        try {
            $json = [System.IO.File]::ReadAllText($Paths.Settings) | ConvertFrom-Json
            foreach ($loc in $json.m_CatalogLocations) {
                if ($loc.m_Keys -contains 'AddressablesMainContentCatalogRemoteHash') {
                    $file = ($loc.m_InternalId -split '[\\/]')[-1]
                    if ($file -like 'catalog_*.hash') { return $file.Substring(0, $file.Length - 5) }
                }
            }
        } catch { }
    }
    $hashes = @([System.IO.Directory]::GetFiles($Paths.Win, 'catalog_*.hash'))
    if ($hashes.Count -eq 1) { return [System.IO.Path]::GetFileNameWithoutExtension($hashes[0]) }
    return $null
}

# 在位元組陣列裡把 $From 全部換成等長的 $To，回傳替換次數
function Set-BytesReplaced([byte[]]$Data, [string]$From, [string]$To) {
    $latin1 = [System.Text.Encoding]::GetEncoding(28591)
    $text = $latin1.GetString($Data)
    $toBytes = $latin1.GetBytes($To)
    $count = 0
    $pos = $text.IndexOf($From, [System.StringComparison]::Ordinal)
    while ($pos -ge 0) {
        [System.Array]::Copy($toBytes, 0, $Data, $pos, $toBytes.Length)
        $count++
        $pos = $text.IndexOf($From, $pos + $From.Length, [System.StringComparison]::Ordinal)
    }
    return $count
}

# 用遊戲原版 catalog 重寫快取 catalog；$UseMod 決定是否把 bundle 名稱指向中文化檔案
function Write-CacheCatalog($Paths, [string]$CatalogName, [bool]$UseMod) {
    if (-not [System.IO.Directory]::Exists($Paths.CacheDir)) { [System.IO.Directory]::CreateDirectory($Paths.CacheDir) | Out-Null }
    $data = [System.IO.File]::ReadAllBytes($Paths.Catalog)
    $hits = 0
    if ($UseMod) {
        foreach ($b in $Script:Bundles) { $hits += Set-BytesReplaced $data $b (Get-ModName $b) }
    }
    [System.IO.File]::WriteAllBytes([System.IO.Path]::Combine($Paths.CacheDir, "$CatalogName.bin"), $data)
    $hash = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($Paths.Win, "$CatalogName.hash")).Trim()
    [System.IO.File]::WriteAllText([System.IO.Path]::Combine($Paths.CacheDir, "$CatalogName.hash"), $hash, [System.Text.Encoding]::ASCII)
    return $hits
}

function Get-FileSha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Assert-GameNotRunning([switch]$Skip) {
    if ($Skip) { return }
    if (Get-Process -Name 'ROB RUN' -ErrorAction SilentlyContinue) {
        Stop-WithError '遊戲正在執行。請完全關閉遊戲（工作管理員裡也不能有 ROB RUN.exe）後再試一次。'
    }
}

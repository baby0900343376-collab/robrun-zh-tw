<#
  ROB RUN 繁體中文化 — 安裝

  1. 找到遊戲資料夾
  2. 準備專用的 Python（只在第一次）
  3. 用你電腦上的遊戲原版檔案，產生繁體中文化的資源檔
  4. 以新檔名 *_zht.bundle 放進遊戲資料夾（不修改任何原版檔案）
  5. 改寫使用者資料夾裡的 Addressables 快取 catalog，讓遊戲改讀新檔
  6. 檢查結果

  參數：
    -GameDir  "<遊戲資料夾>"   指定遊戲位置（不指定就自動尋找）
    -DryRun                    只找遊戲、檢查檔案，不做任何修改
    -PythonExe "<python.exe>"  使用已裝好 UnityPy 的 Python（進階）
#>
param(
    [string]$GameDir,
    [switch]$DryRun,
    [string]$PythonExe,
    [string]$CacheRoot,          # 測試用
    [switch]$SkipRunningCheck    # 測試用
)

. (Join-Path $PSScriptRoot 'scripts\common.ps1')

$PyVersion = '3.12.10'
$PyDir     = Join-Path $Script:WorkDir 'python'
$BuildDir  = Join-Path $Script:WorkDir 'build'
$Patcher   = Join-Path $PSScriptRoot 'patcher\patch.py'
$Reqs      = Join-Path $PSScriptRoot 'patcher\requirements.txt'
$DataDir   = Join-Path $PSScriptRoot 'data'
$Wheels    = Join-Path $PSScriptRoot 'wheels'

function Install-PrivatePython {
    # pip 會往 stderr 寫訊息，這裡不能讓它變成例外
    $ErrorActionPreference = 'Continue'
    $ProgressPreference = 'SilentlyContinue'
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

    $py = Join-Path $PyDir 'python.exe'
    $stamp = Join-Path $PyDir 'robrun_ready.txt'
    $want = [System.IO.File]::ReadAllText($Reqs).Trim()
    if ((Test-Path -LiteralPath $py) -and (Test-Path -LiteralPath $stamp) -and ([System.IO.File]::ReadAllText($stamp).Trim() -eq $want)) {
        return $py
    }

    if (-not (Test-Path -LiteralPath $py)) {
        if (Test-Path -LiteralPath $PyDir) { Remove-Item -LiteralPath $PyDir -Recurse -Force }
        New-Item -ItemType Directory -Path $PyDir -Force | Out-Null
        $zip = Join-Path $Script:WorkDir 'python-embed.zip'
        $bundled = Get-ChildItem -LiteralPath $Wheels -Filter 'python-*-embed-amd64.zip' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($bundled) {
            Copy-Item -LiteralPath $bundled.FullName -Destination $zip -Force
        } else {
            Show-Info "下載 Python $PyVersion（python.org）…"
            try { Invoke-WebRequest -UseBasicParsing -Uri "https://www.python.org/ftp/python/$PyVersion/python-$PyVersion-embed-amd64.zip" -OutFile $zip }
            catch { Show-Err "下載 Python 失敗：$($_.Exception.Message)"; return $null }
        }
        Expand-Archive -LiteralPath $zip -DestinationPath $PyDir -Force
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        # 內嵌版 Python 預設不讀 site-packages，要打開
        Get-ChildItem -LiteralPath $PyDir -Filter 'python*._pth' -File | ForEach-Object {
            $t = [System.IO.File]::ReadAllText($_.FullName) -replace '(?m)^#\s*import site', 'import site'
            [System.IO.File]::WriteAllText($_.FullName, $t)
        }
    }

    $pipWheel = Get-ChildItem -LiteralPath $Wheels -Filter 'pip-*.whl' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pipWheel) {
        Show-Info '安裝相依套件（使用附帶的離線檔）…'
        & $py (Join-Path $pipWheel.FullName 'pip') install --disable-pip-version-check --no-warn-script-location --no-index --find-links $Wheels -r $Reqs 2>&1 |
            ForEach-Object { Write-Log "pip: $_" }
    } else {
        Show-Info '安裝相依套件（從 PyPI 下載）…'
        $getPip = Join-Path $Script:WorkDir 'get-pip.py'
        try { Invoke-WebRequest -UseBasicParsing -Uri 'https://bootstrap.pypa.io/get-pip.py' -OutFile $getPip }
        catch { Show-Err "下載 pip 失敗：$($_.Exception.Message)"; return $null }
        & $py $getPip --disable-pip-version-check --no-warn-script-location 2>&1 | ForEach-Object { Write-Log "get-pip: $_" }
        & $py -m pip install --disable-pip-version-check --no-warn-script-location -r $Reqs 2>&1 | ForEach-Object { Write-Log "pip: $_" }
    }
    if ($LASTEXITCODE -ne 0) { Show-Err '安裝相依套件失敗'; return $null }
    & $py -c 'import UnityPy, numpy, PIL' 2>&1 | ForEach-Object { Write-Log "check: $_" }
    if ($LASTEXITCODE -ne 0) { Show-Err '相依套件無法載入'; return $null }
    [System.IO.File]::WriteAllText($stamp, $want)
    return $py
}

# ------------------------------------------------------------------ 主流程
Write-Host ''
Write-Host '  ROB RUN 繁體中文化 — 安裝' -ForegroundColor White
Write-Log '===== install ====='

foreach ($f in $Patcher, $Reqs, (Join-Path $DataDir 'zh-TW.json')) {
    if (-not (Test-Path -LiteralPath $f)) { Stop-WithError "缺少檔案：$f。請重新下載完整的中文化包。" }
}
Assert-GameNotRunning -Skip:$SkipRunningCheck

Show-Title '1/6 尋找遊戲'
$game = Find-GameDir $GameDir
if (-not $game) { $game = Read-GameDirFromUser }
if (-not $game) { Stop-WithError '沒有找到遊戲，安裝取消。' }
Show-Ok "遊戲資料夾：$game"
$paths = Get-GamePaths $game $CacheRoot

foreach ($f in $paths.Catalog) { if (-not [System.IO.File]::Exists($f)) { Stop-WithError "遊戲檔案不完整，找不到 $f" } }
foreach ($b in $Script:Bundles) {
    if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($paths.Win, $b))) { Stop-WithError "找不到遊戲原版檔案 $b。遊戲版本可能不相容。" }
}
$catalogName = Get-CatalogName $paths
if (-not $catalogName) { Stop-WithError '找不到遊戲的 catalog 設定。遊戲版本可能不相容。' }
if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($paths.Win, "$catalogName.hash"))) { Stop-WithError "找不到 $catalogName.hash" }
Show-Ok "遊戲檔案齊全（catalog：$catalogName）"

# 記下原版檔案的大小和時間，最後確認沒被改到
$fingerprint = @{}
foreach ($f in @($paths.Catalog) + ($Script:Bundles | ForEach-Object { [System.IO.Path]::Combine($paths.Win, $_) })) {
    $i = Get-Item -LiteralPath $f
    $fingerprint[$f] = "$($i.Length)|$($i.LastWriteTimeUtc.Ticks)"
}

if ($DryRun) { Write-Host ''; Show-Warn 'DryRun：只做了檢查，沒有修改任何檔案。'; exit 0 }

Show-Title '2/6 準備產生器'
if ($PythonExe) { $py = $PythonExe } else { $py = Install-PrivatePython }
if (-not $py) { Stop-WithError "無法準備 Python。如果是網路問題，請改用附有 wheels 資料夾的發佈包。" }
Show-Ok 'Python 已就緒'

Show-Title '3/6 產生中文化檔案（約 1 分鐘）'
if (Test-Path -LiteralPath $BuildDir) { Remove-Item -LiteralPath $BuildDir -Recurse -Force }
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8 = '1'
$prevEncoding = [Console]::OutputEncoding
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$ErrorActionPreference = 'Continue'
& $py $Patcher --game-dir $paths.Win --data $DataDir --out $BuildDir --report (Join-Path $Script:WorkDir 'patch_report.json') 2>&1 |
    ForEach-Object { Show-Info "$_" }
$patchExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = $prevEncoding } catch { }
if ($patchExit -ne 0) { Stop-WithError '產生中文化檔案失敗，遊戲資料夾沒有被修改。' }
$built = @{}
foreach ($b in $Script:Bundles) {
    $f = Join-Path $BuildDir $b
    if (-not (Test-Path -LiteralPath $f)) { Stop-WithError "產生器沒有輸出 $b" }
    $built[$b] = Get-FileSha256 $f
}
Show-Ok '中文化檔案已產生'

Show-Title '4/6 放進遊戲資料夾'
foreach ($b in $Script:Bundles) {
    Copy-Item -LiteralPath (Join-Path $BuildDir $b) -Destination ([System.IO.Path]::Combine($paths.Win, (Get-ModName $b))) -Force
}
Show-Ok "已放入 $($Script:Bundles.Count) 個 *_zht.bundle"

Show-Title '5/6 讓遊戲讀取中文化檔案'
$hits = Write-CacheCatalog $paths $catalogName $true
if ($hits -lt $Script:Bundles.Count) { Stop-WithError "catalog 裡只找到 $hits 個檔名，遊戲版本可能不相容。請執行「解除安裝.bat」還原。" }
Show-Ok "快取 catalog 已更新（$hits 處）"

Show-Title '6/6 檢查'
foreach ($b in $Script:Bundles) {
    $f = [System.IO.Path]::Combine($paths.Win, (Get-ModName $b))
    if (-not (Test-Path -LiteralPath $f)) { Show-Err "找不到 $(Get-ModName $b)"; continue }
    if ((Get-FileSha256 $f) -ne $built[$b]) { Show-Err "$(Get-ModName $b) 內容不符" }
}
$cacheBin = [System.IO.File]::ReadAllBytes([System.IO.Path]::Combine($paths.CacheDir, "$catalogName.bin"))
$cacheText = [System.Text.Encoding]::GetEncoding(28591).GetString($cacheBin)
foreach ($b in $Script:Bundles) {
    if ($cacheText.IndexOf((Get-ModName $b), [System.StringComparison]::Ordinal) -lt 0) { Show-Err "快取 catalog 沒有指向 $(Get-ModName $b)" }
}
foreach ($f in $fingerprint.Keys) {
    $i = Get-Item -LiteralPath $f
    if ("$($i.Length)|$($i.LastWriteTimeUtc.Ticks)" -ne $fingerprint[$f]) { Show-Err "原版檔案被改動了：$f" }
}
if ($Script:Errors -gt 0) { Stop-WithError "檢查發現 $($Script:Errors) 個問題。請執行「解除安裝.bat」還原，再重新安裝一次。" }
Show-Ok '中文化檔案就位，原版檔案沒有被修改'

Write-Host ''
Write-Host '  安裝完成！' -ForegroundColor Green
Write-Host '  進遊戲後：設定 → 其它 → 語言 → 選「繁體中文」→ 確定' -ForegroundColor White
Write-Host '  （「繁體中文」使用的是原本「俄語」的位置）' -ForegroundColor DarkGray
Write-Log 'install finished'
exit 0

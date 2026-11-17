<#
  ROB RUN 繁體中文化 — 解除安裝

  1. 刪除遊戲資料夾裡的 *_zht.bundle
  2. 用遊戲原版 catalog 重寫快取，讓遊戲回到原版資源
  3. 清除產生器留下的暫存（專用 Python、產生的檔案）

  參數：-GameDir "<遊戲資料夾>"
#>
param(
    [string]$GameDir,
    [string]$CacheRoot,          # 測試用
    [switch]$SkipRunningCheck    # 測試用
)

. (Join-Path $PSScriptRoot 'scripts\common.ps1')

Write-Host ''
Write-Host '  ROB RUN 繁體中文化 — 解除安裝' -ForegroundColor White
Write-Log '===== uninstall ====='
Assert-GameNotRunning -Skip:$SkipRunningCheck

Show-Title '1/3 尋找遊戲'
$game = Find-GameDir $GameDir
if (-not $game) { $game = Read-GameDirFromUser }
if (-not $game) { Stop-WithError '沒有找到遊戲，解除安裝取消。' }
Show-Ok "遊戲資料夾：$game"
$paths = Get-GamePaths $game $CacheRoot

Show-Title '2/3 移除中文化檔案'
$removed = 0
foreach ($b in $Script:Bundles) {
    $f = [System.IO.Path]::Combine($paths.Win, (Get-ModName $b))
    if (Test-Path -LiteralPath $f) {
        try { Remove-Item -LiteralPath $f -Force; $removed++ } catch { Show-Err "刪不掉 $f：$($_.Exception.Message)" }
    }
}
if ($removed -gt 0) { Show-Ok "已刪除 $removed 個 *_zht.bundle" } else { Show-Warn '沒有找到中文化檔案（可能已經解除安裝過）' }

$catalogName = $null
if ([System.IO.File]::Exists($paths.Catalog)) { $catalogName = Get-CatalogName $paths }
if ($catalogName -and [System.IO.File]::Exists([System.IO.Path]::Combine($paths.Win, "$catalogName.hash"))) {
    $cacheBin = [System.IO.Path]::Combine($paths.CacheDir, "$catalogName.bin")
    $needRestore = $true
    if ([System.IO.File]::Exists($cacheBin)) {
        $text = [System.Text.Encoding]::GetEncoding(28591).GetString([System.IO.File]::ReadAllBytes($cacheBin))
        $needRestore = $text.Contains($Script:ModSuffix)
    }
    if ($needRestore) {
        Write-CacheCatalog $paths $catalogName $false | Out-Null
        Show-Ok '快取 catalog 已還原成原版'
    } else {
        Show-Ok '快取 catalog 本來就是原版'
    }
} else {
    Show-Warn '找不到原版 catalog，略過快取還原（下次啟動遊戲時會自動重建）'
}

Show-Title '3/3 清除暫存'
foreach ($sub in 'build', 'python') {
    $d = Join-Path $Script:WorkDir $sub
    if (Test-Path -LiteralPath $d) {
        try { Remove-Item -LiteralPath $d -Recurse -Force; Show-Ok "已清除 $d" } catch { Show-Warn "清不掉 $d：$($_.Exception.Message)" }
    }
}

Write-Host ''
if ($Script:Errors -gt 0) {
    Write-Host "  解除安裝有 $($Script:Errors) 個問題，請看上面的紅字。記錄：$Script:LogFile" -ForegroundColor Red
    exit 1
}
Write-Host '  已回到原版。' -ForegroundColor Green
Write-Log 'uninstall finished'
exit 0

$ErrorActionPreference = 'Stop'
$simDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vsim = 'C:\modeltech64_10.5\win64\vsim.exe'
if (-not (Test-Path -LiteralPath $vsim)) {
    $vsim = 'D:\Quartus\modelsim_ase\win32aloem\vsim.exe'
}
if (-not (Test-Path -LiteralPath $vsim)) {
    $found = Get-Command vsim.exe -ErrorAction SilentlyContinue
    if ($found) { $vsim = $found.Source }
}
if (-not (Test-Path -LiteralPath $vsim)) {
    throw '未找到ModelSim vsim.exe，请先将其加入PATH。'
}

Push-Location $simDir
try {
    $log = Join-Path $simDir 'center_crop_full_split.log'
    & $vsim -c -do 'do run_center_crop_full_split.do' 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) { throw 'ModelSim执行失败。' }
    $text = Get-Content -LiteralPath $log -Raw
    foreach ($name in @('mipi_center_crop_32','gray_edge_display')) {
        if ($text -notmatch "TEST PASSED: $name") {
            throw "未找到通过标志：$name"
        }
    }
    if ($text -match 'TEST FAILED|\*\* Error:|Errors:\s*[1-9]|(?m)^#\s+ERROR\s') {
        throw '日志中发现失败或错误。'
    }
    Write-Host 'TEST PASSED: center_crop_full_split'
} finally {
    Pop-Location
}

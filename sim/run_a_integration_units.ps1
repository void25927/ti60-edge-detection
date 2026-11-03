# 可选自动入口；也可在ModelSim中手动执行run_a_integration_units.do。
param([string]$ModelSimBin = 'C:\modeltech64_10.5\win64')
$ErrorActionPreference = 'Stop'
$vsim = Join-Path $ModelSimBin 'vsim.exe'
if (-not (Test-Path -LiteralPath $vsim)) { throw "Missing simulator: $vsim" }
Push-Location $PSScriptRoot
try {
    $output = @(& $vsim -c -do 'do run_a_integration_units.do; quit -f' 2>&1 |
                ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $logDir = Join-Path $PSScriptRoot 'modelsim_a_integration'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $output | Set-Content -LiteralPath (Join-Path $logDir 'console.log') -Encoding UTF8
    $text = $output -join [Environment]::NewLine
    if ($exitCode -ne 0 -or $text -match 'TEST FAILED|(?im)^#?\s*\*\* Error:|(?im)^#?\s*ERROR:') {
        throw 'A integration unit regression failed.'
    }
    foreach ($test in @('system_mode_controller','ddr_frame_manager','video_ui_overlay','edge_overlay')) {
        if ($text -notmatch "TEST PASSED: $test") { throw "Missing pass marker: $test" }
    }
    Write-Host 'ALL TESTS PASSED: a_integration_units'
} finally {
    Pop-Location
}

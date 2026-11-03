# 可选自动入口；也可在ModelSim中手动执行run_basic.do。
param([string]$ModelSimBin = 'C:\modeltech64_10.5\win64')
$ErrorActionPreference = 'Stop'
$vsim = Join-Path $ModelSimBin 'vsim.exe'
if (-not (Test-Path -LiteralPath $vsim)) { throw "Missing simulator: $vsim" }
Push-Location $PSScriptRoot
try {
    $output = @(& $vsim -c -do 'do run_basic.do; quit -f' 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $output | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'modelsim_basic\console.log') -Encoding UTF8
    $text = $output -join [Environment]::NewLine
    if ($exitCode -ne 0 -or $text -match 'TEST FAILED|(?im)^#?\s*\*\* Error:|(?im)^#?\s*ERROR:') {
        throw 'ModelSim regression failed. See sim/modelsim_basic/console.log'
    }
    foreach ($test in @('rgb888_to_gray','gray_3x3_window','gray_window_stream','median_3x3',
                        'gaussian_3x3','sobel_3x3','gradient_threshold','canny_nms',
                        'canny_double_threshold','canny_hysteresis','debounce',
                        'key_event_controller','system_mode_controller','threshold_controller',
                        'ddr_frame_manager','video_ui_overlay','mipi_center_crop_32',
                        'gray_edge_display','edge_video_pipeline','edge_overlay')) {
        if ($text -notmatch "TEST PASSED: $test") { throw "Missing pass marker: $test" }
    }
    if ($text -notmatch 'ALL TESTS PASSED: a_integrated_advanced_edge_video') { throw 'Regression did not finish.' }
    Write-Host 'ALL TESTS PASSED: a_integrated_advanced_edge_video'
} finally {
    Pop-Location
}

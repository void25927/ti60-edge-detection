# 独立Ti60综合；产物保存在sim/efinity_basic，不改正式工程输出。
param([string]$EfinityBin = 'C:\Efinity\2023.2\bin')
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $PSScriptRoot ('efinity_basic\run_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$map = Join-Path $EfinityBin 'efx_map.exe'
if (-not (Test-Path -LiteralPath $map)) { throw "Missing synthesis tool: $map" }

$ispNames = @('rgb888_to_gray','gray_3x3_window','median_3x3','gaussian_3x3',
              'sobel_3x3','gradient_threshold','canny_nms','canny_double_threshold',
              'canny_hysteresis','canny_edge_pipeline','mipi_center_crop_32',
              'gray_edge_display','edge_video_pipeline')
$controlNames = @('debounce','key_event_controller','system_mode_controller','threshold_controller')
$axiNames = @('ddr_frame_manager')
$uiNames = @('font_rom_8x16','video_ui_overlay')
$sourceFiles = @($ispNames | ForEach-Object { Join-Path $projectDir "src\isp\$_.v" })
$sourceFiles += @($controlNames | ForEach-Object { Join-Path $projectDir "src\control\$_.v" })
$sourceFiles += @($axiNames | ForEach-Object { Join-Path $projectDir "src\axi\$_.v" })
$sourceFiles += @($uiNames | ForEach-Object { Join-Path $projectDir "src\ui\$_.v" })
$tops = @('median_3x3','gaussian_3x3','sobel_3x3','gradient_threshold',
          'canny_nms','canny_double_threshold','canny_hysteresis',
          'debounce','key_event_controller','system_mode_controller','threshold_controller',
          'ddr_frame_manager','video_ui_overlay',
          'canny_edge_pipeline','edge_video_pipeline')

New-Item -ItemType Directory -Path $runDir | Out-Null
$previousEfinityHome = $env:EFINITY_HOME
$env:EFINITY_HOME = (Split-Path -Parent $EfinityBin).Replace('\','/')
try {
    foreach ($top in $tops) {
        $caseDir = Join-Path $runDir $top
        $workDir = Join-Path $caseDir 'work'
        $outputDir = Join-Path $caseDir 'outflow'
        New-Item -ItemType Directory -Path $workDir,$outputDir | Out-Null
        $arguments = @('--project',$top,'--root',$top,'--family','Titanium','--device','Ti60F225',
                       '--work-dir',$workDir,'--output-dir',$outputDir,
                       '--write-efx-verilog',(Join-Path $outputDir "$top.map.v"))
        foreach ($file in $sourceFiles) { $arguments += @('--v',$file) }
        $output = @(& $map @arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
        $output | Set-Content -LiteralPath (Join-Path $caseDir 'synthesis.log') -Encoding UTF8
        $text = $output -join [Environment]::NewLine
        if ($exitCode -ne 0 -or $text -match '(?im)\bVERI-ERROR\b|\[EFX-\d+ ERROR\]') {
            throw "Synthesis failed: $top. See $caseDir"
        }
        $report = Get-Content -LiteralPath (Join-Path $outputDir "$top.map.rpt") -Raw
        $netlist = Get-Content -LiteralPath (Join-Path $outputDir "$top.map.v") -Raw
        if ($report -match '(?m)^EFX_(DSP\w*|MULT|LATCH)\s*:\s*[1-9]' -or
            $netlist -match '(?m)^\s*EFX_(DSP\w*|MULT|LATCH)\s+\S+') {
            throw "Unexpected DSP, multiplier or latch: $top"
        }
        if ($text -match '(?i)inferred.*latch|latch.*inferred|combinational loop.*(found|detected)') {
            throw "Review latch/loop diagnostic: $top"
        }
        Write-Host "SYNTHESIS PASSED: $top"
    }
    Write-Host "Reports: $runDir"
} finally {
    $env:EFINITY_HOME = $previousEfinityHome
}

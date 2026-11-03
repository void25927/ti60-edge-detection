# RGB888转灰度模块XSIM自检脚本

$ErrorActionPreference = "Stop"

# Vivado 2020.2工具目录
$vivadoBin = "C:\Xilinx\Vivado\2020.2\bin"

$xvlog = Join-Path $vivadoBin "xvlog.bat"
$xelab = Join-Path $vivadoBin "xelab.bat"
$xsim  = Join-Path $vivadoBin "xsim.bat"

# 根据脚本位置定位正式源码
$projectDir = Split-Path -Parent $PSScriptRoot
$rtlFile = Join-Path $projectDir "src\isp\rgb888_to_gray.v"
$tbFile  = Join-Path $PSScriptRoot "rgb888_to_gray_tb.v"

# 每次仿真使用独立临时目录
$runTime = Get-Date -Format "yyyyMMdd_HHmmss"
$workDir = Join-Path $env:TEMP "rgb888_to_gray_xsim_$runTime"

function Test-RequiredFile
{
    param
    (
        [string]$FilePath
    )

    if (-not (Test-Path -LiteralPath $FilePath))
    {
        throw "找不到文件：$FilePath"
    }
}

function Invoke-XsimTool
{
    param
    (
        [string]$StageName,
        [string]$ToolPath,
        [string[]]$ToolArguments,
        [string]$LogPath
    )

    Write-Host ""
    Write-Host "========== $StageName ==========" -ForegroundColor Cyan

    $outputLines = @(
        & $ToolPath @ToolArguments 2>&1 |
            ForEach-Object { $_.ToString() }
    )

    $toolExitCode = $LASTEXITCODE

    $outputLines |
        Set-Content -LiteralPath $LogPath -Encoding UTF8

    $outputLines |
        ForEach-Object { Write-Host $_ }

    if ($toolExitCode -ne 0)
    {
        throw "$StageName 失败，退出码：$toolExitCode"
    }

    return ($outputLines -join [Environment]::NewLine)
}

try
{
    Test-RequiredFile $xvlog
    Test-RequiredFile $xelab
    Test-RequiredFile $xsim
    Test-RequiredFile $rtlFile
    Test-RequiredFile $tbFile

    New-Item `
        -ItemType Directory `
        -Path $workDir `
        -Force |
        Out-Null

    Write-Host "RTL文件：$rtlFile"
    Write-Host "Testbench：$tbFile"
    Write-Host "临时目录：$workDir"

    Push-Location $workDir

    $allOutput = ""

    # 1. Verilog语法分析
    $allOutput += Invoke-XsimTool `
        -StageName "xvlog语法检查" `
        -ToolPath $xvlog `
        -ToolArguments @(
            $rtlFile,
            $tbFile
        ) `
        -LogPath (Join-Path $workDir "01_xvlog.log")

    # 2. 展开仿真设计
    $allOutput += Invoke-XsimTool `
        -StageName "xelab设计展开" `
        -ToolPath $xelab `
        -ToolArguments @(
            "rgb888_to_gray_tb",
            "-debug",
            "typical",
            "-s",
            "rgb888_to_gray_tb_sim"
        ) `
        -LogPath (Join-Path $workDir "02_xelab.log")

    # 3. 运行自检仿真
    $allOutput += Invoke-XsimTool `
        -StageName "XSIM自检仿真" `
        -ToolPath $xsim `
        -ToolArguments @(
            "rgb888_to_gray_tb_sim",
            "-runall"
        ) `
        -LogPath (Join-Path $workDir "03_xsim.log")

    # 检查日志结果
    if ($allOutput -match "TEST FAILED")
    {
        throw "testbench报告TEST FAILED"
    }

    if ($allOutput -match "(?im)^\s*ERROR:")
    {
        throw "仿真日志中发现ERROR"
    }

    if ($allOutput -notmatch "TEST PASSED: rgb888_to_gray")
    {
        throw "未找到TEST PASSED标志"
    }

    Write-Host ""
    Write-Host "TEST PASSED: rgb888_to_gray" -ForegroundColor Green
    Write-Host "仿真临时文件：$workDir"
}
catch
{
    Write-Host ""
    Write-Host "TEST FAILED: rgb888_to_gray" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "请根据上方第一条ERROR检查源码。"
    exit 1
}
finally
{
    Pop-Location -ErrorAction SilentlyContinue
}
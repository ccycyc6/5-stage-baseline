<#
.SYNOPSIS
  Upload a 32x32 raw frame to the ARES-P4 vision demo over the board UART.

.DESCRIPTION
  Sends "u", waits for the firmware prompt, writes exactly 1024 bytes and
  prints whatever the board sends back (preview + classification + timing).
  Uses System.IO.Ports, so no extra packages are needed.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\send_image.ps1 -Port COM3 -Raw build\demo_circle.raw

.EXAMPLE
  # interactive: just watch the board, then press u manually
  powershell -ExecutionPolicy Bypass -File tools\send_image.ps1 -Port COM3
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Port,
    [int]$Baud = 115200,
    [string]$Raw = "",
    [int]$ReadyTimeoutSec = 10,
    [int]$ResultTimeoutSec = 8
)

$ErrorActionPreference = "Stop"

function Read-Until {
    param($sp, [string]$Pattern, [int]$TimeoutSec, [System.Text.StringBuilder]$Buf)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $chunk = $sp.ReadExisting()
        if ($chunk) {
            [void]$Buf.Append($chunk)
            Write-Host -NoNewline $chunk
            if ($Buf.ToString() -match [regex]::Escape($Pattern)) { return $true }
        }
        Start-Sleep -Milliseconds 40
    }
    return $false
}

if ($Raw) {
    if (-not (Test-Path -LiteralPath $Raw)) { throw "raw file not found: $Raw" }
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Raw).Path)
    if ($bytes.Length -ne 1024) {
        throw ("raw file must be exactly 1024 bytes (32x32), got {0}. Use tools/img2raw.py first." -f $bytes.Length)
    }
}

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, "None", 8, "One"
$sp.ReadTimeout = 200
$sp.WriteTimeout = 2000
$sp.DtrEnable = $false
$sp.RtsEnable = $false
$sp.Open()
Write-Host ("opened {0} @ {1} 8N1" -f $Port, $Baud) -ForegroundColor Cyan

$buf = New-Object System.Text.StringBuilder
try {
    Start-Sleep -Milliseconds 300
    [void]$sp.ReadExisting()

    if ($Raw) {
        $sp.Write("u")
        Write-Host "sent u, waiting for the upload prompt ..." -ForegroundColor Yellow
        if (-not (Read-Until -sp $sp -Pattern "ready for 1024 bytes" -TimeoutSec $ReadyTimeoutSec -Buf $buf)) {
            throw "board did not answer with the upload prompt (is the vision bitstream loaded, 115200 8N1?)"
        }
        Start-Sleep -Milliseconds 100
        $sp.Write($bytes, 0, $bytes.Length)
        Write-Host ("`nsent {0} bytes, waiting for the result ..." -f $bytes.Length) -ForegroundColor Yellow
        [void](Read-Until -sp $sp -Pattern "classify took" -TimeoutSec $ResultTimeoutSec -Buf $buf)
        Start-Sleep -Milliseconds 300
        $tail = $sp.ReadExisting()
        if ($tail) { [void]$buf.Append($tail); Write-Host -NoNewline $tail }
    } else {
        Write-Host "no -Raw given: showing 15 s of board output, type u in your own terminal to upload" -ForegroundColor Yellow
        [void](Read-Until -sp $sp -Pattern "__never__" -TimeoutSec 15 -Buf $buf)
    }
} finally {
    $sp.Close()
}

Write-Host ""
$text = $buf.ToString()
if ($text -match "result:\s*(\S+)") {
    Write-Host ("CLASS = {0}" -f $Matches[1]) -ForegroundColor Green
}
if ($text -match "distance\s+(\d+)") {
    Write-Host ("distance = {0}" -f $Matches[1]) -ForegroundColor Green
}
if ($text -match "classify took\s+(\d+) cycles") {
    Write-Host ("latency = {0} cycles" -f $Matches[1]) -ForegroundColor Green
}

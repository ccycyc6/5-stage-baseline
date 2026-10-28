<#
.SYNOPSIS
  Upload a firmware image to the ARES-S1 UART boot loader.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\upload.ps1 -Port COM5 -File build\fw\b4_hello.bin
#>
param(
    [string]$Port = "COM5",
    [Parameter(Mandatory = $true)][string]$File,
    [int]$Baud = 115200
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $File)) { throw "image not found: $File" }
$payload = [System.IO.File]::ReadAllBytes((Resolve-Path $File))
if ($payload.Length -eq 0) { throw "image is empty" }
if ($payload.Length -gt 0x20000) { throw "image larger than 128 KiB" }

# Payload checksum: 32-bit sum of bytes, little endian on the wire.
$sum = 0
foreach ($b in $payload) { $sum = ($sum + $b) -band 0xFFFFFFFF }

$frame = New-Object System.IO.MemoryStream
$magic = [System.Text.Encoding]::ASCII.GetBytes("ARS1")
$frame.Write($magic, 0, 4)
$frame.Write([BitConverter]::GetBytes([uint32]$payload.Length), 0, 4)
$frame.Write($payload, 0, $payload.Length)
$frame.Write([BitConverter]::GetBytes([uint32]$sum), 0, 4)
$bytes = $frame.ToArray()

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, "None", 8, "One"
$sp.ReadTimeout = 500
$sp.Open()
Start-Sleep -Milliseconds 100
$sp.DiscardInBuffer()

Write-Host ("upload: {0} bytes payload, checksum 0x{1:X8}, {2} bytes on the wire" -f $payload.Length, $sum, $bytes.Length)
$sp.Write($bytes, 0, $bytes.Length)

# Echo whatever the loader and the new firmware say for a couple of seconds.
$deadline = (Get-Date).AddSeconds(2)
$text = ""
while ((Get-Date) -lt $deadline) {
    try { $text += $sp.ReadExisting() } catch { }
    Start-Sleep -Milliseconds 50
}
$sp.Close()
Write-Host $text

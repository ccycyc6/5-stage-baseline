<#
.SYNOPSIS
  Upload a firmware image to the ARES-S1 UART boot loader.

.DESCRIPTION
  The serial port is exclusive on Windows: close any serial terminal
  (sscom, PuTTY, MobaXterm, another PowerShell) that has the port open
  before running this.  The script prints everything the loader and the
  freshly started firmware say for a few seconds after the transfer.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\upload.ps1 -Port COM9 -File build\fw\b4_hello.bin
#>
param(
    [string]$Port = "COM5",
    [Parameter(Mandatory = $true)][string]$File,
    [int]$Baud = 115200,
    [int]$ListenSeconds = 4
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
try {
    $sp.Open()
}
catch [System.UnauthorizedAccessException] {
    throw ("$Port is already open. Close every serial terminal that holds it " +
           "(sscom / PuTTY / MobaXterm / another PowerShell), then run again.")
}
catch {
    throw ("cannot open $Port : " + $_.Exception.Message +
           "  (wrong port number, or the USB-UART is unplugged)")
}

Start-Sleep -Milliseconds 100
$sp.DiscardInBuffer()

Write-Host ("upload: {0} bytes payload, checksum 0x{1:X8}, {2} bytes on the wire" -f $payload.Length, $sum, $bytes.Length)
$sp.Write($bytes, 0, $bytes.Length)
$sp.BaseStream.Flush()

# Transmission itself takes payload/11520 seconds; then the loader prints and
# jumps, and the new firmware prints.  Listen long enough to catch all of it.
$deadline = (Get-Date).AddSeconds($ListenSeconds)
$text = ""
while ((Get-Date) -lt $deadline) {
    try { $text += $sp.ReadExisting() } catch { }
    Start-Sleep -Milliseconds 50
}
$sp.Close()

if ($text.Length -eq 0) {
    Write-Host "upload: no reply. Is the B4 bitstream running (banner printed at power-up)?"
} else {
    Write-Host "----- board says -----"
    Write-Host $text
}

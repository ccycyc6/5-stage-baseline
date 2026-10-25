<#
.SYNOPSIS
  One-shot board build for the Pangu 200Pro+ (PG2L200H-6IFBB676): firmware ->
  $readmemh image -> ADS-compatible RTL copy -> PDS compile/synth/PNR/bitstream.

.DESCRIPTION
  1. tools/build_win.ps1 builds the firmware image with board settings
     (UART_DIV, CPU_HZ) and emits <target>/<target>.hex.
  2. The hex is copied to fpga/pango/syn/fw.hex, which is the $readmemh image
     the on-chip memory model inside the SoC loads at configuration time.
  3. tools/pango_prep.py mirrors rtl/**/*.sv into a .v tree and rewrites the
     SystemVerilog constructs Pango ADS cannot parse.
  4. pds_shell runs fpga/pango/flow_board.tcl: compile -> synthesize -ads ->
     dev_map -> pnr -> report_timing -> gen_bit_stream.

.EXAMPLE
  pwsh -File tools\build_board.ps1
  pwsh -File tools\build_board.ps1 -Target yolo -Iterations 200
  pwsh -File tools\build_board.ps1 -FlowOnly
#>
[CmdletBinding()]
param(
    [ValidateSet("coremark","yolo","smp","vision")]
    [string]$Target = "coremark",
    [int]$Iterations = 1000,
    [int]$UartDiv = 234,
    [int]$CpuHz = 27000000,
    [string]$PdsRoot = "D:\PDS_2022.2-SP6.4",
    [string]$ProjectName = "ares_p4",
    [switch]$SkipFirmware,
    [switch]$SkipPrep,
    [switch]$FlowOnly
)

$ErrorActionPreference = "Stop"

if ($PSScriptRoot) { $ToolsDir = $PSScriptRoot } else { $ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Root = (Resolve-Path (Join-Path $ToolsDir "..")).Path
Set-Location $Root

$SynDir   = Join-Path $Root "build\pango\syn"
$HexDst   = Join-Path $SynDir "fw.hex"
$PdsShell = Join-Path $PdsRoot "bin\pds_shell.exe"

Write-Host "=== ARES-P4 board build: $Target ===" -ForegroundColor Cyan
Write-Host "  project : $Root"
Write-Host "  pds     : $PdsShell"
if (-not (Test-Path $PdsShell)) { throw "pds_shell.exe not found at $PdsShell (use -PdsRoot)" }

# ---------------------------------------------------------------- 1. firmware
$fwBin = Join-Path $Root ("build_win\{0}\{0}.bin" -f $Target)
if (-not $FlowOnly -and -not $SkipFirmware) {
    Write-Host "" ; Write-Host "--- [1/4] firmware image ---" -ForegroundColor Cyan
    $pwArgs = @("-ExecutionPolicy","Bypass","-File",(Join-Path $ToolsDir "build_win.ps1"),
              "-Target",$Target,"-Iterations",$Iterations,"-UartDiv",$UartDiv,"-CpuHz",$CpuHz)
    & powershell @pwArgs
    if ($LASTEXITCODE -ne 0) { throw "firmware build failed" }
}
if (-not (Test-Path $fwBin)) { throw "firmware binary missing: $fwBin" }

New-Item -ItemType Directory -Force -Path $SynDir | Out-Null
& python (Join-Path $ToolsDir "fw_hex128.py") $fwBin $HexDst
if ($LASTEXITCODE -ne 0) { throw "firmware image conversion failed" }
$lines = (Get-Content -LiteralPath $HexDst | Measure-Object -Line).Lines
Write-Host ("  firmware image: {0} x 16 B lines ({1} KiB) -> {2}" -f $lines, [math]::Ceiling($lines * 16 / 1024), $HexDst)
Copy-Item -LiteralPath (Join-Path $Root "fpga\pango\flow_board.tcl") -Destination $SynDir -Force

# ---------------------------------------------------------------- 2. RTL prep
if (-not $FlowOnly -and -not $SkipPrep) {
    Write-Host "" ; Write-Host "--- [2/4] ADS-compatible RTL copy ---" -ForegroundColor Cyan
    & python (Join-Path $ToolsDir "pango_prep.py")
    if ($LASTEXITCODE -ne 0) { throw "RTL preparation failed" }

    # Pango ADS rtl-infer mis-merges the colour-bar/OSD constant muxes in
    # ares_video (multiple drivers on _$_VCC_$_ / _$_GND_$_), so the board
    # build uses the register-window stub.  The Verilator build keeps the real
    # video subsystem.
    $vidFile  = Join-Path $SynDir "rtl\soc\video\ares_video.v"
    $stubFile = Join-Path $Root "rtl\soc\video\ares_video_stub.sv"
    $stubTxt  = Get-Content -LiteralPath $stubFile -Raw
    Set-Content -LiteralPath $vidFile -Value ($stubTxt -replace "module ares_video_stub", "module ares_video") -NoNewline
    Remove-Item -LiteralPath (Join-Path $SynDir "rtl\soc\video\ares_video_stub.v") -ErrorAction SilentlyContinue
    Write-Host "  video: ADS-compatible stub substituted for ares_video"
}

# ---------------------------------------------------------------- 3. PDS flow
Write-Host "" ; Write-Host "--- [3/4] PDS compile / synth / PnR / bitstream ---" -ForegroundColor Cyan
Push-Location $SynDir
try {
    & $PdsShell -file (Join-Path $SynDir "flow_board.tcl") -project_name $ProjectName
    $rc = $LASTEXITCODE
} finally { Pop-Location }
if ($rc -ne 0) { throw "PDS flow failed (see $SynDir)" }

# ---------------------------------------------------------------- 4. report
Write-Host "" ; Write-Host "--- [4/4] artifacts ---" -ForegroundColor Cyan
$sbit = Get-ChildItem -Path $SynDir -Recurse -Filter *.sbit -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($sbit) { Write-Host ("  bitstream : {0} ({1:N0} bytes)" -f $sbit.FullName, $sbit.Length) }
else { Write-Warning "no .sbit produced" }

Write-Host "" ; Write-Host "RESULT: bitstream ready" -ForegroundColor Green
Write-Host "Program with:"
Write-Host ("  {0}\bin\cdt_js.exe -port 65420" -f $PdsRoot)
Write-Host ("  {0}\bin\cdt_cfg.exe -file fpga\pango\program.tcl -args {{{1}}}" -f $PdsRoot, $sbit.FullName)
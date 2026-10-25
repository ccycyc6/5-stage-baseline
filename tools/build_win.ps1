<#
.SYNOPSIS
  Windows bare-metal RV32IM firmware build for the ARES-P4 RISC-V SoC (no make required).

.DESCRIPTION
  Compiles the project firmware sources with a prebuilt riscv-none-elf (xPack) GCC
  and emits, per target: <name>.elf, <name>.bin and <name>.hex.

  The .hex file is a $readmemh-style image that is byte-for-byte identical to the
  output of sim/tools/bin2hex.py:
    * flat binary, zero-padded up to a multiple of 4 bytes
    * one 32-bit little-endian word per line
    * 8 lowercase hex digits
    * line endings 'native' by default, i.e. CRLF on Windows, because python's
      text-mode writer uses os.linesep; use -HexEol lf for LF-only output
  With -VerifyHex (default) the generated file is diffed byte-for-byte against
  sim/tools/bin2hex.py when python is on PATH, and the target fails on mismatch.

.PARAMETER Target
  coremark | yolo | smp | all

.PARAMETER Iterations
  CoreMark ITERATIONS count (default 10, matches the Makefile).

.PARAMETER UartDiv
  UART baud divisor compiled in via -DUART_DIV (default 8 = simulation, 868 = board).

.PARAMETER CpuHz
  Core clock in Hz compiled in via -DCPU_HZ (default 100000000; board v1 = 50000000).

.PARAMETER DetImgCount
  YOLO DET_IMG_COUNT (default 1).

.PARAMETER ToolchainBin
  Directory holding riscv-none-elf-gcc.exe. Auto-detected if omitted.

.PARAMETER BuildDir
  Output directory relative to the project root (default build_win).

.PARAMETER Clean
  Remove the target output directory before building.

.PARAMETER VerifyHex
  Cross-check the generated hex against sim/tools/bin2hex.py when python is available.

.PARAMETER HexEol
  Hex line endings: 'native' (default, CRLF on Windows - byte-identical to
  bin2hex.py there) or 'lf'.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\build_win.ps1 -Target all -Iterations 10 -UartDiv 8

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\build_win.ps1 -Target coremark -Iterations 1000 -UartDiv 868

.EXAMPLE
  tools\build_win.ps1 -Target yolo -DetImgCount 1

.NOTES
  Does not use make, does not modify PATH, RTL or firmware sources.
#>
[CmdletBinding()]
param(
    [ValidateSet('coremark','yolo','smp','vision','all')]
    [string]$Target = 'coremark',
    [int]$Iterations = 10,
    [int]$UartDiv = 8,
    [int]$DetImgCount = 1,
    # Core clock compiled into the firmware (CoreMark score normalisation)
    [int]$CpuHz = 100000000,
    [string]$BuildDir = 'build_win',
    [string]$ToolchainBin = '',
    [switch]$Clean,
    [bool]$VerifyHex = $true,
    # 'native' == CRLF on Windows, exactly what sim/tools/bin2hex.py writes there
    # (python text mode uses os.linesep); 'lf' for POSIX-style output.
    [ValidateSet('native','lf')]
    [string]$HexEol = 'native'
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- paths
if ($PSScriptRoot) { $ToolsDir = $PSScriptRoot }
else { $ToolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Root = (Resolve-Path (Join-Path $ToolsDir '..')).Path
Set-Location $Root

$LinkerScript = Join-Path $Root 'firmware\common\linker.ld'
if (-not (Test-Path $LinkerScript)) { throw "linker script not found: $LinkerScript" }

# ---------------------------------------------------------------- toolchain
function Resolve-Toolchain {
    param([string]$Explicit)
    $candidates = @()
    if ($Explicit) { $candidates += $Explicit }
    if ($env:RISCV_GCC_BIN) { $candidates += $env:RISCV_GCC_BIN }
    $candidates += 'E:\qs\toolchain\riscv\bin'
    $candidates += (Join-Path $Root 'toolchain\riscv\bin')

    foreach ($dir in $candidates) {
        if (-not $dir) { continue }
        if (-not (Test-Path $dir)) { continue }
        foreach ($prefix in @('riscv-none-elf','riscv64-unknown-elf','riscv-none-embed','riscv32-unknown-elf')) {
            if (Test-Path (Join-Path $dir "$prefix-gcc.exe")) { return @{ Bin = (Resolve-Path $dir).Path; Prefix = $prefix } }
        }
    }
    foreach ($prefix in @('riscv-none-elf','riscv64-unknown-elf','riscv-none-embed','riscv32-unknown-elf')) {
        $cmd = Get-Command "$prefix-gcc.exe" -ErrorAction SilentlyContinue
        if ($cmd) { return @{ Bin = (Split-Path -Parent $cmd.Source); Prefix = $prefix } }
    }
    throw "No RISC-V bare-metal GCC found. Expected riscv-none-elf-gcc.exe in E:\qs\toolchain\riscv\bin, or pass -ToolchainBin <dir>."
}

$tc   = Resolve-Toolchain -Explicit $ToolchainBin
$Gcc  = Join-Path $tc.Bin "$($tc.Prefix)-gcc.exe"
$Objc = Join-Path $tc.Bin "$($tc.Prefix)-objcopy.exe"
$Size = Join-Path $tc.Bin "$($tc.Prefix)-size.exe"

# ---------------------------------------------------------------- flags
$ArchFlags  = @('-march=rv32im_zicsr_zifencei','-mabi=ilp32')
$CommonFlags = @(
    '-O2','-ffreestanding','-fno-builtin','-nostdlib','-nostartfiles',
    '-mno-relax','-msmall-data-limit=0',
    '-Ifirmware','-Ifirmware/common',"-DUART_DIV=$UartDiv","-DCPU_HZ=$CpuHz"
)

$script:Failures = New-Object System.Collections.ArrayList
$script:Passes   = New-Object System.Collections.ArrayList

function Invoke-Gcc {
    param([string[]]$GccArgs, [string]$Label)
    # Windows PowerShell 5.1 turns native stderr into ErrorRecords and, with
    # $ErrorActionPreference = 'Stop', into a terminating NativeCommandError.
    # Capture stderr through a temp file instead.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $errFile = [System.IO.Path]::GetTempFileName()
    $out = @()
    $err = @()
    try {
        $out = & $Gcc @GccArgs 2> $errFile | ForEach-Object { "$_" }
        $rc = $LASTEXITCODE
        if (Test-Path $errFile) {
            $err = @(Get-Content -LiteralPath $errFile | Where-Object { "$_" -and "$_".Trim() })
        }
    } finally {
        $ErrorActionPreference = $prevEap
        Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
    }
    # PowerShell wraps native stderr in formatted error records; drop that noise
    $noise = 'NativeCommandError|CategoryInfo|FullyQualifiedErrorId|^[+]|^At '
    $err = @($err | Where-Object { "$_" -notmatch $noise })
    $all = @($out) + @($err)
    if ($rc -ne 0) {
        Write-Host "    FAILED: $Label" -ForegroundColor Red
        $all | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkRed }
    } else {
        # keep real diagnostics visible; the custom linker script always emits a benign RWX note
        $all | Where-Object { "$_" -match 'error|warning' -and "$_" -notmatch 'LOAD segment with RWX permissions' } |
            ForEach-Object { Write-Host "      $_" -ForegroundColor DarkYellow }
    }
    return ($rc -eq 0)
}

function Compile-One {
    param([string]$Source, [string]$Object, [string[]]$Extra)
    $a = @($ArchFlags) + @($CommonFlags) + @($Extra) + @('-c', $Source, '-o', $Object)
    Write-Host ("    CC   {0}" -f $Source)
    return (Invoke-Gcc -GccArgs $a -Label $Source)
}

function Convert-BinToHex {
    param([string]$BinPath, [string]$HexPath)
    $data = [System.IO.File]::ReadAllBytes($BinPath)
    $pad = $data.Length % 4
    if ($pad -ne 0) {
        $padded = New-Object byte[] ($data.Length + (4 - $pad))
        [System.Array]::Copy($data, $padded, $data.Length)
        $data = $padded
    }
    $sw = New-Object System.IO.StreamWriter($HexPath, $false, (New-Object System.Text.UTF8Encoding($false)))
    if ($HexEol -eq 'lf') { $sw.NewLine = [string][char]10 }
    else { $sw.NewLine = [System.Environment]::NewLine }   # bin2hex.py uses os.linesep (CRLF on Windows)
    try {
        for ($i = 0; $i -lt $data.Length; $i += 4) {
            [uint32]$w = [uint32]$data[$i]
            $w = $w -bor ([uint32]$data[$i+1] -shl 8)
            $w = $w -bor ([uint32]$data[$i+2] -shl 16)
            $w = $w -bor ([uint32]$data[$i+3] -shl 24)
            $sw.WriteLine(('{0:x8}' -f $w))
        }
    } finally { $sw.Close() }
    return $data.Length
}

function Test-HexMatchesPython {
    param([string]$BinPath, [string]$HexPath)
    $py = Get-Command python -ErrorAction SilentlyContinue
    $conv = [System.IO.Path]::Combine($Root, 'sim', 'tools', 'bin2hex.py')
    if (-not $py -or -not (Test-Path $conv)) { return $null }
    $ref = [System.IO.Path]::GetTempFileName()
    try {
        & $py.Source $conv $BinPath $ref | Out-Null
        if ($LASTEXITCODE -ne 0) { return $null }
        $mine   = [System.IO.File]::ReadAllBytes($HexPath)
        $theirs = [System.IO.File]::ReadAllBytes($ref)
        if ($HexEol -eq 'lf') {
            # bin2hex.py on Windows writes CRLF; compare content only for LF output
            $tmp = New-Object 'System.Collections.Generic.List[byte]'
            foreach ($b in $theirs) { if ($b -ne 13) { $tmp.Add($b) } }
            $theirs = $tmp.ToArray()
        }
        if ($mine.Length -ne $theirs.Length) { return $false }
        for ($i = 0; $i -lt $mine.Length; $i++) { if ($mine[$i] -ne $theirs[$i]) { return $false } }
        return $true
    } finally { Remove-Item $ref -ErrorAction SilentlyContinue }
}

function Build-Target {
    param([string]$Name)

    $outDir = Join-Path (Join-Path $Root $BuildDir) $Name
    if ($Clean -and (Test-Path $outDir)) { Remove-Item $outDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    $sources = @()   # list of @{ Src = ...; Extra = @() }
    switch ($Name) {
        'coremark' {
            $sources += @{ Src = 'firmware\common\start.S';        Extra = @(); SrcName = 'start.S' }
            $sources += @{ Src = 'firmware\common\runtime.c';      Extra = @(); SrcName = 'runtime.c' }
            $cmExtra = @('-Ifirmware/coremark', "-DITERATIONS=$Iterations")
            foreach ($f in @('core_list_join','core_matrix','core_state','core_util','core_portme')) {
                $sources += @{ Src = "firmware\coremark\$f.c"; Extra = $cmExtra; SrcName = "$f.c" }
            }
            # core_main.c defines main(); rename it so firmware/coremark/main.c keeps the entry point
            $sources += @{ Src = 'firmware\coremark\core_main.c'; Extra = ($cmExtra + @('-Dmain=coremark_main')); SrcName = 'core_main.c' }
            $sources += @{ Src = 'firmware\coremark\main.c';      Extra = $cmExtra; SrcName = 'main.c' }
        }
        'yolo' {
            $yExtra = @('-Ifirmware/yolo', "-DDET_IMG_COUNT=$DetImgCount")
            foreach ($f in @('firmware\common\start.S','firmware\common\runtime.c',
                             'firmware\yolo\mt.c','firmware\yolo\mt_net.c',
                             'firmware\yolo\mt_detect.c','firmware\yolo\main.c')) {
                $sources += @{ Src = $f; Extra = $yExtra; SrcName = (Split-Path -Leaf $f) }
            }
        }
        'smp' {
            foreach ($f in @('firmware\common\start.S','firmware\common\runtime.c','firmware\tests\smp_test.c')) {
                $sources += @{ Src = $f; Extra = @(); SrcName = (Split-Path -Leaf $f) }
            }
        }
        'vision' {
            # CPU-only shape recognition demo (no miniTensor): 32x32 frame in,
            # 5 classes out, results on the UART.
            $vExtra = @('-Ifirmware/vision')
            foreach ($f in @('firmware\common\start.S','firmware\common\runtime.c',
                             'firmware\vision\vision_img.c','firmware\vision\vision_main.c')) {
                $sources += @{ Src = $f; Extra = $vExtra; SrcName = (Split-Path -Leaf $f) }
            }
        }
        default { throw "unknown target '$Name'" }
    }

    Write-Host ""
    Write-Host ("=== [$Name] compiling {0} sources -> {1}" -f $sources.Count, $outDir) -ForegroundColor Cyan

    $objs = @()
    $t0 = Get-Date
    foreach ($s in $sources) {
        $objName = [System.IO.Path]::GetFileNameWithoutExtension($s.SrcName) + '.o'
        $obj = Join-Path $outDir $objName
        if (-not (Compile-One -Source $s.Src -Object $obj -Extra $s.Extra)) {
            $null = $script:Failures.Add("$Name : compile $($s.Src)")
            return
        }
        $objs += $obj
    }

    $elf = Join-Path $outDir "$Name.elf"
    $bin = Join-Path $outDir "$Name.bin"
    $hex = Join-Path $outDir "$Name.hex"
    Remove-Item $elf,$bin,$hex -ErrorAction SilentlyContinue

    $linkArgs = @($ArchFlags) + @('-nostdlib','-nostartfiles','-mno-relax',
                                  '-T', (Join-Path $Root 'firmware\common\linker.ld')) + $objs + @('-lgcc','-o',$elf)
    Write-Host ("    LD   {0}" -f $elf)
    if (-not (Invoke-Gcc -GccArgs $linkArgs -Label "link $Name.elf")) {
        $null = $script:Failures.Add("$Name : link")
        return
    }
    if (-not (Test-Path $elf)) {
        $null = $script:Failures.Add("$Name : link produced no ELF")
        return
    }

    & $Objc -O binary $elf $bin
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $bin)) {
        $null = $script:Failures.Add("$Name : objcopy")
        return
    }

    $null = Convert-BinToHex -BinPath $bin -HexPath $hex

    $hexOk = $null
    if ($VerifyHex) { $hexOk = Test-HexMatchesPython -BinPath $bin -HexPath $hex }
    if ($hexOk -eq $false) {
        Write-Host "    hex MISMATCH vs sim/tools/bin2hex.py" -ForegroundColor Red
        $null = $script:Failures.Add("$Name : hex mismatch")
        return
    }

    $elfLen = (Get-Item $elf).Length
    $binLen = (Get-Item $bin).Length
    $hexLen = (Get-Item $hex).Length
    $secs = [int]((Get-Date) - $t0).TotalSeconds
    $hexNote = ''
    if ($hexOk -eq $true) { $hexNote = ' (hex verified vs bin2hex.py)' }

    Write-Host ("    PASS {0}: elf={1:N0} B  bin={2:N0} B  hex={3:N0} B  {4}s{5}" -f $Name, $elfLen, $binLen, $hexLen, $secs, $hexNote) -ForegroundColor Green
    & $Size $elf | ForEach-Object { Write-Host "      $_" }
    $null = $script:Passes.Add([pscustomobject]@{
        Target = $Name; Elf = $elfLen; Bin = $binLen; Hex = $hexLen
        ElfPath = $elf; BinPath = $bin; HexPath = $hex
    })
}

# ---------------------------------------------------------------- main
Write-Host "ARES-P4 RV32IM build (no make)"
Write-Host ("  toolchain : {0}" -f $Gcc)
Write-Host ("  version   : {0}" -f ((& $Gcc --version | Select-Object -First 1)))
Write-Host ("  triple    : {0}" -f (& $Gcc -dumpmachine))
$multi = (& $Gcc @ArchFlags -print-multi-directory)
Write-Host ("  multilib  : {0}  (arch=rv32im_zicsr_zifencei abi=ilp32)" -f $multi)
Write-Host ("  project   : {0}" -f $Root)
Write-Host ("  flags     : {0}" -f (($ArchFlags + $CommonFlags) -join ' '))

$targets = @()
switch ($Target) {
    'all'      { $targets = @('coremark','yolo','smp') }
    default    { $targets = @($Target) }
}

foreach ($t in $targets) { Build-Target -Name $t }

Write-Host ""
Write-Host "================ SUMMARY ================"
foreach ($p in $script:Passes) {
    Write-Host ("  PASS  {0,-9} elf {1,8:N0} B   bin {2,8:N0} B   hex {3,9:N0} B" -f $p.Target, $p.Elf, $p.Bin, $p.Hex) -ForegroundColor Green
    Write-Host ("        {0}" -f $p.ElfPath)
    Write-Host ("        {0}" -f $p.BinPath)
    Write-Host ("        {0}" -f $p.HexPath)
}
foreach ($f in $script:Failures) { Write-Host ("  FAIL  {0}" -f $f) -ForegroundColor Red }
if ($script:Failures.Count -gt 0) {
    Write-Host ("RESULT: FAILED ({0} target(s)/step(s))" -f $script:Failures.Count) -ForegroundColor Red
    exit 1
}
Write-Host ("RESULT: PASS - {0} target(s) built" -f $script:Passes.Count) -ForegroundColor Green
exit 0
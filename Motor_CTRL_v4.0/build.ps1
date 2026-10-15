# Motor_CTRL_v4.0: simulate, synthesize, place, pack and load the Tang Nano 9K.
#
#   .\build.ps1            full flow; writes the flash (image survives power off)
#   .\build.ps1 -Sram      same build, loads SRAM only (lost at power off)
#   .\build.ps1 -NoLoad    build pack.fs, do not touch the board
#   .\build.ps1 -LoadOnly  load the pack.fs already built (add -Sram for SRAM)
#   .\build.ps1 -NoSim     skip tb_motion, tb_pwm and tb_com
#   .\build.ps1 -Seed 5    nextpnr seed
#
# Numbers in config.vh do not re-run the benches: the last PASS is remembered
# in sim.stamp. A change to a .v runs only the benches that read that file.
# Placement starts from the previous pnr.json.
#
# Each openFPGALoader call has a time limit and is killed if it hangs. If the
# USB programmer stops answering: unplug the board, plug it in, -LoadOnly.
#
# Constants: config.vh. A placement failure or LUT4 use over 75 % stops the
# build; the answer is a smaller circuit, not another seed.
param(
    [switch]$Sram,
    [switch]$NoLoad,
    [switch]$LoadOnly,
    [switch]$NoSim,
    [switch]$WriteStamp,
    [int]$Seed = 3
)

$src = @('top.v', 'orch.v', 'adc_master.v', 'format_scan.v', 'motion.v',
         'com_ctrl.v', 'drive.v', 'pwm_timer.v', 'pwm_drv.v',
         'text_pwm.v', 'lcd_master.v', 'btn_sync.v', 'pause_reg.v')
$simBenches = @(
    @{ name = 'tb_motion'; files = @('tb_motion.v', 'motion.v', 'config.vh') },
    @{ name = 'tb_pwm';    files = @('tb_pwm.v', 'drive.v', 'pwm_timer.v', 'pwm_drv.v', 'config.vh') },
    @{ name = 'tb_com';    files = @('tb_com.v', 'com_ctrl.v', 'motion.v',
                                     'drive.v', 'pwm_timer.v', 'pwm_drv.v', 'config.vh') }
)
$lutMax = 75
$lutGoal = 62
$clkMHz = 27

function Step($m) { Write-Host ""; Write-Host "== $m" -ForegroundColor Cyan }
function Fail($m) { Write-Host "ERROR: $m" -ForegroundColor Red; Pop-Location; exit 1 }
function Ok($m)   { Write-Host "   $m" -ForegroundColor Green }

# Hash the bench sources. Integer CFG_ values are blanked, so editing a
# number in config.vh does not invalidate a PASS.
function Get-SimFp($files) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $ms = New-Object System.IO.MemoryStream
    foreach ($f in $files) {
        $name = [Text.Encoding]::UTF8.GetBytes("$f`n")
        $ms.Write($name, 0, $name.Length)
        $text = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $f))
        if ($f -eq 'config.vh') {
            $text = [regex]::Replace($text, '(?m)^(\s*`define\s+CFG_\w+\s+)\d+', '${1}0')
            $text = [regex]::Replace($text, '(?m)//.*$', '')
        }
        $body = [Text.Encoding]::UTF8.GetBytes($text)
        $ms.Write($body, 0, $body.Length)
    }
    return ([BitConverter]::ToString($sha.ComputeHash($ms.ToArray()))).Replace('-', '')
}

function Read-Stamp {
    $map = @{}
    if (Test-Path (Join-Path $PSScriptRoot 'sim.stamp')) {
        foreach ($l in Get-Content (Join-Path $PSScriptRoot 'sim.stamp')) {
            if ($l -match '^(\S+)\s+([0-9A-F]+)$') { $map[$Matches[1]] = $Matches[2] }
        }
    }
    return $map
}

function Save-Stamp($map) {
    $lines = foreach ($k in ($map.Keys | Sort-Object)) { "$k $($map[$k])" }
    Set-Content -Path (Join-Path $PSScriptRoot 'sim.stamp') -Value $lines -Encoding ascii
}

if ($WriteStamp) {
    $map = @{}
    foreach ($b in $simBenches) { $map[$b.name] = Get-SimFp $b.files }
    Save-Stamp $map
    exit 0
}

Push-Location $PSScriptRoot
. (Join-Path $PSScriptRoot '..\oss-cad-suite\environment.ps1')

function Build {
    # ---- config ----
    Step "config.vh"
    $cfg = @{}
    foreach ($l in Get-Content config.vh) {
        if ($l -match '^\s*`define\s+(CFG_\w+)\s+(\d+)') {
            $cfg[$Matches[1]] = [int64]$Matches[2]
            Write-Host ("   {0,-16} {1}" -f $Matches[1], $Matches[2])
        }
    }
    # AD7606 at +-5 V (RANGE to GND): code = mV * 32768 / 5000, 32767 at the top.
    if ($cfg.CFG_POT_MV -lt 1000 -or $cfg.CFG_POT_MV -ge 5000) {
        Fail "CFG_POT_MV debe ir de 1000 a 4999: con +-5 V un riel de 5,000 V o mas satura el ADC"
    }
    $full = [math]::Floor($cfg.CFG_POT_MV * 32768 / 5000)
    $endMv = $cfg.CFG_POT_END * 5000 / 32768
    Write-Host ("   pot: riel {0} mV = codigo {1}, puntas de {2:N0} mV" -f $cfg.CFG_POT_MV, $full, $endMv)
    if (($full - 2 * $cfg.CFG_POT_END) -le 4096) { Fail "CFG_POT_END demasiado grande" }
    if ($cfg.CFG_POT_FILT -gt 12) { Fail "CFG_POT_FILT maximo 12" }
    $step = [math]::Floor(2 * $cfg.CFG_HALL_TH / [math]::Pow(2, $cfg.CFG_HALL_SHIFT))
    Write-Host ("   1 paso del encoder = {0} cuentas" -f $step)
    if ($step -lt 1) { Fail "CFG_HALL_SHIFT demasiado grande: un paso del encoder daria 0 cuentas" }
    if (($cfg.CFG_CLK_HZ / $cfg.CFG_LINE_HZ) -ge 1048576) { Fail "CFG_LINE_HZ minimo 26" }
    # DRV8871: % x 10 = clocks only with 1000 clocks per period; 800 ns minimum pulse.
    if ($cfg.CFG_CLK_HZ / $cfg.CFG_PWM_PERIOD -ne 27000) { Fail "CFG_PWM_PERIOD debe dar 27 kHz (1000 ciclos)" }
    if ($cfg.CFG_PWM_MIN * 1e9 / $cfg.CFG_CLK_HZ -lt 800) { Fail "CFG_PWM_MIN bajo 800 ns" }
    Write-Host ("   PWM 27 kHz, 1 ciclo = 0,1 %, minimo {0:N0} ns" -f ($cfg.CFG_PWM_MIN * 1e9 / $cfg.CFG_CLK_HZ))
    if ($cfg.CFG_STALL_MS -lt 50 -or $cfg.CFG_STALL_MS -gt 1000) { Fail "CFG_STALL_MS de 50 a 1000" }
    if ($cfg.CFG_PULSE_PCT -lt 1 -or $cfg.CFG_PULSE_PCT -gt 100) { Fail "CFG_PULSE_PCT de 1 a 100" }
    if ($cfg.CFG_MAN_X_PCT -lt 1 -or $cfg.CFG_MAN_X_PCT -gt 100) { Fail "CFG_MAN_X_PCT de 1 a 100" }
    if ($cfg.CFG_MAN_Y_PCT -lt 1 -or $cfg.CFG_MAN_Y_PCT -gt 100) { Fail "CFG_MAN_Y_PCT de 1 a 100" }
    if ($cfg.CFG_RESUME -le $cfg.CFG_GATE) { Fail "CFG_RESUME tiene que ser mayor que CFG_GATE" }

    # ---- simulation ----
    if (-not $NoSim) {
        $stamp = Read-Stamp
        $pending = @()
        $fps = @{}
        foreach ($b in $simBenches) {
            $fps[$b.name] = Get-SimFp $b.files
            if ($stamp[$b.name] -ne $fps[$b.name]) { $pending += $b }
        }
        if ($pending.Count -eq 0) {
            Ok "simulacion al dia: solo cambiaron constantes"
        }
        foreach ($b in $pending) {
            Step "iverilog $($b.name)"
            $vfiles = @($b.files | Where-Object { $_ -ne 'config.vh' })
            & iverilog -g2012 -I . -o "$($b.name).vvp" @vfiles
            if ($LASTEXITCODE -ne 0) { Fail "iverilog $($b.name)" }
            $sim = & vvp -n "$($b.name).vvp" 2>&1 | ForEach-Object { "$_" }
            $sim | Where-Object { $_ -match '^(ok|FAIL|PASS|FAILS)' } | ForEach-Object { Write-Host "   $_" }
            if (-not ($sim | Where-Object { $_.Trim() -eq 'PASS' })) { Fail "$($b.name) no paso" }
            $stamp[$b.name] = $fps[$b.name]
            Save-Stamp $stamp
        }
    }

    # ---- yosys ----
    Step "yosys synth_gowin"
    & yosys -q -l yosys.log -p "read_verilog -I. $($src -join ' '); synth_gowin -top top -nodsp -json top.json"
    if ($LASTEXITCODE -ne 0) { Fail "yosys (ver yosys.log)" }
    Ok "top.json"

    # ---- nextpnr ----
    Step "nextpnr-himbaechel (seed $Seed)"
    $np = @('-q', '-l', 'pnr.log', '--json', 'top.json', '--write', 'pnr.json',
            '--device', 'GW1NR-LV9QN88PC6/I5', '--freq', "$clkMHz", '--seed', "$Seed",
            '--vopt', 'family=GW1N-9C', '--vopt', 'cst=board.cst')
    $guide = @()
    if ($null -eq $script:pnrGuide) {
        $help = & nextpnr-himbaechel --help 2>&1 | Out-String
        $script:pnrGuide = $help -match '(?m)--guide\b'
    }
    if ($script:pnrGuide -and (Test-Path pnr.json)) {
        Copy-Item pnr.json pnr.guide.json -Force
        $guide = @('--guide', 'pnr.guide.json')
        Ok "colocacion anterior como guia"
    }
    & nextpnr-himbaechel @np @guide 2>$null
    $pnrExit = $LASTEXITCODE
    if ($pnrExit -ne 0 -and $guide.Count -gt 0) {
        Write-Host "   la guia no sirvio: se coloca de cero" -ForegroundColor Yellow
        & nextpnr-himbaechel @np 2>$null
        $pnrExit = $LASTEXITCODE
    }
    $log = Get-Content pnr.log
    if ($log -match 'Unable to find legal placement') {
        Fail "no cabe en la GW1NR-9: achicar la arquitectura, no cambiar la semilla"
    }
    $lut = $log | Select-String 'LUT4:\s+(\d+)/\s*(\d+)\s+(\d+)%' | Select-Object -Last 1
    if ($lut) {
        $pct = [int]$lut.Matches[0].Groups[3].Value
        Write-Host ("   LUT4 {0}/{1} ({2} %)" -f $lut.Matches[0].Groups[1].Value,
                    $lut.Matches[0].Groups[2].Value, $pct)
        if ($pct -gt $lutMax) { Fail "LUT4 sobre $lutMax %: achicar la arquitectura" }
        if ($pct -gt $lutGoal) { Write-Host "   LUT4 sobre la meta de $lutGoal % del plan PWM" -ForegroundColor Yellow }
    }
    $fmax = $log | Select-String 'Max frequency for clock' | Select-Object -Last 2
    $fmax | ForEach-Object { Write-Host "   $($_.Line.Trim())" }
    $errs = @($log | Select-String '^ERROR')
    $errs | ForEach-Object { Write-Host "   $($_.Line)" -ForegroundColor Red }
    if ($pnrExit -ne 0 -or $errs.Count -gt 0) { Fail "nextpnr (ver pnr.log)" }
    if (-not $fmax -or ($fmax | Where-Object { $_.Line -match 'FAIL' })) {
        Fail "timing no pasa a $clkMHz MHz"
    }
    Ok "pnr.json, 0 errores, PASS a $clkMHz MHz"

    # ---- pack ----
    Step "gowin_pack"
    & gowin_pack -d GW1N-9C --sspi_as_gpio --mspi_as_gpio -o pack.fs pnr.json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path pack.fs)) { Fail "gowin_pack" }
    Ok ("pack.fs {0:N0} bytes" -f (Get-Item pack.fs).Length)
}

function Stop-Loaders {
    Get-Process openFPGALoader -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "   cerrando openFPGALoader que retenia el USB (PID $($_.Id))" -ForegroundColor Yellow
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        $null = $_.WaitForExit(3000)
    }
}

function Unplug($why) {
    Write-Host "   $why" -ForegroundColor Red
    Fail ("el programador USB no responde. Desconecta el USB de la Tang Nano 9K, " +
          "espera 5 s, conectalo y corre:  .\build.ps1 -LoadOnly")
}

# Runs openFPGALoader with a time limit. Sets $script:ldExit (-1 = hung, killed)
# and $script:ldOut (output without the intermediate progress bars).
function Run-Loader($argStr, $timeoutS, [switch]$Quiet) {
    Remove-Item loader.log -ErrorAction SilentlyContinue
    $p = Start-Process cmd.exe -ArgumentList "/c openFPGALoader $argStr > loader.log 2>&1" `
                       -WorkingDirectory $PSScriptRoot -NoNewWindow -PassThru
    $null = $p.Handle
    $t0 = Get-Date
    $script:ldExit = -1
    try {
        while (-not $p.WaitForExit(1000)) {
            $s = [int]((Get-Date) - $t0).TotalSeconds
            if (-not $Quiet) { Write-Host -NoNewline "`r   $s s" }
            if ($s -ge $timeoutS) { break }
            if (Test-Path loader.log) {
                $snap = ''
                try {
                    $fs = [IO.File]::Open((Join-Path $PSScriptRoot 'loader.log'), 'Open', 'Read', 'ReadWrite')
                    $sr = New-Object IO.StreamReader($fs)
                    $snap = $sr.ReadToEnd()
                    $sr.Close()
                } catch { }
                if ($snap -match 'usb bulk write failed|JTAG init failed|unable to open|FTDI purge of TX buffer failed') { break }
            }
        }
        if ($p.HasExited) { $script:ldExit = $p.ExitCode }
    } finally {
        if (-not $p.HasExited) {
            Stop-Loaders
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $Quiet) { Write-Host ("`r   {0:N0} s" -f ((Get-Date) - $t0).TotalSeconds) }
    $raw = if (Test-Path loader.log) { [IO.File]::ReadAllText((Resolve-Path loader.log)) } else { '' }
    $prev = ''
    $script:ldOut = @(foreach ($l in (($raw -replace "\x1b\[[0-9;]*m", '') -split "[`r`n]+")) {
        $l = $l.TrimEnd()
        if (-not $l.Trim() -or $l -eq $prev) { continue }
        if ($l -match '\]\s*[\d.]+\s*%' -and $l -notmatch '100(\.0+)?\s*%') { continue }
        $prev = $l
        $l
    })
}

function Probe {
    Run-Loader '-b tangnano9k --detect' 20 -Quiet
    if ($script:ldExit -ne 0 -or -not ($script:ldOut -match 'idcode')) {
        $script:ldOut | ForEach-Object { Write-Host "   $_" }
        Unplug "openFPGALoader --detect no encontro la FPGA"
    }
}

function Load($what, $flags, $timeoutS) {
    for ($try = 1; $try -le 3; $try++) {
        Step "openFPGALoader $what (intento $try de 3)"
        Stop-Loaders
        Probe
        Run-Loader "-b tangnano9k $flags pack.fs" $timeoutS
        $script:ldOut | ForEach-Object { Write-Host "   $_" }
        if ($script:ldExit -eq 0 -and ($script:ldOut -match 'CRC check\s*:\s*Success')) { return }
        if ($script:ldExit -eq -1) { Write-Host "   colgado mas de $timeoutS s: cerrado" -ForegroundColor Yellow }
        if ($script:ldOut -match 'unable to open|JTAG init failed|usb bulk write failed|FTDI purge of TX buffer failed') {
            Unplug "no se pudo abrir el programador"
        }
        Start-Sleep -Seconds 3
    }
    Fail "openFPGALoader $what sin 'CRC check: Success' en 3 intentos"
}

if ($LoadOnly) {
    if (-not (Test-Path pack.fs)) { Fail "no hay pack.fs: corre .\build.ps1 sin -LoadOnly" }
    $newest = Get-Item (@('config.vh', 'board.cst') + $src) |
              Sort-Object LastWriteTime | Select-Object -Last 1
    if ($newest.LastWriteTime -gt (Get-Item pack.fs).LastWriteTime) {
        Fail "$($newest.Name) cambio despues de pack.fs: corre .\build.ps1 sin -LoadOnly"
    }
} else {
    Build
}

if ($NoLoad) { Pop-Location; exit 0 }

if ($Sram) {
    Load "SRAM" '' 60
    Ok "cargado en SRAM (se pierde al cortar la energia)"
} else {
    Load "flash" '-f' 90
    # The running image only changes after a reconfigure; load SRAM too.
    Load "SRAM" '' 60
    Ok "grabado en flash: arranca con este programa al volver la energia"
}
Pop-Location

# Telemetria del protocolo Lab 206 por el USB-UART de la Tang Nano 9K.
# 115200 8N1. El COM es la UART del BL702, no el JTAG.
#   .\mon.ps1
#   .\mon.ps1 COM11
param([string]$Port = "")

$names = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
if (-not $Port) {
    Write-Host "Puertos:" ($names -join ", ")
    Write-Host "Elige el COM del serial (no el JTAG):  .\mon.ps1 COM11"
    exit 1
}

Write-Host "115200 8N1 en $Port"
Write-Host "PotenciaA,PotenciaB,PotA,PotB,Sensor1,Sensor2,Estado,Settled"
Write-Host "A/1 = eje X, B/2 = eje Y. PotA va con Sensor1, PotB con Sensor2."
Write-Host "PotenciaA/B = % aplicado (+000 si frena o se bloqueo). PWM 27 kHz, mando abierto."
Write-Host "Ordenes: M  B  N  A,pa,pb  T,cx,cy,px,py  I,ix,iy  P,eje,signo,idx  Q,eje,pot,n"
Write-Host "A en %, +-100. Q = n periodos de 37 us a pot %, luego freno (Q,X,60,270 = 10 ms)."
Write-Host "T = AUTO: PotA = cx y PotB = cy, recortadas al maximo de cada eje. AUTO frena."
Write-Host "MANUAL, eje calibrado: el pot lleva el eje ahi. X a CFG_MAN_X_PCT %, Y a CFG_MAN_Y_PCT %."
Write-Host "Estado: RESET MANUAL AUTO BRAKE PULSE PWM_X PWM_Y PWM_XY PWM_0"
Write-Host "Marcas (se borran al encender): x_zero  y_zero  x_final  y_final  reset"
Write-Host "Escribe una orden y Enter para enviarla."
Write-Host ""

$sp = New-Object System.IO.Ports.SerialPort $Port, 115200, 'None', 8, 'One'
$sp.ReadTimeout = 200
$sp.NewLine = "`n"
$sp.DtrEnable = $true
$sp.Open()
$quiet = 0
try {
    while ($true) {
        $typed = $false
        try { $typed = [Console]::KeyAvailable } catch { $typed = $false }
        if ($typed) {
            $cmd = [Console]::ReadLine()
            if ($cmd.Length -gt 0) {
                $sp.Write($cmd + "`n")
                Write-Host ("> " + $cmd)
            }
        }
        try {
            $line = $sp.ReadLine().TrimEnd("`r")
            if ($line.Length -gt 0) {
                $quiet = 0
                Write-Host $line
            }
        } catch [System.TimeoutException] {
            $quiet++
            if ($quiet -ge 15) {
                Write-Host "(sin datos)"
                $quiet = 0
            }
        }
    }
} finally {
    $sp.Close()
}

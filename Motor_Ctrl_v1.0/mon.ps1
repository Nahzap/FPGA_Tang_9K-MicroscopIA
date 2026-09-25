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
Write-Host "PotenciaA,PotenciaB,Sensor1,Sensor2,Estado,Settled"
Write-Host "A = eje X, B = eje Y. Sensor1 = Y, Sensor2 = X."
Write-Host "Ordenes: M  B  N  A,pa,pb  F,refx,refy[,gate]  I,ix,iy  P,eje,signo,idx"
Write-Host ""

$sp = New-Object System.IO.Ports.SerialPort $Port, 115200, 'None', 8, 'One'
$sp.ReadTimeout = 3000
$sp.NewLine = "`n"
$sp.DtrEnable = $true
$sp.Open()
try {
    while ($true) {
        try {
            $line = $sp.ReadLine()
            if ($line.Length -gt 0) {
                Write-Host $line
            }
        } catch [System.TimeoutException] {
            Write-Host "(sin datos)"
        }
    }
} finally {
    $sp.Close()
}

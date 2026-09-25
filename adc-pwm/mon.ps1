# Lee el lazo por el serial USB de la Tang Nano 9K (115200 8N1).
# El COM es la interfaz UART del BL702, no la de JTAG.
#   .\mon.ps1
#   .\mon.ps1 COM5
param([string]$Port = "")

$names = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
if (-not $Port) {
    Write-Host "Puertos:" ($names -join ", ")
    Write-Host "Elige el COM del serial (no el JTAG):  .\mon.ps1 COM5"
    exit 1
}

Write-Host "115200 8N1 en $Port"
Write-Host "eje,pausa,dir,pot,cmp,eff,mov,skip,lock,um/s,rawA,rawB"
Write-Host "pot y cmp en hex. pot 64 = 100 %. Techo X = 10E (270), techo Y = 21C (540)."
Write-Host "um/s en decimal. lock - ninguno, P +, N -, B ambos."
Write-Host "mov/skip = hubo flanco o salto desde la linea anterior."
Write-Host "rawA/rawB = cuentas del Hall en el ADC (hex con signo)."
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

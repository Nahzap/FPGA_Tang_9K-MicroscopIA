# Motor_Ctrl_v1.0

Tang Nano 9K. La FPGA manda los dos DRV8871, lee pots y Hall por el AD7606, y habla el protocolo serial de Lab 206.

Un eje, un encoder, un motor. El encoder mide **tasa de flancos**, no distancia. No hay fin de carrera.

## Pines

| Qué | Dónde |
| --- | --- |
| Reloj 27 MHz | pin 52 |
| ADC SPI | 25–30 (31 es copia de CONVST, sin cable) |
| LCD ST7789 | 47, 48, 49, 76, 77 |
| PWM X IN1 / IN2 | 40 / 35 = J5-13 / 14 |
| PWM Y IN1 / IN2 | 41 / 42 = J5-15 / 16 |
| UART TX | pin 17 → BL702 |
| UART RX | pin 18 ← BL702 |
| Pausa S1 / S2 | pines 3 / 4, PWM a 00 |

Pots 3.3 V: **V3 → X** (ADC ch2), **V4 → Y** (ch3). Centro ≈ 1.65 V = reposo.

Hall que se mueven con el motor X: **V7 / V8** (ch6 / ch7). Con el motor Y: **V5 / V6** (ch4 / ch5).

Motores a 12 V. Hall a 3.3 V.

## Serial

115200 8N1. El STM32 de Lab 206 usa 1 Mbps; el USB-UART de esta placa (BL702) queda en **115200**. Hay que abrir el COM a esa velocidad.

Cabecera una vez, luego líneas CRLF:

```
PotenciaA,PotenciaB,Sensor1,Sensor2,Estado,Settled
```

PotenciaA es el eje X y PotenciaB el Y, con signo. Esta placa no pasa de **±92** en ningún eje. Sensor1 es la medida de Y y Sensor2 la de X: flancos en 64 ms × 64, tope 4095. 36 flancos ≈ 2304, la referencia que pide unos 1000 μm/s cuando más adelante se calibre la distancia.

Órdenes. `\r` se ignora. `\n` cierra la línea.

| Orden | Efecto |
| --- | --- |
| `M` | Manual. El pot manda. Banda ancha; por debajo del umbral, PWM 0; al pasarlo, salta al mínimo que mueve y sube hasta el período. |
| `B` | Freno. IN1 = IN2 = 1. |
| `N` | AUTO en 0,0. Los dos motores en 00. |
| `A,pa,pb` | Potencias firmadas del host. Por encima de ±92 se recorta a ±92. |
| `F,refx,refy[,gate]` | Lazo. Dentro de la puerta el PWM es 0. `gate` es 1..40; si falta, vale 2. |
| `I,invx,invy` | Polaridad del error hacia el motor. |
| `P,eje,signo,idx` | Pulso corto en A/X/0 o B/Y/1. No se tira si llega junto con otras órdenes. |

Al encender está en `M`. S1/S2 cortan el PWM (00) sin cambiar el modo.

Ver la telemetría: `.\mon.ps1 COM11`

## Cómo se graba

Desde `D:\FPGA`, en PowerShell: `.\activate-oss-cad.ps1`. Luego, en esta carpeta:

```
yosys -p "read_verilog top.v orch.v adc_master.v format_scan.v axis_ctl.v com_ctrl.v pwm_timer.v pwm_drv.v text_pwm.v lcd_master.v btn_sync.v pause_reg.v; synth_gowin -top top -nodsp -json top.json"
nextpnr-himbaechel --json top.json --write pnr.json --device GW1NR-LV9QN88PC6/I5 --freq 27 --vopt family=GW1N-9C --vopt cst=board.cst
gowin_pack -d GW1N-9C --sspi_as_gpio --mspi_as_gpio -o pack.fs pnr.json
openFPGALoader -b tangnano9k -f pack.fs
```

El log de nextpnr va a un archivo (`> pnr.log`), no a un filtro de PowerShell. Exigir `CRC check: Success`.

Bancos: `iverilog -g2012 -o tb_axis.vvp axis_ctl.v tb_axis_ctl.v` y lo mismo con `com_ctrl.v tb_com_ctrl.v`. Luego `vvp`.

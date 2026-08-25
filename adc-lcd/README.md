# AD7606 SPI en la LCD de 1″

**Capítulo 5.** Pregunta: ¿los 8 canales de 16 bits del HW-AD7606-F4 se leen por SPI y se ven en la ST7789? ¿El GY-91 (MPU9250) se lee por I2C debajo de esas líneas?

El cable ADC y R1=10 kΩ (R2 vacía) ya estaban. Un reloj 27 MHz. SPI del ADC y SPI de la LCD en pines distintos. I2C del IMU en **33** y **34**. Una conversión ADC y un burst IMU por fotograma. **Una sola FSM recorre V1…V8**; otra recorre el I2C. No hay ocho conversores en paralelo.

---

## 1. Qué deberías ver

Tras ~0.4 s (init LCD) y un fotograma más (primer CONVST):

- Título: `AD7606 SPI +/-5V`
- Ocho líneas `Vn:+d.dddHHHH` — voltios ±5 V (RAGE a GND) y el raw en hex.
- Pie: `BLO` + 4 hex (contador de conversiones, no es el ADC) y `B0 D1` (pin 29 y pin 30 en vivo). `FFFF` / `−0.000V` = DB7 suelto (pull-up). `OK` = BUSY pulsó.
- Debajo: `GY91 I2C 71 OK` (o `NAK` / `..` si el I2C no responde) y seis líneas `AX/AY/AZ` en g y `GX/GY/GZ` en dps. Cian. 17 filas de 8 px; la última pierde 1 px (suele ser vacío del glifo). No hay teleprompter.

LED2 (pin 11) se enciende cuando ya hubo al menos un latch válido.

S1 (pin 3) o S2 (pin 4): congela las cifras; la LCD sigue pintando. En pausa el pin **25** queda en 3.3 V (CONVST DC) y LED2 (pin 11) se queda encendido: sirve para comprobar con el polímetro la seda **25** y CVA del F4.

Con **V1 unido a su G**: V1 cerca de `+0.000` y hex cerca de `0000` (unos LSB de ruido). Los demás canales igual si también están a su G.

Carga en **flash SPI** (`-f`, CRC Success 2026-08-25 16:08). Sobrevive al apagar. Pisa el bitstream anterior.

---

## 2. Por qué es liviano (escaneo)

El AD7606 convierte los 8 canales **a la vez** con un CONVST. El silicio no puede “preguntar solo V3” en el chip; lo que sí se recorre a bajo costo es el **dato**:

1. SPI: un acumulador de 16 bits. Cada 16 clocks se guarda el canal `ch_i` y se pasa al siguiente (`0…7`). No hay shifter de 128 bits.
2. Voltios: un solo `format_scan`. Resta 1000/100/10 hasta agotar el milivoltaje, luego `idx++`. 8 canales en **85 ciclos** de 27 MHz (~3.15 µs, iverilog).
3. LCD: el raster elige la línea `y` y lee el registro ya formateado. No hay ALU en el camino de píxel.

Un intento anterior instanció **ocho** `format_ch` combinacionales: LUT4 **86 %**, ALU **68 %**, nextpnr no terminaba. Esta versión: LUT4 **32 %**, ALU **4 %**, DFF **13 %**, fmax de ruta **70.47 MHz** (PASS a 27 MHz). Queda margen para otros circuitos.

---

## 3. Estructura

```
adc-lcd/
  top.v            frame_done → copia estable + CONVST; sample_done → format_scan
  adc_master.v     RST → CONVST → BUSY → escaneo 8×16 en DOUTA
  format_scan.v    Un datapath; idx 0..7; mV = |raw|*625/4096
  i2c_master.v     PHY I2C open-drain 100 kHz (estiramiento de SCL)
  imu_mpu.v        PWR_MGMT_1, WHO_AM_I, burst 14 B desde 0x3B
  format_imu.v     Un datapath; accel g y gyro dps
  text_adc.v       Fuente 8×8: V1…V8 y debajo GY-91
  lcd_master.v     PHY ST7789 (copia de lcd-params)
  btn_sync.v       Armado al soltar
  pause_reg.v      Latch de pausa
  board.cst
  pack.fs
  tb_format_scan.v
  tb_format_imu.v
  tb_adc_scan.v
  tb_adc_master.v
  tb_i2c_mpu.v
  README.md
```

**Historia de una muestra**

1. `lcd_master` termina un 240×135 → `frame_done`.
2. Si ADC idle, formateo idle y no hay pausa, `top` copia los registros a la pantalla y pulsa `start`.
3. `adc_master`: RST 1 ms; CONVST ~5 µs y se mantiene alto ~20 µs (tCONV) en el pin 25 (CVA y CVB). En PAUSA el pin 25 queda en 3.3 V.
4. Espera BUSY alto y luego bajo (sync 2FF). Timeout ~20 µs → `TOUT` y aun así lee.
5. CS bajo, SCLK sigue en **1**. 128 flancos de **bajada** (MSB válido en el primero; el resto sale en la subida y se muestrea en la bajada).
6. SCLK idle **alto**, **1.6875 MHz** (8+8 ciclos @ 27 MHz). 128 ciclos = 8×16.
7. CS alto. `sample_done` un ciclo → `format_scan` recorre V1…V8.
8. Idle hasta el siguiente fotograma.

Escala: `mV = |raw| * 625 / 4096` (= `* 5000 / 32768`). Signo del raw. Truncado hacia 0.

---

## 4. Pines

| Señal | Pin FPGA |
| --- | --- |
| clk | 52 |
| adc_convst (CVA y CVB) | 25 |
| adc_convstb (copia de CONVST) | 31 |
| adc_reset | 26 |
| adc_cs | 27 |
| adc_sclk (RD) | 28 |
| adc_busy | 29 |
| adc_dout (DB7) | 30 |
| i2c_scl (GY-91 SCL) | 33 |
| i2c_sda (GY-91 SDA) | 34 |
| lcd_resetn | 47 |
| lcd_cs | 48 |
| lcd_rs | 49 |
| lcd_clk | 76 |
| lcd_data | 77 |
| btn0_n S1 | 3 |
| btn1_n S2 | 4 |
| led | 11 |

---

## 5. Medido (2026-08-25 13:07, America/New_York)

| Qué | Valor |
| --- | --- |
| `tb_format_scan` | ALL PASS; 0→+0.000, 32767→+4.999, 0x8000→−5.000, 6554→+1.000, 4096→+0.625 |
| `format_scan` 8 canales | **85 ciclos** (~3.15 µs @ 27 MHz) |
| `tb_adc_master` | ALL PASS (8 palabras distintas, 2FF, BUSY modelado) |
| Reset ADC a idle | 541 ciclos (~20.0 µs; 270+270 RST) |
| Burst + BUSY (sim) | 2238 ciclos hasta `sample_done` (~82.9 µs; BUSY de TB = 40 ciclos) |
| LUT4 | 4802 / 8640 (**55 %**) con GY-91 |
| ALU | 724 / 6480 (**11 %**) |
| DFF | 1676 / 6480 (**25 %**) |
| fmax post-ruta | **28.77 MHz** (PASS @ 27.00 MHz) |
| `tb_format_imu` | ALL PASS; 16384→1.000 g; 131 LSB→1 dps |
| `tb_i2c_mpu` | ALL PASS; WHO=0x71; burst AX/AY/AZ/GX/GY/GZ |
| Carga | SRAM CRC Success, luego **flash SPI** `-f` — **CRC check: Success** (2026-08-25 16:08). Sobrevive al apagar. Un intento `-f` anterior falló el CRC (16:07); el que cuenta es este. |

---

## 6. Rebuild (SRAM)

```powershell
cd D:\FPGA
.\activate-oss-cad.ps1
cd D:\FPGA\adc-lcd
iverilog -o tb_fmt.vvp format_scan.v tb_format_scan.v; vvp tb_fmt.vvp
iverilog -o tb_fimu.vvp format_imu.v tb_format_imu.v; vvp tb_fimu.vvp
iverilog -o tb_m.vvp adc_master.v tb_adc_master.v; vvp tb_m.vvp
iverilog -o tb_imu.vvp i2c_master.v imu_mpu.v tb_i2c_mpu.v; vvp tb_imu.vvp
yosys -p "read_verilog top.v adc_master.v text_adc.v format_scan.v format_imu.v i2c_master.v imu_mpu.v lcd_master.v btn_sync.v pause_reg.v; synth_gowin -top top -nodsp -json top.json"
nextpnr-himbaechel --json top.json --write pnr.json --device GW1NR-LV9QN88PC6/I5 --freq 27 --vopt family=GW1N-9C --vopt cst=board.cst
gowin_pack -d GW1N-9C --sspi_as_gpio --mspi_as_gpio -o pack.fs pnr.json
openFPGALoader -b tangnano9k pack.fs
```

Residente (sobrevive al apagar): `openFPGALoader -b tangnano9k -f pack.fs` — exigir **CRC check: Success**.

---

## 7. Tiempos del HDL (27 MHz)

| Evento | Ciclos | Tiempo |
| --- | --- | --- |
| RST alto / bajo | 27000 + 27000 | 1.00 ms + 1.00 ms |
| CONVST alto (incluye tCONV) | 135 + 540 | 5.00 µs + 20.00 µs |
| Timeout BUSY pegado | 54000 | 2.00 ms |
| Espera post-BUSY y post-CS | 8 | 296 ns |
| Semiperiodo SCLK | 8 | 296 ns (SCLK 1.6875 MHz) |
| Trama SPI | 128 bits | ~76 µs |
| Formato V1…V8 | 85 (sim) | ~3.15 µs |

Datasheet: RST ≥ 50 ns, CONVST ≥ 25 ns, tCONV (OS=0) ~4 µs, SCLK << máximo a VDRIVE 3.3 V.

Índice: [`../README.md`](../README.md). Las notas de planificación viven en `Docs/` local (no se publican en el remoto).

---

## 8. Prueba con GY-61 (ADXL335)

Puente **CVA–CVB** en el F4 y **un** cable al pin **25**. El pin **31** no se usa.

| GY-61 | Destino |
| --- | --- |
| VCC | 3.3 V de la 9K (hueco **24**) |
| GND | GND común |
| X-OUT | F4 **V1** |
| Y-OUT | F4 **V2** |
| Z-OUT | F4 **V3** |
| ST | NC |

V4…V8 cada uno a su **G**. No cruzar con la fuente de **12 V** de los N20 (solo GND común).

Placa plana: V1/V2 ≈ +1.6 V, V3 ≈ +1.9 V. Inclinar: esas tres líneas cambian. Pie **OK**.

---

## 9. GY-91 (MPU9250) por I2C

Pines **33** (SCL) y **34** (SDA). Open-drain + pull-up interno. 3.3 V hueco **24**, GND común. NCS/CSB/SDO del módulo NC. No conectar HDMI: esos pines son DE/VS del conector HDMI.

Tras el init de la LCD (~0.4 s) más ~100 ms de wake del MPU: línea `GY91 I2C 71 OK` (0x73 o 0x70 también cuentan como ID conocido; otro hex sale `ID`). `NAK` = el esclavo no respondió (cable, 5 V, o SDO atado y dirección 0x69 — el HDL reintenta 0x69). `..` = aún en espera.

Accel ±2 g (`g`); gyro ±250 dps (`dps`). Mover la placa: AX/AY/AZ y GX/GY/GZ deben cambiar. Pausa S1/S2 congela también el IMU en pantalla.

**Registro 2026-08-25 16:12 (America/New_York, UTC-4).** En placa y confirmado por el usuario: WHO/ejes bajo V1…V8. Flash SPI **CRC Success** 16:08. Este capítulo es el residente.


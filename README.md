# FPGA Tang Nano 9K — MicroscopIA

**Diseño en la placa:** [`Motor_CTRL_v2.0/`](Motor_CTRL_v2.0/README.md). AD7606 + LCD ST7789 + 2× DRV8871. Los potenciómetros piden un lugar en la guía: 69 mm en X y 52 mm en Y. Se calibra con `x_zero`/`x_final` e `y_zero`/`y_final`. Los dos ejes comparten un solo circuito de posición, con una sola potencia y frenada anticipada: el eje llega sin vibrar. Protocolo serial de Lab 206 a 115200; potencias en % del PWM. Constantes en `Motor_CTRL_v2.0/config.vh`.

**Último reporte de avance, con diagramas de arquitectura:** [2026-09-25 16:15 (UTC-3)](Motor_CTRL_v2.0/README.md#reporte-de-avance--2026-09-25-1615-utc-3).

**Velocidad, la imagen anterior:** [`Motor_Ctrl_v1.0/`](Motor_Ctrl_v1.0/README.md). `adc-pwm/` es el ensayo anterior a esa.

Compilar y grabar la flash desde `Motor_CTRL_v2.0`: `.\build.ps1`. Solo grabar lo ya compilado: `.\build.ps1 -LoadOnly`. Exige **CRC check: Success**.

Pots 3.3 V: **V3 → eje X**, **V4 → eje Y**. Hall que se mueven con X: **V7/V8**. Con Y: **V5/V6**. PWM 50 kHz (`Motor_CTRL_v2.0/config.vh`). Reposo 00. `B` por el serial es freno (11).

| Qué | Dónde |
| --- | --- |
| ADC SPI | FPGA 25–30 |
| LCD ST7789 | 47, 48, 49, 76, 77 |
| PWM X | 40 / 35 = J5-13 / 14 |
| PWM Y | 41 / 42 = J5-15 / 16 |
| Reloj | 27 MHz, pin 52 |

Las notas `Docs/` no van al remoto.

---

## 1. La placa

Sipeed **Tang Nano 9K**. FPGA Gowin **GW1NR-LV9QN88PC6/I5** (familia **GW1N(R)-9C**, idcode `0x100481b`). Reloj de usuario: **27 MHz en el pin 52**. Seis LED activos en bajo (10, 11, 13, 14, 15, 16; el 10 comparte DONE). Botones S1/S2 activos en bajo (pines 3 y 4). LCD **ST7789 SPI 240×135** en el conector 8P. USB-C → **BL702** JTAG (FT2232, `0403:6010`).

No hace falta el IDE de Gowin.

---

## 2. Cómo se programa

1. **Entorno.** PowerShell: `.\activate-oss-cad.ps1`. Carga la OSS CAD Suite de `oss-cad-suite/` (local; no está en este repo).
2. **Yosys** → `top.json`.
3. **nextpnr-himbaechel** con `board.cst` (`--vopt family=GW1N-9C`).
4. **gowin_pack** → `pack.fs` (`-d GW1N-9C --sspi_as_gpio --mspi_as_gpio`).
5. **Carga.** SRAM para un ensayo. **Flash** (`-f`) para que arranque solo. Un `-f` sustituye al bitstream anterior.

En `Motor_CTRL_v2.0` los cinco pasos los hace `build.ps1` (ver [Cómo se graba](Motor_CTRL_v2.0/README.md#cómo-se-graba)). Antes del primer JTAG: Zadig, **WinUSB solo en Interface 0**. Detect: `GW1N(R)-9C`.

Cierre **2026-09-25 16:15 (UTC-3)**. Host: Windows. Remoto: [Nahzap/FPGA_Tang_9K-MicroscopIA](https://github.com/Nahzap/FPGA_Tang_9K-MicroscopIA).

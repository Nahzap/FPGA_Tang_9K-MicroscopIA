# FPGA Tang Nano 9K — MicroscopIA

**Un solo diseño:** AD7606 + LCD ST7789 + 2× DRV8871. Control de **velocidad** por pot + indicadores de encoder **listo**. Siguiente: control de **posición** por encoders.

Carpeta: [`adc-pwm/`](adc-pwm/README.md). Cierre: [`adc-pwm/2026-09-11_1413_control-velocidad.md`](adc-pwm/2026-09-11_1413_control-velocidad.md). Flash: `openFPGALoader -b tangnano9k -f pack.fs`. Exigir **CRC check: Success**.

Pots 3.3 V: **V3 → eje X**, **V4 → eje Y**. Hall A/B: **V5/V6 = X**, **V7/V8 = Y**. Centro al encender = 0 %. PWM 20 kHz, Table 1 (drive ↔ brake). Fin de carrera por stall; el pot manda entero hasta que un tope se traba.

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

Comandos en [`adc-pwm/README.md`](adc-pwm/README.md). Antes del primer JTAG: Zadig, **WinUSB solo en Interface 0**. Detect: `GW1N(R)-9C`.

Cierre **2026-09-11 14:13 (UTC-3)**. Host: Windows. Remoto: [Nahzap/FPGA_Tang_9K-MicroscopIA](https://github.com/Nahzap/FPGA_Tang_9K-MicroscopIA).

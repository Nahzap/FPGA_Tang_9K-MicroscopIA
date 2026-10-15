# FPGA Tang Nano 9K — MicroscopIA

**Diseño en la placa:** [`Motor_CTRL_v4.0/`](Motor_CTRL_v4.0/README.md). AD7606 en ±5 V, LCD ST7789, dos DRV8871 y dos N20 a 12 V. Las guías son 69 mm en X y 52 mm en Y. Se calibra con `x_zero`/`x_final` e `y_zero`/`y_final`. Los dos ejes comparten un solo circuito de posición.

En MANUAL el potenciómetro lleva el eje calibrado a ese lugar al **35 %** (`CFG_MAN_X_PCT` / `CFG_MAN_Y_PCT`) y el puente frena al llegar. La frenada anticipada usa la velocidad del milisegundo ya cerrado. Una inversión espera a que paren los flancos Hall, para no cruzar el pin de 3 V con el que trocea los 12 V. AUTO calcula el pedido y no mueve. El mando abierto (`A`, `N`, `B`, `P`, `Q`) va a 27 kHz.

Registro de esa ley y de lo medido en la platina:

- [2026-10-13 18:54 (UTC-3) — control de posición y eje X](Motor_CTRL_v4.0/docs/2026-10-13_1854_control-de-posicion-y-eje-x.md)
- [2026-10-15 10:13 (UTC-3) — tope al 35 %](Motor_CTRL_v4.0/docs/2026-10-15_1013_tope-35-porciento.md)

Y cierra el lazo. X, con la misma ley y el puente al máximo, avanzó 6 pasos y se quedó: el motor de X no tiene el par. Hay que cambiarlo. El detalle está en el registro del 2026-10-13.

**Imágenes anteriores:** [`Motor_CTRL_v3.0/`](Motor_CTRL_v3.0/README.md), [`Motor_CTRL_v2.0/`](Motor_CTRL_v2.0/README.md), [`Motor_Ctrl_v1.0/`](Motor_Ctrl_v1.0/README.md). `adc-pwm/` es el ensayo anterior a v1.

Compilar y grabar desde `Motor_CTRL_v4.0`: `.\build.ps1`. Solo grabar lo ya compilado: `.\build.ps1 -LoadOnly`. Exige **CRC check: Success** en flash y en SRAM. Si desde el último PASS solo cambiaron números de `config.vh`, no vuelve a simular.

Pots a 5 V: **V3 → eje X**, **V4 → eje Y**. Hall de X: **V7/V8**. Hall de Y: **V5/V6**. PWM 27 kHz. Reposo y pausa: 00. `B` y la llegada al pedido: 11.

| Qué | Dónde |
| --- | --- |
| ADC SPI | FPGA 25–30 |
| LCD ST7789 | 47, 48, 49, 76, 77 |
| PWM X IN1 / IN2 | 40 / 35 |
| PWM Y IN1 / IN2 | 41 / 42 |
| UART TX / RX | 17 / 18, hacia el BL702 |
| Reloj | 27 MHz, pin 52 |

Las notas `Docs/` de la raíz no van al remoto. El registro de control de v4.0 sí: `Motor_CTRL_v4.0/docs/`.

---

## 1. La placa

Sipeed **Tang Nano 9K**. FPGA Gowin **GW1NR-LV9QN88PC6/I5** (familia **GW1N(R)-9C**, idcode `0x100481b`). Reloj de usuario: **27 MHz en el pin 52**. Seis LED activos en bajo (10, 11, 13, 14, 15, 16; el 10 comparte DONE). Botones S1/S2 activos en bajo (pines 3 y 4). LCD **ST7789 SPI 240×135** en el conector 8P. USB-C → **BL702**, visto como FTDI `0403:6010`: interfaz 0 JTAG, interfaz 1 serial.

No hace falta el IDE de Gowin. La FPGA tiene 8640 LUT4. Si la colocación no entra, o el uso pasa de ~75 %, se achica el circuito. No se reintenta la misma red con otra semilla.

---

## 2. Cómo se programa

1. **Entorno.** PowerShell, con `oss-cad-suite` en el `PATH` (`oss-cad-suite/bin` y `oss-cad-suite/lib`). La suite es local y no está en este repo.
2. **Yosys** `synth_gowin -nodsp` → `top.json`.
3. **nextpnr-himbaechel**, semilla 3, familia `GW1N-9C`, `board.cst`. Si hay un `pnr.json` previo, lo usa de guía.
4. **gowin_pack** → `pack.fs` (`-d GW1N-9C --sspi_as_gpio --mspi_as_gpio`).
5. **Carga.** Flash (`-f`) y después SRAM, para que la imagen en marcha sea la grabada. Un `-f` sustituye al bitstream anterior.

Antes del primer JTAG: Zadig, **WinUSB solo en la interfaz 0**. Si el USB corta a mitad (`usb bulk write failed`, `JTAG init failed` o `ftdi_usb_reset` ocupado): desconectar el USB de la Tang Nano, esperar 5 s, conectar y `.\build.ps1 -LoadOnly`. No dejar un `openFPGALoader` colgado.

Cierre de esta imagen: **2026-10-15 10:13 (UTC-3)**. Host: Windows. Remoto: [Nahzap/FPGA_Tang_9K-MicroscopIA](https://github.com/Nahzap/FPGA_Tang_9K-MicroscopIA).

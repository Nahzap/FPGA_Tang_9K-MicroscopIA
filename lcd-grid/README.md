# Grilla turbo — la primera imagen

**Capítulo 3 de 5.** Pregunta: ¿podemos pintar píxeles en la pantalla de ~1″, no solo encender LED?

Hasta aquí el laboratorio hablaba con diodos. Aquí habla con un **ST7789** por SPI. La primera imagen no es un logotipo: es una **rejilla de cuadrados** cuyos colores recorren una paleta tipo turbo. Si ves teselas y las ves cambiar, el init, el raster y el refresh existen.

---

## 1. Qué deberías ver

Tras ~0.4 s (reset y sleep-out del panel), una cuadrícula **24×15**: celdas de 10×9 píxeles que llenan exactamente **240×135** (360 teselas; antes eran 10×5). Líneas negras de 1 px en el borde de cada celda. El relleno recorre **turbo** (azul violáceo → cian → verde → amarillo → rojo) cada **~150 ms**. El segundo LED (pin 11) está apagado durante el init y luego parpadea al ritmo de la paleta.

Si la pantalla queda negra: el cable 8P suele ir al revés. Alinea el pin 1 con la seda de la placa. Si ves la grilla corrida o con una franja negra, los offsets de ventana (X=40…279, Y=53…187) no coinciden con **ese** cristal; son los del ejemplo oficial Sipeed.

Este bitstream **no** conduce la LCD RGB grande por FPC (4.3″ / 5″). Solo el módulo SPI de 1.14″.

Carga típica: SRAM.

---

## 2. Por qué esta imagen y no un bitmap

Un PNG embebido demuestra memoria, no el tubo de vídeo. Una grilla demuestra, en este orden:

1. El panel aceptó la secuencia de init (MADCTL, COLMOD 16-bit, CASET/RASET, RAMWR).
2. El maestro SPI escribe un flujo continuo de RGB565.
3. El raster conoce `x`, `y` y en qué celda está (24 columnas × 15 filas).
4. El color no es ruido: sale de una LUT de 16 entradas más un índice `(cell_x + cell_y + phase)`.

La paleta turbo se aproxima en RGB565 (16 colores). No es matplotlib en el FPGA; es una LUT compacta con el mismo recorrido perceptual.

---

## 3. Estructura — dos archivos, un dueño del bus

```
lcd-grid/
  top.v          Reloj de paleta + LED testigo
  lcd_st7789.v   FSM del panel: reset → init → stream
  board.cst      Reloj, SPI 8P, LED2
  pack.fs
  README.md
```

`top` no habla SPI. Solo cuenta 4_050_000 ciclos (~150 ms @ 27 MHz), incrementa `phase` (4 bits) y instancia `lcd_st7789`. El LED es `~phase[0]` cuando `running` (estado STREAM); si no, queda apagado (nivel alto).

`lcd_st7789` es el **único** dueño de `lcd_clk`, `lcd_data`, `lcd_cs`, `lcd_rs`, `lcd_resetn`.

**Historia del FSM (un estado después del otro):**

1. **RESET** — `lcd_resetn=0` durante 100 ms.
2. **PREPARE** — suelta reset, espera 200 ms.
3. **WAKE** — un byte SPI: comando `0x11` (sleep out).
4. **SNOOZE** — 120 ms, como pide el datasheet / demo Sipeed.
5. **INIT** — 70 palabras de ROM. Bit 8 = comando (`0`) o dato (`1`). Avanza el índice solo cuando el byte SPI terminó (`bit_loop==8`).
6. **STREAM** — cada píxel son 16 bits (byte alto, byte bajo), CS alto un ciclo entre píxeles. Al terminar 240×135, el raster vuelve a (0,0) y sigue. No hay segundo init.

`lcd_clk` es `~clk`: SPI a 13.5 MHz, un bit por ciclo de 27 MHz.

La tesela se calcula **combinacionalmente** a partir de `pix_x/y` descompuestos en `cell_*` y `sub_*`. Si `sub_x==0` o `sub_y==0`, el píxel es negro (línea de grilla). Si no, `turbo_rgb565(cell_x + cell_y + phase)`.

Los delays de reset/sleep son tiempos del **panel**, no una carrera entre dos FSM. El stream no empieza hasta que `cmd_index == INIT_N`.

---

## 4. Pines (conector 8P, ejemplo oficial Sipeed `spi_lcd`)

| Señal | Pin | Oficio |
| --- | --- | --- |
| `clk` | 52 | 27 MHz |
| `lcd_clk` | 76 | SCL |
| `lcd_data` | 77 | MOSI |
| `lcd_cs` | 48 | Chip select |
| `lcd_rs` | 49 | DC (comando/dato) |
| `lcd_resetn` | 47 | Reset activo bajo |
| `led` | 11 | LED2, latido |

No hay GPIO de backlight: en el módulo 8P el BL suele ir a 3V3. Drive 8 y pull-up en las líneas SPI, como el CST de Sipeed.

Offsets: **CASET 40…279**, **RASET 53…187**, `MADCTL=0x70` (landscape MX+MY+MV), `COLMOD=0x05` (16-bit).

---

## 5. Cómo se programa (secuencia)

```powershell
cd D:\FPGA
.\activate-oss-cad.ps1
cd D:\FPGA\lcd-grid

yosys -p "read_verilog top.v lcd_st7789.v; synth_gowin -top top -json top.json"

nextpnr-himbaechel --json top.json --write pnr.json --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C --vopt cst=board.cst

gowin_pack -d GW1N-9C --sspi_as_gpio --mspi_as_gpio -o pack.fs pnr.json

openFPGALoader -b tangnano9k pack.fs
```

Yosys lee **dos** Verilog: el top y el maestro LCD. SRAM por defecto.

```powershell
openFPGALoader -b tangnano9k -f pack.fs
```

pisa el residente. El capítulo 4 es el que se pensó para quedarse en flash.

---

## 6. Qué hereda el siguiente capítulo

`lcd-params` copia la PHY y la ROM de init. No reabre el debate del conector 8P. Añade texto, botones y un teleprompter que **no avanza** hasta que este mismo raster dice “fotograma terminado”.

Volver al índice: [`../README.md`](../README.md).

**Registro 2026-08-25 16:12 (America/New_York, UTC-4).** Historia del laboratorio. Residente en flash: `adc-lcd` (16:08, CRC Success).

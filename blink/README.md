# Blink — el primer signo de vida

**Capítulo 1 de 5.** Pregunta: ¿el bitstream que escribimos en el PC llega al FPGA y mueve un pin real?

Si la respuesta es sí, el resto del laboratorio tiene suelo. Si es no, no tiene sentido hablar de LCD ni de flash.

Lee este archivo de arriba abajo. El circuito es un solo hilo: reloj → contador → LED.

---

## 1. Qué deberías ver

Con la Tang Nano 9K alimentada y este `pack.fs` cargado, el **segundo LED** (pin 11, LED2) parpadea a ~1.24 s de periodo (`cnt[24]` a 27 MHz). Los otros cinco no se tocan. El LED es **activo en bajo**: el Verilog pone `0` para encender.

Al cortar la alimentación el diseño desaparece si solo se cargó en SRAM. Este capítulo no se grabó en flash a propósito: es la prueba de que el tubo de herramientas funciona, no el programa residente.

---

## 2. Por qué este diseño y no otro

Un blink es el equivalente FPGA de “hello world”, pero no es decorativo. Fuerza, en este orden:

1. Un archivo Verilog con un `top` sintético.
2. Un `.cst` que ata nombres de puerto a pines físicos.
3. Yosys `synth_gowin` sin primitivas raras.
4. nextpnr-himbaechel con el part `GW1NR-LV9QN88PC6/I5`.
5. `gowin_pack` y `openFPGALoader -b tangnano9k`.

El pin **11** se elige a propósito. El pin 10 también es LED, pero comparte **DONE**. Si el primer experimento usara el 10, un fallo de empaquetado se confundiría con un fallo de JTAG. Aquí el único grado de libertad visible es “¿parpadea LED2?”.

---

## 3. Estructura — un módulo, un reloj, un pin

```
blink/
  top.v        Circuito
  board.cst    Pines
  pack.fs      Bitstream (se regenera)
  README.md    Este relato
```

No hay FSM, no hay SPI, no hay botones. `top` tiene dos puertos: `clk` y `led`.

**Historia del circuito (en el tiempo del silicio):**

1. El oscilador de 27 MHz entra por el pin 52.
2. Un registro de 25 bits, `cnt`, suma 1 en cada flanco de subida.
3. El bit 24 cambia cada 2²⁴ ciclos ≈ 0.62 s en alto y 0.62 s en bajo.
4. `assign led = ~cnt[24]` invierte el bit porque el LED de la placa enciende con nivel bajo.

Eso es todo el paralelismo que hay: un contador. La documentación no “paraleliza” nada más.

---

## 4. Restricciones físicas

```
IO_LOC  "clk" 52;
IO_PORT "clk" IO_TYPE=LVCMOS33;
IO_LOC  "led" 11;
IO_PORT "led" IO_TYPE=LVCMOS33;
```

`IO_LOC` y `IO_PORT` van en líneas distintas (sintaxis Gowin / Apicula). `LVCMOS33` es el estándar del banco de los LED.

| Señal | Pin | Rol |
| --- | --- | --- |
| `clk` | 52 | 27 MHz |
| `led` | 11 | LED2, activo bajo |

---

## 5. Cómo se programa (secuencia)

En PowerShell, **esta** carpeta, **esta** sesión:

```powershell
cd D:\FPGA
.\activate-oss-cad.ps1
cd D:\FPGA\blink

yosys -p "read_verilog top.v; synth_gowin -top top -json top.json"

nextpnr-himbaechel --json top.json --write pnr.json --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C --vopt cst=board.cst

gowin_pack -d GW1N-9C --sspi_as_gpio --mspi_as_gpio -o pack.fs pnr.json

openFPGALoader -b tangnano9k pack.fs
```

El último comando escribe **SRAM**. Esperado: `CRC check: Success` y LED2 parpadeando.

Para dejarlo residente (sustituye lo que haya en flash):

```powershell
openFPGALoader -b tangnano9k -f pack.fs
```

En este laboratorio el residente habitual es `lcd-params`, no este blink.

---

## 6. Si no parpadea

1. `openFPGALoader -b tangnano9k --detect` debe decir `GW1N(R)-9C` / `0x100481b`.
2. WinUSB en JTAG Interface 0 (Zadig). No tocar el UART.
3. Entorno activado en **la misma** ventana (`activate-oss-cad.ps1`).
4. Estás mirando el **segundo** LED, no el que comparte DONE.

---

## 7. Qué no hace este capítulo

No usa los seis LED, no habla con la LCD, no lee botones, no pretende sobrevivir al apagado. Eso es el capítulo 2 (`led-seq`).

Volver al índice: [`../README.md`](../README.md).

**Registro 2026-08-25 16:12 (America/New_York, UTC-4).** Este capítulo sigue siendo la prueba de JTAG. El bitstream **residente** en flash es `adc-lcd` (ADC + GY-91), CRC Success 16:08.

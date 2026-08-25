# Secuencia de 6 LED — una luz que recorre la placa

**Capítulo 2 de 5.** Pregunta: si el blink demostró un pin, ¿podemos poseer la fila entera, incluido el LED que comparte DONE?

El circuito sigue siendo un solo hilo: reloj → tiempo de paso → rotación one-hot → seis salidas invertidas.

---

## 1. Qué deberías ver

Con el USB-C a la **izquierda** y el HDMI a la **derecha**, los seis LED forman una fila en el borde. Una sola luz encendida avanza **LED1 → LED6** (pines 10 → 11 → 13 → 14 → 15 → 16) y vuelve al primero. Cinco pasos por segundo: **200 ms** por LED, una vuelta cada **1.2 s**.

Activo en bajo: el one-hot interno es `1` = “este LED toca”; la asignación `led = ~chase` lo convierte en el nivel que la placa entiende.

Si el LED del pin 10 (LED1 / DONE) se queda fijo y los otros cinco caminan, el chase de 6 bits sigue siendo correcto: DONE a veces no se deja usar como GPIO. El empaquetado de este capítulo pide `--done_as_gpio` precisamente por eso.

Carga típica: SRAM. Se borra al apagar.

---

## 2. Por qué viene después del blink

El blink aisló el tubo de herramientas. Aquí se añade:

- Un **vector** de salidas, no un bit.
- Un **ritmo** explícito (constante `STEP = 5_400_000` ciclos @ 27 MHz = 200 ms), no un bit suelto del contador.
- El pin **10**, que el capítulo 1 evitó. `gowin_pack` necesita `--done_as_gpio` además de `--sspi_as_gpio --mspi_as_gpio`.

Sin el blink, un fallo aquí no se sabría si es JTAG, CST o DONE. Con el blink ya cerrado, el fallo se localiza.

---

## 3. Estructura

```
led-seq/
  top.v        Contador de paso + registro chase
  board.cst    clk + led[5:0]
  pack.fs      Bitstream
  README.md    Este relato
```

Sigue habiendo un solo módulo `top`. Dos registros:

| Registro | Ancho | Oficio |
| --- | --- | --- |
| `cnt` | 23 bits | Cuenta hasta `STEP-1` |
| `chase` | 6 bits | One-hot. Arranca en `6'b000001` (`led[0]`) |

**Historia del ciclo de reloj, cuando toca avanzar:**

1. `cnt` llega a `STEP-1`.
2. `cnt` vuelve a 0.
3. `chase` rota: `{chase[4:0], chase[5]}` — el bit que se caía por la izquierda entra por la derecha.
4. `led` es la inversión bit a bit. Solo un LED físico en bajo.

Cuando no toca avanzar, solo incrementa `cnt`. No hay segundo reloj, no hay FSM de “estados de LED”: el estado **es** el one-hot.

---

## 4. Mapa de pines

| Señal | Pin | Nombre Sipeed | Nota |
| --- | --- | --- | --- |
| `clk` | 52 | XTAL 27 MHz | |
| `led[0]` | 10 | LED1 | Comparte DONE |
| `led[1]` | 11 | LED2 | El del blink |
| `led[2]` | 13 | LED3 | |
| `led[3]` | 14 | LED4 | |
| `led[4]` | 15 | LED5 | |
| `led[5]` | 16 | LED6 | Hacia HDMI |

`IO_LOC` / `IO_PORT` por cada bit, `IO_TYPE=LVCMOS33`.

---

## 5. Cómo se programa (secuencia)

```powershell
cd D:\FPGA
.\activate-oss-cad.ps1
cd D:\FPGA\led-seq

yosys -p "read_verilog top.v; synth_gowin -top top -json top.json"

nextpnr-himbaechel --json top.json --write pnr.json --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C --vopt cst=board.cst

gowin_pack -d GW1N-9C --sspi_as_gpio --mspi_as_gpio --done_as_gpio -o pack.fs pnr.json

openFPGALoader -b tangnano9k pack.fs
```

La diferencia respecto al blink está en **una** bandera de pack: `--done_as_gpio`. Sin ella, `led[0]` puede no comportarse como GPIO.

Flash (opcional, pisa el residente):

```powershell
openFPGALoader -b tangnano9k -f pack.fs
```

---

## 6. Qué no hace este capítulo

No hay LCD, no hay botones, no hay texto. El siguiente paso no es “más LED”: es **una imagen**. Eso es `lcd-grid`.

Volver al índice: [`../README.md`](../README.md).

**Registro 2026-08-25 16:12 (America/New_York, UTC-4).** Historia del laboratorio. Residente en flash: `adc-lcd` (16:08, CRC Success).

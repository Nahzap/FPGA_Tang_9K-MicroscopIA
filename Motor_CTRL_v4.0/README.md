# Motor_CTRL_v4.0

Tang Nano 9K, AD7606 en ±5 V, LCD ST7789 y dos DRV8871. Mueve dos N20 a 12 V sobre las guías de 69 mm (X) y 52 mm (Y).

Los dos ejes usan el mismo circuito de cuenta Hall, potenciómetro y lazo de posición. Solo cambian sus registros y el porcentaje de MANUAL. La ley y lo medido en la platina están en:

- [2026-10-13 18:54 (UTC-3) — control de posición y eje X](docs/2026-10-13_1854_control-de-posicion-y-eje-x.md)
- [2026-10-15 10:13 (UTC-3) — tope al 35 %](docs/2026-10-15_1013_tope-35-porciento.md)

Todas las constantes están en **`config.vh`**. Se edita ese archivo y se corre `.\build.ps1`.

## Estado — 2026-10-15 10:13 (UTC-3)

**Grabada en flash y en SRAM. CRC check: Success en las dos.** Es la imagen que arranca al volver la energía.

| Qué | Resultado |
| --- | --- |
| MANUAL | X e Y al **35 %** (350/1000 ciclos, ~4,2 V; eje parado y 10 Ω ~0,4 A) |
| Simulación | `tb_motion`, `tb_pwm` y `tb_com` en PASS. El 35 % no las repitió: solo cambiaron números de `config.vh` |
| Recursos | LUT4 5469/8640 (**63 %**). Por encima de la meta de 62 % del plan y debajo del tope de 75 % |
| Timing | 54,74 MHz y 35,15 MHz, PASS a 27 MHz, 0 errores de nextpnr |
| Platina | Y, calibrado, sigue al potenciómetro y frena al llegar. X recibe el mismo mando y no sostiene el avance: el motor de X no tiene el par. Hay que cambiarlo |

## Lazo de posición

Un paso = un flanco Hall = **84 cuentas**. El Hall está en la guía.

En MANUAL, eje calibrado:

1. El pedido es la fracción del pot por el máximo del eje.
2. Si el error supera la zona, el puente va a `±35 %` con el signo que mueve la cuenta hacia el pedido.
3. Dentro de la zona el mando es 0: las dos entradas del DRV8871 en alto (freno, ~0 V entre bornes).

| Situación | Zona |
| --- | --- |
| Parado, hay que volver a salir | 2 pasos (`CFG_RESUME`) más la costa |
| Empujando hacia el pedido | 1 paso (`CFG_GATE`) más la costa |
| El sentido pedido no es el del último movimiento | 2 pasos para arrancar, 1 para soltar, sin costa |

La costa es `vel × 84 × CFG_BRAKE_MS`. `vel` son los flancos del milisegundo **anterior** (5 pasos por cada flanco/ms). Los flancos que todavía están llegando no agrandan la zona: si lo hicieran, el primer flanco apagaría el puente.

El signo se aprende de los flancos. Mientras la cuenta sigue moviéndose, un signo contrario espera en freno. El pin cercano a 3 V (dirección) y el que trocea los 12 V no se cruzan en marcha. `inv_x` / `inv_y` solo invierten los pines, no la cuenta.

AUTO muestra el pedido del PC y deja el puente en 11. No mueve.

En mando abierto, 300 ms sin un flanco Hall frenan y `PotenciaA`/`PotenciaB` pasan a `+000`. En MANUAL esa guarda no actúa: lejos del pedido el 35 % sigue aplicado aunque la guía no avance.

## PWM

**27 kHz, 1000 ciclos, 37,04 µs. 1 ciclo = 0,1 %.** Un contador para los dos ejes. Y va 500 ciclos detrás de X.

| Mando | IN1 | IN2 |
| --- | --- | --- |
| Adelante, ciclo d | 1 | 0 durante d, 1 el resto |
| Atrás, ciclo d | 0 durante d, 1 el resto | 1 |
| 100 % (solo un `A` a ±100; MANUAL está al 35 %) | 10 o 01 estático | |
| 0 %, llegada, `B`, AUTO, bloqueo | 1 | 1 |
| `RESET` sin nada que mover, pausa | 0 | 0 |

Reglas de `pwm_drv` (DRV8871, SLVSCY9B):

1. El mando se toma solo en el borde del período.
2. Ningún tramo alto ni bajo dura menos de 22 ciclos (815 ns). De 0,1 a 2,1 % sube a 2,2 %. De 97,9 a 99,9 % pasa a 100 %.
3. Cambio de sentido: un período completo de 11 en el medio. 10 nunca toca 01.
4. Detenido = 11. El freno no duerme el chip.
5. Al salir de 00: dos períodos de 11 (74 µs) antes del primer pulso.
6. Guarda de bloqueo de 300 ms, solo fuera de MANUAL.
7. La pausa pone 00 en el acto.

El medidor de la FPGA compara los ciclos con IN1 ≠ IN2 contra el mando legal. Si difieren, o si hay un 10 ↔ 01 directo, la LCD muestra `PWM ERR` hasta `reset`. El cable y el DRV8871 se juzgan por el movimiento.

`R_ILIM` del módulo fija la corriente máxima, no la FPGA: `I_TRIP = 64 kV / R_ILIM`. Con 12 V y 10 Ω, el tope del bobinado al 35 % es unos 0,4 A con el eje parado. En vacío la corriente se queda cerca de 200 mA por la fuerza contraelectromotriz. 200 mA girando no es el tope de par.

## Cableado de los potenciómetros a 5 V

| Qué | Dónde |
| --- | --- |
| Extremo alto de los dos pots | salida del regulador de 5 V |
| Extremo bajo | GND del AD7606 (tierra común con el regulador y la Tang Nano) |
| Cursor del pot X | V3 (ADC ch2) |
| Cursor del pot Y | V4 (ADC ch3) |
| Hall X / Y | V7, V8 / V5, V6, a 3,3 V |

El AD7606 está en ±5 V (RANGE a GND). El código 32767 es 4,99985 V: el riel tiene que medir menos de 5,000 V. Con un pot de 10 kΩ, 220 Ω en serie en el extremo alto bajan unos 0,1 V.

Los pots no tocan pines de la FPGA. Entran solo al ADC.

## Calibrar el riel (`CFG_POT_MV`)

1. Grabar con el valor por defecto (4950 mV).
2. Llevar cada pot a su tope y leer V3 y V4 en la LCD, o medir el riel.
3. Escribir ese valor en mV en `CFG_POT_MV`. Si V3 y V4 difieren, usar el menor.
4. `.\build.ps1`.

`CFG_POT_END` = 330 códigos ≈ 50 mV. En las puntas el pedido es 0 o el máximo. Un riel 50 mV bajo el configurado todavía pide el máximo (P3).

## Cómo se calcula el pedido

En cada ronda del datapath compartido, X e Y se turnan:

1. **Hall.** Cada flanco suma o resta un paso. Dos canales en la misma muestra: dos flancos, en el último sentido conocido. La cuenta no baja de 0 y, calibrada, no pasa su máximo.
2. **Pot.** Promedio de 2^`CFG_POT_FILT` muestras. Cambia si se mueve más de `CFG_POT_HYST` códigos. Una lectura negativa vale 0.
3. **MANUAL.** `(pot − END) / (FULL − 2·END) × máximo`, recortado a 0..máximo. `FULL = CFG_POT_MV × 32768 / 5000`.
4. **AUTO.** `min(cx, máximo de X)` y `min(cy, máximo de Y)`, de la orden `T`. El pot no lo mueve.

## Calibración de los ejes

La cuenta vale 0 al encender, con `reset` y con `x_zero` / `y_zero`. En `RESET` se puede llevar cada eje a los topes con `A`, `P` o `Q`.

1. Opcional: `x_zero` en el extremo inferior.
2. Llevar el eje al otro extremo y mandar `x_final`: esa cuenta es el máximo.
3. Lo mismo con `y_final`.
4. Con los dos `final`, Estado pasa de `RESET` a `MANUAL`. `M` también cierra la calibración, con el máximo ya alcanzado.

Calibrado, el eje frena cuando el error queda dentro de la zona. Y lo hace y después sigue al potenciómetro. X queda pedido al 35 % (o al 100 % si se manda `A`) y la guía no acompaña: ver el registro del 2026-10-13.

## Configuración (`config.vh`)

| Sección | Constantes | Valores hoy |
| --- | --- | --- |
| 1. Placa | `CFG_CLK_HZ` | 27 MHz |
| 2. Potenciómetros | `CFG_POT_MV`, `CFG_POT_END`, `CFG_POT_FILT`, `CFG_POT_HYST` | 4950 mV, 330 (≈ 50 mV), 10, 4 |
| 3. Encoders Hall | `CFG_HALL_TH`, `CFG_HALL_SHIFT`, `CFG_COUNT_MAX` | 10813 (1,65 V), 8, 999999 |
| 4. Serial | `CFG_BAUD`, `CFG_LINE_HZ` | 115200, 50 líneas/s |
| 5. Puentes | `CFG_STALL_MS`, `CFG_PULSE_PCT`, `CFG_MAN_X_PCT`, `CFG_MAN_Y_PCT`, `CFG_GATE`, `CFG_RESUME`, `CFG_BRAKE_MS` | 300 ms, 40 %, 35 %, 35 %, 1 paso, 2 pasos, 5 ms |
| 6. Guías | `CFG_X_UM`, `CFG_Y_UM` | 69000, 52000 (solo referencia) |

`CFG_PWM_PERIOD` (1000) y `CFG_PWM_MIN` (22) no se editan a mano: el paso de % a ciclos exige período 1000. `build.ps1` lo verifica. `CFG_POL_LEARN` = 1 aprende el sentido que sube la cuenta.

## Pines

`board.cst`. PWM X IN1/IN2 = 40/35. PWM Y IN1/IN2 = 41/42. `DRIVE=8` en esas salidas. UART TX/RX = 17/18.

## Serial

`PotenciaA,PotenciaB,PotA,PotB,Sensor1,Sensor2,Estado,Settled`.

PotenciaA/B es el % aplicado a X/Y, con signo. `+000` es freno, pausa o bloqueo del mando abierto. PotA va con Sensor1 (X). PotB va con Sensor2 (Y).

| Orden | Efecto |
| --- | --- |
| `A,pa,pb` | ciclo útil libre en %, con signo, recortado a ±100. Estado `PWM_X`, `PWM_Y`, `PWM_XY` o `PWM_0`. No queda limitado al 35 % |
| `N` | `A,0,0`: los dos en 11 |
| `B` | freno 11, Estado `BRAKE` |
| `P,eje,signo,idx` | pulso de 20 × (idx+1) ms a ±`CFG_PULSE_PCT` % (40 %), Estado `PULSE`, luego `PWM_0` |
| `Q,eje,pot,n` | n períodos (1 = 37 µs, hasta 65535 = 2,4 s) a `pot` % con signo, Estado `PULSE`, luego `PWM_0` |
| `I,ix,iy` | invierte el sentido de los pines de X / Y (distinto de 0 = invertido) |
| `M` | MANUAL. X e Y al 35 % hacia el potenciómetro |
| `T,cx,cy,px,py` | AUTO: pedido del PC, informado. El puente queda en 11 |
| `x_zero`, `y_zero`, `x_final`, `y_final`, `reset` | marcas. `reset` también borra `PWM ERR` |

`eje` es `X`/`A`/`0` o `Y`/`B`/`1`. Cualquier orden nueva corta un `Q` en curso y libera la guarda de bloqueo.

Ver la telemetría: `.\mon.ps1 COM11`

## Cómo se graba

`.\build.ps1` (simula si hace falta, sintetiza, coloca, empaqueta, flash y SRAM). `-Sram`, `-NoLoad`, `-LoadOnly`, `-NoSim`.

Si desde el último PASS solo cambiaron los números de `config.vh`, no corre `tb_motion`, `tb_pwm` ni `tb_com`. La colocación usa el `pnr.json` anterior como guía. Exige PASS de las tres simulaciones cuando corren, 0 errores de nextpnr, PASS a 27 MHz y LUT4 ≤ 75 % (avisa sobre 62 %).

Si el USB no responde: desconectar la Tang Nano, esperar 5 s, conectar, `.\build.ps1 -LoadOnly`.

## Pruebas de simulación

| Caso | Qué prueba |
| --- | --- |
| H1–H6 | Conteo Hall: subir y bajar, tope, piso en 0, doble flanco |
| K1–K5 | `final`, `x_zero` después del final, `reset`, máximo sin final, `M` |
| P1–P6 | Pot: 0 V, riel, saturación, riel 50 mV bajo, negativo, recta, ruido |
| A1–A3 | AUTO: `T` recortado al máximo, el pot no manda, `M` devuelve el mando al pot |
| M1–M4 | MANUAL: en el pedido frena; lejos, X va a `CFG_MAN_X_PCT` y Y no se mueve si no está armado |
| W1–W10 | PWM: ciclo legal, mínimo 22 ciclos, borde de período, inversión con 11, despertar, fase X/Y, bloqueo, `Q`, medidor |
| C1–C9 | UART: órdenes, nombres de Estado, `A` recortado a ±100, `Q` |

## Prueba Humano - Máquina

La haces tú. 12 V conectados.

Lo ya visto el 2026-10-13, con la imagen al 100 % y la costa corregida:

| Qué pasó | Lectura |
| --- | --- |
| Y calibrado | Sigue al potenciómetro y frena en el pedido |
| X con PotenciaA en −100 y el pedido 34 pasos más allá | Sensor1 avanzó 6 pasos y se detuvo. El puente siguió al −100 % |
| X fuera de la guía | La yema lo para. No forcejea |
| Línea de reposo | Error de menos de 2 pasos, PotenciaA `+000`, Settled 1 |

| Paso que sigue | Qué haces | Qué debe verse |
| --- | --- | --- |
| 1 | Motor de X fuera de la guía, pot lejos, mirando la línea | Si PotenciaA se queda en ±35 y la yema lo para, el motor es el flojo. Si pasa solo a `+000` en ~0,3 s, esa prueba no vale: el Hall está en la guía |
| 2 | El mismo ensayo con el motor de Y | Tiene que forcejear |
| 3 | Cambiar el motor de X y repetir el pot en MANUAL | Sensor1 sigue a PotA y, al llegar, PotenciaA vuelve a `+000` |
| 4 | Anotar `R_ILIM` de los dos DRV8871 | `I_TRIP = 64 kV / R_ILIM` |

## Archivos

| Archivo | Qué es |
| --- | --- |
| `config.vh` | Todas las constantes |
| `docs/` | Registro de la ley y de la platina, con fecha y hora |
| `build.ps1` | Simular, compilar y grabar |
| `mon.ps1` | Monitor serial |
| `top.v` | Conexiones |
| `motion.v` | Cuenta Hall, pedido y lazo, compartido por X e Y |
| `com_ctrl.v` | Protocolo serial Lab 206 |
| `drive.v` | Órdenes a los dos puentes. En MANUAL no aplica la guarda de 300 ms |
| `pwm_timer.v` | Contador de 1000 ciclos. Y desfasado 500 |
| `pwm_drv.v` | Un DRV8871: reglas 1–7, `Q`, bloqueo, medidor |
| `adc_master.v`, `orch.v` | AD7606 y ritmo |
| `format_scan.v`, `text_pwm.v`, `lcd_master.v` | LCD (`PWM ERR` en el título) |
| `btn_sync.v`, `pause_reg.v` | Pausa |
| `board.cst` | Pines |
| `tb_motion.v`, `tb_pwm.v`, `tb_com.v` | Simulaciones |
| `pack.fs` | Bitstream del 35 % grabado el 2026-10-15 10:06 |

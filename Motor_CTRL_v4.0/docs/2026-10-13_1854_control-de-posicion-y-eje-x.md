# Control de posición y eje X

**2026-10-13 18:54 (UTC-3).** Placa Tang Nano 9K, imagen `Motor_CTRL_v4.0`. Los dos ejes comparten un solo datapath (`motion.v`, índice 0 = X, 1 = Y). Este registro es la ley que quedó grabada ese día y lo que la telemetría mostró en la platina.

## Qué hace el lazo

En MANUAL, con el eje calibrado (`x_final` / `y_final`, o `M`), el pedido es la fracción del potenciómetro por el máximo de ese eje, en cuentas:

`(pot − CFG_POT_END) / (CFG_POT_FULL − 2·CFG_POT_END) × máximo`

Lejos del pedido el puente va a `±CFG_MAN_X_PCT` o `±CFG_MAN_Y_PCT`. Dentro de la zona de parada el mando es 0 y el puente queda en 11 (freno, bobinado en corto). AUTO calcula el pedido del PC y no mueve.

Un paso es un flanco Hall: `2·CFG_HALL_TH / 2^CFG_HALL_SHIFT` = **84 cuentas**. El Hall está en la guía, no dentro del N20. Si en una conversión del AD7606 cambian los dos canales, esa muestra cuenta dos flancos.

| Umbral | Valor | Cuentas |
| --- | --- | --- |
| `CFG_GATE` | 1 paso | 84. Frenar al llegar, viniendo hacia el pedido |
| `CFG_RESUME` | 2 pasos | 168. Parado, volver a empujar si el error supera esto |
| `CFG_BRAKE_MS` | 5 ms | cada flanco/ms del milisegundo ya cerrado suma 5 pasos de adelanto |

La zona, viniendo hacia el pedido, es el umbral más la costa `vel × 84 × 5`. `vel` son los flancos del **milisegundo anterior**. Los flancos de este milisegundo (`ecnt`) no agrandan la zona.

Eso se cambió el 2026-10-13 porque antes la zona usaba el mayor entre `ecnt` y `vel`. El primer flanco ya contaba como 1 flanco/ms, sumaba 5 pasos de freno y solo 1 de avance, y el puente se apagaba en ese mismo flanco. Con menos de 7 pasos de error el motor no recibía más que un período de PWM (37 µs), o ninguno si el mando volvía a 0 antes del borde del período. El medidor veía una tensión muy por debajo de la de arranque.

Signo: el que hace subir o bajar la cuenta hacia el pedido. Se aprende de los flancos (`CFG_POL_LEARN`). `inv_x` / `inv_y` solo dan vuelta los pines en `pwm_drv`; el aprendizaje no los ve.

## Inversión

Mientras siguen llegando flancos, el signo contrario no se aplica. `rev_hold` deja el mando en 0 (las dos entradas en alto) hasta que `vel` y `ecnt` son 0. Así el pin que está cerca de 3 V y el que trocea los 12 V no se intercambian con el eje todavía en movimiento. Al período siguiente del PWM, un 11 completo separa 10 de 01. 10 nunca toca 01.

## PWM

27 kHz, 1000 ciclos de 27 MHz (37,04 µs). 1 % = 10 ciclos. Mínimo 22 ciclos (815 ns). Por encima de 978 ciclos el tramo pasa a 100 % estático.

| Mando | IN1 (X = pin 40, Y = pin 41) | IN2 (X = pin 35, Y = pin 42) |
| --- | --- | --- |
| Adelante, ciclo d | 1 fijo | 0 durante d |
| Atrás, ciclo d | 0 durante d | 1 fijo |
| 100 % | 10 o 01 estático, 12 V continuos | |
| 0, llegada, `B`, AUTO, bloqueo | 1 | 1. Unos 0 V entre bornes |
| `RESET` sin nada que mover, pausa | 0 | 0. Eje suelto |

Y va medio período atrás (500 ciclos, 18,5 µs) para no conmutar junto con X. El mando se toma solo cuando el contador del eje pasa por 0. `DRIVE=8` en esos cuatro pines.

En mando abierto (`A`), 300 ms empujando sin un flanco Hall frenan el eje y `PotenciaA`/`PotenciaB` pasan a `+000`. En MANUAL esa guarda se borra en cada ciclo: si el pedido sigue lejos, el % se mantiene aunque la guía no avance.

## Potencia y corriente

Motores N20 a 12 V. La resistencia medida del bobinado fue 10 Ω. La corriente con el eje girando en vacío fue unos 200 mA: ahí la fuerza contraelectromotriz se lleva la mayor parte de los 12 V. El tope eléctrico es el eje trabado, `I ≈ (12 V × % / 100) / 10 Ω`.

| % MANUAL | Tensión media | Corriente con el eje parado |
| --- | --- | --- |
| 40 (Y, valor de diseño anterior) | 4,8 V | ~0,48 A |
| 70 (X, valor de diseño anterior) | 8,4 V | ~0,84 A |
| 100 | 12 V fijos | ~1,2 A |

`R_ILIM` del módulo DRV8871 puede cortar antes: `I_TRIP = 64 kV / R_ILIM`. La FPGA no mide corriente.

El 2026-10-13 a la tarde se grabó primero X al 90 % e Y al 40 %, y después los dos ejes al 100 %. En esas imágenes, mientras el lazo empuja al 100 % los pines no trocean: uno queda cerca de 3 V y el otro en 0. Al llegar, los dos quedan en alto.

## Telemetría del 2026-10-13 a la tarde

Línea: `PotenciaA,PotenciaB,PotA,PotB,Sensor1,Sensor2,Estado,Settled`. PotA/Sensor1 son el pedido y la cuenta de X. PotB/Sensor2 son Y.

| Momento | Línea | Lectura |
| --- | --- | --- |
| Reposo | `+000,+000,013594,034009,013692,034104,MANUAL,1` | Error de X = 98 cuentas, menos de 2 pasos. Freno. Y también dentro de la zona |
| Pedido nuevo, sin mover la platina a mano | `−100,+000,010329,034021,013188,034104,MANUAL,0` | El pot bajó el pedido 3265 cuentas (39 pasos). X avanzó 504 cuentas (6 pasos) y se quedó a 2859 cuentas (34 pasos) con el puente al −100 % |
| Después de mover X a mano | `+000,+000,010329,034021,010416,034104,MANUAL,1` | Sensor1 a 87 cuentas del pedido. El lazo soltó el puente |

Y no se movió: Sensor2 siguió en 34104. Y, ya calibrado, frena en el pedido y sigue al potenciómetro. X recibe la misma ley y no sostiene el avance.

## Conclusión de X

No es la zona muerta ni un mando que no sale. Con el puente al −100 % la cuenta avanzó 6 pasos en el sentido correcto y después no hubo más flancos. Fuera de la guía, la yema del dedo le quita la fuerza: un N20 sano, al frenarlo, forcejea y la corriente sube hacia 1 A.

El puente de potencia ya se había intercambiado y la falla se quedó en X. Lo que sigue en X es el motor, el acople y la guía. El motor de X es el que hay que cambiar. El de Y ya cierra el lazo. Otro N20 igual de flojo queda corto: al 100 % no hay más tensión que los 12 V.

Para no confundir el corte de firmware con el motor: con el motor fuera de la guía, `A,−100,0` se apaga a los 300 ms porque el Hall no ve flancos y `PotenciaA` pasa a `+000`. La prueba de par vale en MANUAL, con el pot lejos de Sensor1, mientras la línea sigue en `±100`.

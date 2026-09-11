# 2026-09-11 14:13 (UTC-3) — control de velocidad + encoders

Cierre del día. Host: Windows. Bitstream en flash SPI.

## Objetivo cerrado

Control de **velocidad** de los dos N20 (pots V3/V4 → duty/sentido) con **indicadores de encoder** en la LCD. Fin de carrera por stall; recorte suave de PWM solo con tope locked.

**Próximo paso (no hecho hoy):** control de **posición** por encoders.

## Placa

`openFPGALoader -b tangnano9k -f pack.fs` → **CRC check: Success** (2026-09-11 ~14:05 UTC-3).

LCD residente:

```
ADC PWM 3.3V
V1:+x.xxx
V2:+x.xxx
V3:+x.xxx
V4:+x.xxx
X:±ddd *L
Y:±ddd *L
OK
```

V1–V4 a tres decimales. X/Y a tres dígitos. `*` = flanco. `L` = tope trabado. Centro al encender: `+000`.

## Pruebas automáticas (iverilog)

| Banco | Resultado |
| --- | --- |
| tb_map_pot | ALL PASS |
| tb_pwm_drv | ALL PASS |
| tb_format_scan | ALL PASS |
| tb_orch | ALL PASS |
| tb_enc_pos | ALL PASS |
| tb_pwr_lim | ALL PASS |

## P&R

LUT4 **68 %** (5907/8640). fmax **39.56 MHz** (PASS @ 27 MHz). El % de 23 bit en un ciclo no cabía (22.68 MHz FAIL); quedó un comparador de 7 bits en 7 ciclos.

## Cable (sin cambio de CST / PWM)

| Señal | Dónde |
| --- | --- |
| PWM X / Y | 40/35, 41/42 |
| Enc X A/B | F4 V5/V6 |
| Enc Y A/B | F4 V7/V8 |
| Hall | +3.3 V J6-24, GND J6-23 |

## Ley que queda

- Pantalla: min/max vivos. Explorar es siempre ±100 % en el extremo actual.
- PWM: pot entero hasta stall (~100 ms sin flanco con mando) → `lock`. Banda 20 %. En ±100 % locked ese sentido = 00; el contrario sale.

Índice: [`README.md`](README.md).

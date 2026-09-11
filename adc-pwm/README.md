# ADC + LCD + 2× DRV8871

Este es el diseño. Control de **velocidad** (pot → PWM) con indicadores de encoder **listos**. La FPGA lee el AD7606, pinta la LCD 1.14″ y manda cuatro PWM a **dos** DRV8871. Pots **V3 → X**, **V4 → Y**. Hall A/B en **V5…V8**. Centro al encender = `+000`. Los topes de pantalla se estiran; el PWM solo se recorta cuando un tope está **locked** (stall).

Cierre de hoy: [`2026-09-11_1413_control-velocidad.md`](2026-09-11_1413_control-velocidad.md). **Próximo paso:** control de posición por encoders.

GPIO 3.3 V directo a IN1/IN2. Sin 1201. `orch` manda. La LCD no apaga un pin.

---

## 1. Qué deberías ver

```
ADC PWM 3.3V
V1:+1.650
V2:+0.012
V3:+1.650
V4:+1.650
X:+000
Y:+000
OK
```

- V1…V4: signo + entero + tres decimales. V3/V4 (pots) en cian. V5…V8 no se pintan.
- `X:+080` / `X:-100` / `X:+000`. Tres dígitos. `*` si hay flanco. `L` si hay fin de carrera locked.
- `PAUSA` con S1/S2 (PWM a 00).

Pot al centro = 00. Hacia 3.3 V = adelante. Hacia 0 V = atrás. Table 1: drive ↔ brake.

Mientras se explora (sin `L`), el pot manda entero aunque la pantalla muestre +100 %. Al llegar a un tope mecánico (~100 ms sin flancos con mando), `L` y el duty baja en los últimos 20 %. En ±100 % locked ese sentido corta; el contrario sigue libre.

---

## 2. Quién manda

```
              orch
     adc_go / map_go+fmt_go / snap
        |           |            |
   adc_master   map_x ║ map_y    pwm_drv x2
                enc_x ║ enc_y    ← pwr_lim
                format_scan      lcd_master
```

- **`enc_pos`**: umbral ~1.65 V, cuadratura, min/max vivos, stall → `lock_p` / `lock_n`. Arranca en `sample_done`.
- **`pwr_lim`**: si el lado no está locked, pasa el pot. Si locked y vas hacia el tope, `cmp * (100-pct) / 20`. En 100 % = 00.
- **`orch`**: tres pistas. El ADC no espera al formateo. `pwm_en` no mira la LCD.

```
adc-pwm/
  orch.v         orquestador
  adc_master.v   AD7606 SPI
  format_scan.v  V1…V8 → mV/BCD
  map_pot.v      un pot → fwd/rev/cmp
  enc_pos.v      A/B → % y locks
  pwr_lim.v      recorte al tope locked
  pwm_timer.v / pwm_drv.v
  text_pwm.v     V1–V4 + X/Y
  lcd_master.v / btn_sync.v / pause_reg.v
  top.v          solo cablea
  board.cst
  tb_enc_pos.v / tb_pwr_lim.v
```

---

## 3. Pines

| Señal | Dónde |
| --- | --- |
| clk | 52 |
| ADC SPI | 25–30 (31 CONVST copia, sin cable) |
| PWM X | 40 / 35 = J5-13 / 14 |
| PWM Y | 41 / 42 = J5-15 / 16 |
| LCD | 47, 48, 49, 76, 77 |
| S1 / S2 / LED2 | 3 / 4 / 11 |
| Enc X A/B | F4 **V5 / V6** |
| Enc Y A/B | F4 **V7 / V8** |
| Hall Vcc / GND | J6-24 **+3.3 V** / J6-23 GND |

---

## 4. Rebuild (flash SPI — residente)

```powershell
cd D:\FPGA
.\activate-oss-cad.ps1
cd D:\FPGA\adc-pwm
iverilog -o tb_map.vvp map_pot.v tb_map_pot.v; vvp tb_map.vvp
iverilog -o tb_pwm.vvp pwm_timer.v pwm_drv.v tb_pwm_drv.v; vvp tb_pwm.vvp
iverilog -o tb_fmt.vvp format_scan.v tb_format_scan.v; vvp tb_fmt.vvp
iverilog -o tb_orch.vvp orch.v tb_orch.v; vvp tb_orch.vvp
iverilog -o tb_enc.vvp enc_pos.v tb_enc_pos.v; vvp tb_enc.vvp
iverilog -o tb_lim.vvp pwr_lim.v tb_pwr_lim.v; vvp tb_lim.vvp
yosys -p "read_verilog top.v orch.v adc_master.v format_scan.v map_pot.v enc_pos.v pwr_lim.v pwm_timer.v pwm_drv.v text_pwm.v lcd_master.v btn_sync.v pause_reg.v; synth_gowin -top top -nodsp -json top.json"
nextpnr-himbaechel --json top.json --write pnr.json --device GW1NR-LV9QN88PC6/I5 --freq 27 --vopt family=GW1N-9C --vopt cst=board.cst
gowin_pack -d GW1N-9C --sspi_as_gpio --mspi_as_gpio -o pack.fs pnr.json
openFPGALoader -b tangnano9k -f pack.fs
```

Exigir **CRC check: Success**.

---

## 5. Escala

Pot 0…3.3 V, centro 1.65 V, banda ±66 mV. PWM 20 kHz, pulso mínimo 27 clocks. Hall umbral 1.65 V. Stall 100 muestras (~100 ms). Banda de recorte 20 %. LUT4 **68 %**. fmax post-ruta **39.56 MHz** (PASS @ 27 MHz).

Índice: [`../README.md`](../README.md). Resultados: [`2026-09-11_1413_control-velocidad.md`](2026-09-11_1413_control-velocidad.md). Pinout local: `Docs/2026-09-10_1543_pinout-adc-pwm.md`.

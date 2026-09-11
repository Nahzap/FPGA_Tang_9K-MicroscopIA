# ADC + 4 PWM (pots V3/V4)

**Capítulo 6.** Pregunta: ¿la FPGA lee el AD7606 como en el capítulo 5 y manda cuatro PWM a dos DRV8871, con un potenciómetro de 3.3 V por eje?

**Residente:** GPIO 3.3 V directo a IN1/IN2 de **dos** DRV8871. Sin 1201 en el camino. `orch` manda; map X, map Y y format arrancan juntos. La LCD no apaga un pin. **V3 → X, V4 → Y.** Centro = 0 %. 3.3 V = adelante. 0 V = atrás.

---

## 1. Qué deberías ver

El PWM sale en cuanto hay una muestra mapeada (~ms), no espera el init de la LCD (~0.4 s). En la pantalla, tras el init:

- Título: `ADC PWM 3.3V`
- V1…V8 en hex y voltios (V3 y V4 en cian)
- Pie `OK` + contador; `PAUSA` con S1/S2 (los PWM se van a 00)
- `X: F100%` / `X: R050%` / `X:  000%` y lo mismo en Y
- `V3>X V4>Y`

**Scope en J5-13…16**, GND lógico de la 9K. Table 1 del DRV8871: PWM = drive ↔ brake, no “un pin tren y el otro 0”.

| Pot | Pines | Scope (FPGA → IN) |
| --- | --- | --- |
| Centro | los cuatro | 0 V (00, sleep) |
| X → 3.3 V, ~50 % | J5-13 = 40 = IN1 | **3.3 V DC**; J5-14 = 35 = IN2 **PWM 20 kHz** (alto = freno) |
| X → 3.3 V, 100 % | 40 alto, 35 bajo | 10 estático |
| X → 0 V | al revés | IN2 DC, PWM en IN1 |
| Y | J5-15/16 = 41/42 | igual |

S1/S2 → 00. LED2 parpadea con cada conversión.

---

## 2. Quién manda

```
              orch
     adc_go / map_go+fmt_go / snap
        |           |            |
   adc_master   map_x ║ map_y    pwm_drv x2  ← pwm_timer (siempre)
                format_scan      lcd_master (siempre)
```

- **`orch`**: tres pistas independientes. El ADC no espera al formateo ni a la LCD. Los mapas no esperan al formateo. `pwm_en` no mira la pantalla.
- **`format_scan`**: copia V1…V8 al arrancar, así el ADC puede volver a convertir mientras se pintan voltios.
- **`map_pot` × 2**: dos etapas registradas (mV, luego duty/BCD). No es un bucle de 1350 restas. X e Y son dos circuitos, el mismo `map_go`.
- **`pwm_timer` + `pwm_drv` × 2**: 20 kHz, Table 1 (drive/brake), latch en `cnt==0`, wake ~50 µs. `pwm_en` no mira la LCD.
- **`format_scan`**: un datapath que recorre V1…V8. Ocho formateadores en paralelo ya llenaron el 86 % de LUT4 en el capítulo 5 y nextpnr no terminó.
- **`top`**: solo cablea y copia registros en `snap_pwm` / `snap_lcd`.

```
adc-pwm/
  orch.v         orquestador
  adc_master.v   AD7606 SPI
  format_scan.v  V1…V8 → mV/BCD (LCD)
  map_pot.v      un pot → fwd/rev/cmp/pct
  pwm_timer.v    contador 0…1349 (20 kHz)
  pwm_drv.v      un DRV8871 → IN1/IN2
  text_pwm.v     glifos LCD
  lcd_master.v   PHY ST7789
  btn_sync.v     botones
  pause_reg.v    latch pausa
  top.v          solo cablea
  board.cst
  tb_map_pot.v
  tb_pwm_drv.v
  tb_orch.v
```

---

## 3. Pines

| Señal | Pin |
| --- | --- |
| clk | 52 |
| adc_convst (CVA+CVB) | 25 |
| adc_convstb | 31 (sin cable) |
| adc_reset / cs / sclk / busy / dout | 26 / 27 / 28 / 29 / 30 |
| **pwm_x_in1 / in2** | **40 / 35** |
| **pwm_y_in1 / in2** | **41 / 42** |
| lcd reset / cs / rs / clk / data | 47 / 48 / 49 / 76 / 77 |
| S1 / S2 / LED2 | 3 / 4 / 11 |

---

## 4. Rebuild (flash SPI — residente)

Este capítulo es un **controlador**: tiene que arrancar solo. La carga que cuenta es `-f`. SRAM solo para un ensayo; al apagar se pierde.

```powershell
cd D:\FPGA
.\activate-oss-cad.ps1
cd D:\FPGA\adc-pwm
iverilog -o tb_map.vvp map_pot.v tb_map_pot.v; vvp tb_map.vvp
iverilog -o tb_pwm.vvp pwm_timer.v pwm_drv.v tb_pwm_drv.v; vvp tb_pwm.vvp
iverilog -o tb_fmt.vvp format_scan.v tb_format_scan.v; vvp tb_fmt.vvp
iverilog -o tb_orch.vvp orch.v tb_orch.v; vvp tb_orch.vvp
yosys -p "read_verilog top.v orch.v adc_master.v format_scan.v map_pot.v pwm_timer.v pwm_drv.v text_pwm.v lcd_master.v btn_sync.v pause_reg.v; synth_gowin -top top -nodsp -json top.json"
nextpnr-himbaechel --json top.json --write pnr.json --device GW1NR-LV9QN88PC6/I5 --freq 27 --vopt family=GW1N-9C --vopt cst=board.cst
gowin_pack -d GW1N-9C --sspi_as_gpio --mspi_as_gpio -o pack.fs pnr.json
openFPGALoader -b tangnano9k -f pack.fs
```

Exigir **CRC check: Success**. Un `-f` sustituye al bitstream anterior.

---

## 5. Escala

Pot 0…3.3 V sobre F4 ±5 V. Centro 1.65 V (raw ≈ 10813) = 0 %. Banda muerta ±66 mV. Periodo 1350 ciclos @ 27 MHz = 20 kHz. Pulso mínimo 1 µs si duty > 0.

LUT4 **39 %**, ALU **21 %**, DFF **18 %**. fmax post-ruta **31.65 MHz** (PASS @ 27 MHz). `tb_orch` ALL PASS, incluido ADC mientras el formateo sigue ocupado.

Flash **2026-09-11 ~11:15 UTC-3:** `openFPGALoader -b tangnano9k -f pack.fs`, **CRC check: Success**. Este dual pisa el ensayo de un solo puente (`adc-drv1`, que dejaba 41/42 en 0).

Índice: [`../README.md`](../README.md). Plan: `Docs/2026-09-10_1806_plan-adc-pwm-manual.md` (local).

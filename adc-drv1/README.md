# Un DRV8871 — pot V3, Table 1

**Capítulo 7.** Pregunta: ¿un solo puente, dos entradas PWM y un pot en V3 mueven el duty como dice el datasheet?

Proyecto **limpio**. No hereda el dual de `adc-pwm/`. FPGA + ADC + pot + **un** DRV8871. El segundo aislador (pines 41/42) se queda en 00.

**Residente (2026-09-10 ~18:55 UTC-3):** `openFPGALoader -b tangnano9k -f pack.fs`, **CRC check: Success**. LUT4 **29 %**, ALU **13 %**, fmax **31.55 MHz**.

---

## 1. Qué deberías ver

PWM en cuanto hay una muestra mapeada. La LCD no apaga ningún pin.

Pantalla, tras el init (~0.4 s):

- Título: `ADC DRV8871`
- V1…V8 (V3 en cian)
- `M: F 050%` / `M: R100%` / `M:   000%`
- `V3>M1`

**12 V abierto** en la primera prueba. Punta en **J5-13** (FPGA 40 = IN1) y **J5-14** (FPGA 35 = IN2), GND lógico, lado FPGA del 1201.

| Pot V3 | IN1 (40 / J5-13) | IN2 (35 / J5-14) | Puente (Table 1) |
| --- | --- | --- | --- |
| Centro (~1.65 V) | 0 | 0 | Coast → sleep (~1 ms) |
| Hacia 3.3 V, p. ej. 50 % | **3.3 V DC** | PWM 20 kHz, alto = freno | 10 drive / 11 brake |
| Tope 3.3 V | 3.3 V | 0 | 10 estático (100 %) |
| Hacia 0 V, p. ej. 20 % | PWM 20 kHz, alto = freno | **3.3 V DC** | 01 drive / 11 brake |
| Tope 0 V | 0 | 3.3 V | 01 estático |

Eso **no** es “PWM en el pin de avance y el otro a 0”. TI (SLVSCY9B §7.3.1) pide conmutar **drive ↔ brake**. En adelante IN1 se queda alto; IN2 es el PWM. En atrás, al revés.

S1/S2 → 00. LED2 (pin 11) parpadea con cada conversión.

---

## 2. Por qué así (DRV8871)

Fuente: [DRV8871](https://www.ti.com/lit/gpn/DRV8871) SLVSCY9B.

| Condición | Qué implica aquí |
| --- | --- |
| Table 1: 00 High-Z, 10 fwd, 01 rev, 11 brake | Dos pines independientes. Nunca 11 en reposo. |
| PWM “works best” drive↔brake | Valle = 11, no 00. El 00 de más de ~1 ms entra en **sleep**. |
| Pulso ≥ **800 ns** | Duty mínimo 27 clocks @ 27 MHz (1 µs) si 0 % < D < 100 % |
| tON ~ **50 µs** al salir de sleep | Un periodo estático 20 kHz (1350 clocks) antes de modular |
| fPWM 0…100 kHz (rec. ≤ 200 kHz) | **20 kHz** (1350 @ 27 MHz). Menos pérdida que 200 kHz |
| VIH ≥ 1.5 V, 3.3 V válido | LVCMOS33, DRIVE=24 |

`orch` manda. `map_pot` (V3 = ch2) y `format_scan` arrancan juntos. El PWM se latchea en el borde de periodo (`cnt==0`). `top` solo cablea.

---

## 3. Pines

| Señal | FPGA | Header |
| --- | --- | --- |
| pwm_in1 / pwm_in2 | **40 / 35** | J5-13 / J5-14 |
| hold_in1 / hold_in2 | 41 / 42 = **0** | J5-15 / J5-16 (segundo driver dormido) |
| ADC CONVST…DOUT | 25…30 | J5-5…10 |
| LCD | 47, 48, 49, 76, 77 | 8P |
| S1 / S2 / LED2 | 3 / 4 / 11 | |

---

## 4. Rebuild (flash SPI)

```powershell
cd D:\FPGA
.\activate-oss-cad.ps1
cd D:\FPGA\adc-drv1
iverilog -o tb_map.vvp map_pot.v tb_map_pot.v; vvp tb_map.vvp
iverilog -o tb_pwm.vvp pwm_timer.v pwm_drv.v tb_pwm_drv.v; vvp tb_pwm.vvp
iverilog -o tb_orch.vvp orch.v tb_orch.v; vvp tb_orch.vvp
yosys -p "read_verilog top.v orch.v adc_master.v format_scan.v map_pot.v pwm_timer.v pwm_drv.v text_drv.v lcd_master.v btn_sync.v pause_reg.v; synth_gowin -top top -nodsp -json top.json"
nextpnr-himbaechel --json top.json --write pnr.json --device GW1NR-LV9QN88PC6/I5 --freq 27 --vopt family=GW1N-9C --vopt cst=board.cst
gowin_pack -d GW1N-9C --sspi_as_gpio --mspi_as_gpio -o pack.fs pnr.json
openFPGALoader -b tangnano9k -f pack.fs
```

Exigir **CRC check: Success**.

Índice: [`../README.md`](../README.md). Plan: `Docs/2026-09-10_1806_plan-adc-pwm-manual.md` (local).

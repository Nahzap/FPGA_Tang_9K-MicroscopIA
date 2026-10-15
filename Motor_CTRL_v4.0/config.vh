// =====================================================================
//  Motor_CTRL_v4.0 - CONFIGURACION
//  Unico archivo a editar. Despues:  .\build.ps1
//  v4.0 lee pots y Hall y, en MANUAL, lleva el eje calibrado al pedido
//  a CFG_MAN_X_PCT / CFG_MAN_Y_PCT. AUTO no mueve. Mando abierto
//  (A, N, B, P, Q) a 27 kHz.
// =====================================================================
`ifndef CFG_VH
`define CFG_VH


// ---------------------------------------------------------------------
//  1. PLACA                                                   (top.v)
// ---------------------------------------------------------------------
`define CFG_CLK_HZ      27000000    // Hz    reloj de la Tang Nano 9K


// ---------------------------------------------------------------------
//  2. POTENCIOMETROS                                       (motion.v)
//     Alimentados por el regulador de 5 V. AD7606 en +-5 V (RANGE a GND):
//     el codigo 32767 es 4,99985 V, un riel de 5,000 V o mas satura.
//     pedido = (pot - END) / (FULL - 2*END) * maximo del eje
// ---------------------------------------------------------------------
`define CFG_POT_MV      4950        // mV    riel medido en el tope del pot (< 5000)
`define CFG_POT_END     330         // codigo  ~50 mV: en cada punta se lee 0 o tope
`define CFG_POT_FILT    10          // 2^N muestras promediadas (10 = ~26 ms)
`define CFG_POT_HYST    4           // codigo  el pedido cambia si el pot pasa esto


// ---------------------------------------------------------------------
//  3. ENCODERS HALL (siguen a 3,3 V)                       (motion.v)
//     1 paso = 1 flanco del Hall = 2*TH / 2^SHIFT cuentas (84 en el serial)
// ---------------------------------------------------------------------
`define CFG_HALL_TH     10813       // codigo  umbral alto/bajo (1.65 V)
`define CFG_HALL_SHIFT  8           // 2^N codigos de ADC = 1 cuenta
`define CFG_COUNT_MAX   999999      // cuentas  tope (6 digitos en el serial)


// ---------------------------------------------------------------------
//  4. SERIAL                                             (com_ctrl.v)
// ---------------------------------------------------------------------
`define CFG_BAUD        115200      // baudios
`define CFG_LINE_HZ     50          // lineas por segundo (minimo 26)


// ---------------------------------------------------------------------
//  5. PUENTES DRV8871                                       (pwm_drv.v)
//     27 kHz fijo: 1000 ciclos por periodo, 1 ciclo = 0,1 % (ver abajo).
// ---------------------------------------------------------------------
`define CFG_STALL_MS    300         // ms    empujando sin flanco Hall -> freno
`define CFG_PULSE_PCT   40          // %     potencia del pulso P (1..100)
`define CFG_MAN_X_PCT   35          // %     MANUAL, eje X. Tope 35 %: ~4,2 V, eje parado ~0,4 A
`define CFG_MAN_Y_PCT   35          // %     MANUAL, eje Y. Tope 35 %: ~4,2 V, eje parado ~0,4 A
`define CFG_GATE        1           // pasos  llega: frena a esta distancia del pedido
`define CFG_RESUME      2           // pasos  parado, vuelve a arrancar si se aleja mas
`define CFG_BRAKE_MS    5           // ms    frena antes: a (velocidad x este tiempo)
`define CFG_POL_LEARN   1           // 1 = aprende el sentido que sube la cuenta


// ---------------------------------------------------------------------
//  6. GUIAS (solo referencia, no cambia el circuito)
// ---------------------------------------------------------------------
`define CFG_X_UM        69000       // um    largo de la guia X
`define CFG_Y_UM        52000       // um    largo de la guia Y


// ---------------------------------------------------------------------
//  Calculadas - no editar
// ---------------------------------------------------------------------
`define CFG_POT_FULL    (`CFG_POT_MV * 32768 / 5000)   // codigo del riel en +-5 V
`define CFG_UART_DIV    (`CFG_CLK_HZ / `CFG_BAUD)
`define CFG_LINE_GAP    (`CFG_CLK_HZ / `CFG_LINE_HZ)
`define CFG_PWM_PERIOD  1000        // ciclos = 27 kHz; % x 10 cuenta con 1000
`define CFG_PWM_MIN     22          // ciclos = 815 ns >= 800 ns del DRV8871

`endif

// =====================================================================
//  Motor_CTRL_v3.0 - CONFIGURACION
//  Unico archivo a editar. Despues:  .\build.ps1
// =====================================================================
`ifndef CFG_VH
`define CFG_VH


// ---------------------------------------------------------------------
//  1. PLACA                                                   (top.v)
// ---------------------------------------------------------------------
`define CFG_CLK_HZ      27000000    // Hz    reloj de la Tang Nano 9K


// ---------------------------------------------------------------------
//  2. DRIVERS DRV8871                         (pwm_timer.v, pwm_drv.v)
// ---------------------------------------------------------------------
`define CFG_PWM_HZ      50000       // Hz    frecuencia PWM (TI: 0 a 200 kHz)


// ---------------------------------------------------------------------
//  3. MOTORES                                              (motion.v)
// ---------------------------------------------------------------------
`define CFG_POWER       80          // %     UNICA potencia, igual en + y en -
                                    //       (100 = pines fijos, sin PWM)
`define CFG_GATE        1           // pasos  llega: para a esta distancia del pedido
`define CFG_RESUME      2           // pasos  parado, arranca de nuevo si se aleja mas
`define CFG_BRAKE_MS    5           // ms    frena antes de llegar: a (velocidad x este tiempo)
                                    //       se pasa y vuelve: subir / queda corto: bajar / 0 = no
`define CFG_STOP_BRAKE  1           // 1 = frena al llegar (11) / 0 = suelta (00)
`define CFG_POL_LEARN   1           // 1 = aprende solo el sentido de giro
`define CFG_STALL_MS    200         // ms    empuja sin moverse: invierte el sentido


// ---------------------------------------------------------------------
//  4. POTENCIOMETROS                                       (motion.v)
//     pedido = (pot - END) / (FULL - 2*END) * maximo del eje
// ---------------------------------------------------------------------
`define CFG_POT_FULL    21626       // codigo  lectura del ADC a 3.3 V
`define CFG_POT_END     200         // codigo  en cada punta se lee 0 o tope
`define CFG_POT_FILT    10          // 2^N muestras promediadas (10 = ~26 ms)
`define CFG_POT_HYST    4           // codigo  el pedido cambia si el pot pasa esto


// ---------------------------------------------------------------------
//  5. ENCODERS HALL                                        (motion.v)
//     1 paso = 1 flanco del Hall = 2*TH / 2^SHIFT cuentas (84 en el serial)
// ---------------------------------------------------------------------
`define CFG_HALL_TH     10813       // codigo  umbral alto/bajo (1.65 V)
`define CFG_HALL_SHIFT  8           // 2^N codigos de ADC = 1 cuenta
`define CFG_COUNT_MAX   999999      // cuentas  tope (6 digitos en el serial)


// ---------------------------------------------------------------------
//  6. SERIAL                                             (com_ctrl.v)
// ---------------------------------------------------------------------
`define CFG_BAUD        115200      // baudios
`define CFG_LINE_HZ     50          // lineas por segundo (minimo 26)
`define CFG_INV_X       0           // 1 = arranca con X invertido (orden I)
`define CFG_INV_Y       0           // 1 = arranca con Y invertido (orden I)


// ---------------------------------------------------------------------
//  7. GUIAS (solo referencia, no cambia el circuito)
// ---------------------------------------------------------------------
`define CFG_X_UM        69000       // um    largo de la guia X
`define CFG_Y_UM        52000       // um    largo de la guia Y


// ---------------------------------------------------------------------
//  Calculadas - no editar
// ---------------------------------------------------------------------
`define CFG_PWM_PERIOD  (`CFG_CLK_HZ / `CFG_PWM_HZ)
`define CFG_UART_DIV    (`CFG_CLK_HZ / `CFG_BAUD)
`define CFG_LINE_GAP    (`CFG_CLK_HZ / `CFG_LINE_HZ)

`endif

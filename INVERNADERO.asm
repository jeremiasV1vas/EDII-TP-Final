list        p=16f887    ; list directive to define processor
    #include    <p16f887.inc>   ; processor specific variable definitions


; '__CONFIG' directive is used to embed configuration data within .asm file.
; The labels following the directive are located in the respective .inc file.
; See respective data sheet for additional information on configuration word.

    __CONFIG    _CONFIG1, _LVP_OFF & _FCMEN_ON & _IESO_OFF & _BOR_OFF & _CPD_OFF & _CP_OFF & _MCLRE_ON & _PWRTE_ON & _WDT_OFF & _INTRC_OSC_NOCLKOUT
    __CONFIG    _CONFIG2, _WRT_OFF & _BOR21V



;***** VARIABLE DEFINITIONS
#DEFINE TMR0_VALUE d'152'   ; valor de recarga para timer0, con prescaler 1:32 y Fosc=4MHz, para obtener una interrupcion cada 3.33ms
#DEFINE DEBOUNCE_VALUE d'15' ; cantidad de ciclos de timer0 para considerar un rebote como valido (15 ciclos = ~50ms)
#DEFINE TICKS_MEDIO_SEG d'150' ; cantidad de interrupciones de timer0 para medio segundo
; definicion de banderas del registro "banderas"
#DEFINE TECLADO_PRESIONADO d'0' ; estado del teclado: 0 = no presionado, 1 = presionado
#DEFINE HABILITAR_TECLADO d'1'  ; estado para habilitar la lectura del teclado en la rutina de atencion de interrupcion por cambio de estado en puerto B
#DEFINE BUFFER_KEYPAD d'2'      ; estado para indicar que hay una tecla sin procesar
#DEFINE LEER_ADC d'3'           ; estado para indicar que pasaron 500ms y se debe leer el adc
; definicion de pines del puerto B usados como columnas
#DEFINE C1 d'4'     
#DEFINE C2 d'5'
#DEFINE C3 d'6'
#DEFINE C4 d'7'
; definicion de los estados 
#DEFINE NORMAL d'0'     ; estado base del programa
#DEFINE UMBRAL1 d'1'    ; programacion del primer digito del umbral
#DEFINE UMBRAL2 d'2'    ; programacion del segundo digito del umbral
; definicion de letras que el keypad me puede devolver
#DEFINE letraA b'00010000'
#DEFINE letraB b'00100000'
#DEFINE letraC b'00110000'
#DEFINE letraD b'01000000'
#DEFINE simboloAst b'01010000'
#DEFINE simboloNum b'01100000'
; definicion de sensores para el registro "sensor_mostrado"
#DEFINE SENSOR_TEMPERATURA d'0'
#DEFINE SENSOR_LUZ d'1'


cblock 0x20 ; inicio de bloque de variables en banco 0
    display_sel     ; variable para seleccionar el display a mostrar (2-0)
    display0_value  ; variable para almacenar el valor a mostrar en el display 0
    display1_value  ; variable para almacenar el valor a mostrar en el display 1
    display2_value  ; variable para almacenar el valor a mostrar en el display 2
    banderas    ; variable para almacenar banderas de estado
    cont_debounce   ; variable para contar ciclos de debounce del teclado
    cont_adc        ; variable para contar interrupciones hasta llegar a 500ms
    estado_actual   ; variable que guarda el estado actual del programa (0 a 2)
    estado_temporal ; variable que guarda de manera temporal el estado actual
    sensor_mostrado ; variable para definir el sensor mostrado en plantalla en estado normal
    keypad_value    ; variable para guardar la tecla presionada fuera de la isr del keypad
    config_umbral_temp  ; variable temporal para construccion del umbral (nibble alto=decenas, nibble bajo=unidades)
    
    ; umbrales en bcd
    umbral_alto_temperatura 
    umbral_bajo_temperatura 
    umbral_luz          
    
    ; umbrales convertidos a 8 bits listos para comparar con el adc
    umbral_alto_temp_8bit
    umbral_bajo_temp_8bit
    umbral_luz_8bit
    
    ; variables de lectura del adc
    adc_canal_actual    ; 0 = leyendo an0, 1 = leyendo an1
    adc_temperatura     ; valor de 8 bits de la lectura de temperatura
    adc_luz             ; valor de 8 bits de la lectura de luz
    
    ; variables temporales para conversiones y matematicas
    unidades_tmp
    decenas_tmp
    porcentaje_tmp
    umbral_8bit_tmp
    bcd_decenas         ; decenas calculadas desde binario
    bcd_unidades        ; unidades calculadas desde binario
    math_temp           ; registro temporal para bucles de resta
    
    ; variables para el calculo de porcentaje de luz
    acc_hi              ; byte alto del acumulador (resultado del porcentaje)
    acc_lo              ; byte bajo del acumulador
    loop_cnt            ; contador para el bucle de multiplicacion
    luz_porcentaje      ; guarda el valor final 0-99
endc

cblock 0x70 ; variables de interrupcion compartidas en todos los bancos
    w_temp          ; variable used for context saving
    status_temp     ; variable used for context saving
    pclath_temp     ; variable used for context saving
endc

;**********************************************************************
    ORG     0x000             ; processor reset vector

    nop
    goto    main              ; go to beginning of program


    ORG     0x004             ; interrupt vector location

    movwf   w_temp            ; save off current W register contents
    movf    STATUS,w          ; move status register into W register
    movwf   status_temp       ; save off contents of STATUS register
    movf    PCLATH,w      ; move pclath register into w register
    movwf   pclath_temp   ; save off contents of PCLATH register

    btfsc   INTCON, TMR0IF  ; verificar que la interrupcion fue por timer0
    goto isr_timer0     ; si fue por timer0, ir a rutina de atencion de timer0

    btfsc   INTCON, RBIF    ; verificar que la interrupcion fue por cambio de estado en puerto B
    goto isr_keypad     ; si fue por cambio de estado en puerto B, ir a rutina de atencion de keypad

fin_isr
    movf    pclath_temp,w     ; retrieve copy of PCLATH register
    movwf   PCLATH        ; restore pre-isr PCLATH register contents
    movf    status_temp,w     ; retrieve copy of STATUS register
    movwf   STATUS            ; restore pre-isr STATUS register contents
    swapf   w_temp,f
    swapf   w_temp,w          ; restore pre-isr W register contents
    retfie

ORG 0x020

tabla
    ; tabla de conversion de numeros a display de 7 segmentos
    ; se considera que el bit 0 es a y el bit 7 es dp (logica positiva)
    addwf   PCL, f
    retlw   b'00111111' ; 0
    retlw   b'00000110' ; 1
    retlw   b'01011011' ; 2
    retlw   b'01001111' ; 3
    retlw   b'01100110' ; 4
    retlw   b'01101101' ; 5
    retlw   b'01111101' ; 6
    retlw   b'00000111' ; 7
    retlw   b'01111111' ; 8
    retlw   b'01101111' ; 9

ORG 0x100
tabla_bcd_adc
    ; tabla para mapear porcentaje a valor adc de 8 bits
    addwf   PCL, f
    dt   0,   3,   5,   8,  10,  13,  15,  18,  21,  23
    dt  26,  28,  31,  33,  36,  39,  41,  44,  46,  49
    dt  52,  54,  57,  59,  62,  64,  67,  70,  72,  75
    dt  77,  80,  82,  85,  88,  90,  93,  95,  98, 100
    dt 103, 106, 108, 111, 113, 116, 118, 121, 124, 126
    dt 129, 131, 134, 137, 139, 142, 144, 147, 149, 152
    dt 155, 157, 160, 162, 165, 167, 170, 173, 175, 178
    dt 180, 183, 185, 188, 191, 193, 196, 198, 201, 203
    dt 206, 209, 211, 214, 216, 219, 222, 224, 227, 229
    dt 232, 234, 237, 240, 242, 245, 247, 250, 252, 255


ORG 0x200

main
    ; configuración del oscilador interno
    banksel OSCCON
    movlw   b'01100000'     ; configurar oscilador interno a 4mhz
    movwf   OSCCON

    ; inicializacion de variables
    banksel 0
    movlw   d'2'
    movwf   display_sel
    movlw   b'00111111'     ; valor inicial (000)
    movwf   display0_value
    movwf   display1_value
    movwf   display2_value
    
    movlw   DEBOUNCE_VALUE
    movwf   cont_debounce
    movlw   TICKS_MEDIO_SEG
    movwf   cont_adc
    
    clrf    banderas
    bsf     banderas, HABILITAR_TECLADO
    
    clrf    estado_actual
    bsf     estado_actual, NORMAL
    clrf    estado_temporal
    clrf    sensor_mostrado
    bsf     sensor_mostrado, SENSOR_TEMPERATURA
    clrf    config_umbral_temp
    clrf    adc_canal_actual
    clrf    adc_temperatura
    clrf    adc_luz

    ; configuracion de pines para display
    banksel TRISD
    clrf    TRISD
    banksel PORTD
    clrf    PORTD

    ; configuracion puerto E
    banksel ANSEL
    bcf     ANSEL,7
    bcf     ANSEL,6
    bcf     ANSEL,5
    banksel TRISE
    clrf    TRISE
    banksel PORTE
    clrf    PORTE

    ; configuracion inicial de adc
    banksel ADCON1
    movlw   0x00            ; justificacion izquierda, vref=vdd
    movwf   ADCON1
    banksel TRISA
    bsf     TRISA, 0        ; ra0 (temperatura)
    bsf     TRISA, 1        ; ra1 (luz)
    banksel ANSEL
    movlw   b'00000011'     ; an0 y an1 analógicos
    movwf   ANSEL
    banksel ANSELH
    clrf    ANSELH
    banksel ADCON0
    movlw   b'01000001'     ; fosc/8, ch0, adc on
    movwf   ADCON0

    ; configuracion timer0
    banksel OPTION_REG
    movlw   b'01000100'     ; prescaler 1:32, reloj interno
    movwf   OPTION_REG
    banksel TMR0
    movlw   TMR0_VALUE  
    movwf   TMR0

    ; configuracion keypad 4x4
    banksel TRISB
    movlw   b'11110000'
    movwf   TRISB
    banksel PORTB
    clrf    PORTB
    banksel IOCB
    movlw   b'11110000'
    movwf   IOCB
    banksel WPUB
    movlw   b'11110000'
    movwf   WPUB

    ; habilitar interrupciones
    banksel INTCON
    clrf    INTCON
    bsf     INTCON, TMR0IE
    bsf     INTCON, RBIE
    bsf     INTCON, GIE

    goto main_loop


main_loop
    ; bloque de lectura ciclica de adc
    btfss   banderas, LEER_ADC
    goto    revisar_teclado
    
    bcf     banderas, LEER_ADC
    bsf     ADCON0, GO
esperar_adc
    btfsc   ADCON0, GO
    goto    esperar_adc
    
    movf    ADRESH, w
    btfsc   adc_canal_actual, 0
    goto    guardar_an1

guardar_an0
    movwf   adc_temperatura 
    bsf     adc_canal_actual, 0 
    movlw   b'01000101'     ; preparar ch1
    movwf   ADCON0
    goto    revisar_teclado

guardar_an1
    movwf   adc_luz         
    bcf     adc_canal_actual, 0 
    movlw   b'01000001'     ; preparar ch0
    movwf   ADCON0

revisar_teclado
    btfss   banderas, BUFFER_KEYPAD
    goto    actualizar_pantalla

    bcf     banderas, BUFFER_KEYPAD

    ; despachador principal de estados
    btfsc   estado_actual, NORMAL
    goto    loop_estado_normal
    btfsc   estado_actual, UMBRAL1
    goto    loop_estado_umbral1
    goto    loop_estado_umbral2

actualizar_pantalla
    ; solo actualizamos lecturas vivas si estamos en estado normal
    btfss   estado_actual, NORMAL
    goto    main_loop

    btfsc   sensor_mostrado, SENSOR_TEMPERATURA
    goto    mostrar_temp
    goto    mostrar_luz

mostrar_temp
    ; temp_real = adc_temperatura * 2
    bcf     STATUS, C
    rlf     adc_temperatura, w
    
    ; --- FILTRO ANTIDESBORDE DE TEMPERATURA ---
    movwf   math_temp       ; Guardo el valor original
    sublw   d'99'           ; Resto: 99 - W
    btfss   STATUS, C       ; Si C=0, el valor original era mayor a 99
    goto    limitar_t
    movf    math_temp, w    ; Si era <= 99, recupero el valor original
    goto    bcd_t
limitar_t
    movlw   d'99'           ; Lo clavo en 99 máximo para proteger la tabla
bcd_t:
    ; ------------------------------------------
    call    bin_a_bcd

    movlw   b'01111000'                 ; 't' en 7seg
    movwf   display0_value
    movf    bcd_decenas, w
    call    tabla
    movwf   display1_value
    movf    bcd_unidades, w
    call    tabla
    movwf   display2_value
    goto    main_loop

mostrar_luz
    ; calculamos el porcentaje de luz actual
    call    calcular_porcentaje_luz
    
    ; --- FILTRO ANTIDESBORDE DE LUZ ---
    movf    luz_porcentaje, w
    movwf   math_temp
    sublw   d'99'
    btfss   STATUS, C
    goto    limitar_l
    movf    math_temp, w
    goto    bcd_l
limitar_l
    movlw   d'99'
bcd_l:
    ; ----------------------------------
    call    bin_a_bcd

    movlw   b'00111000'                 ; 'L' en 7seg
    movwf   display0_value
    movf    bcd_decenas, w
    call    tabla
    movwf   display1_value
    movf    bcd_unidades, w
    call    tabla
    movwf   display2_value
    goto    main_loop

; -------------------------------------------------------
loop_estado_normal
    movf    keypad_value, w
    xorlw   letraA
    btfsc   STATUS, Z
    goto    loop_normal_letraA

    movf    keypad_value, w
    xorlw   letraB
    btfsc   STATUS, Z
    goto    loop_normal_letraB

    movf    keypad_value, w
    xorlw   letraC
    btfsc   STATUS, Z
    goto    loop_normal_letraC

    goto    loop_normal_ast

loop_normal_letraA
    clrf    estado_actual
    bsf     estado_actual, UMBRAL1
    movf    keypad_value, w
    movwf   estado_temporal
    movlw   b'00111110'                 ; 'U'
    movwf   display0_value
    movlw   b'01000000'                 ; '-'
    movwf   display1_value
    movwf   display2_value
    clrf    keypad_value
    goto    main_loop

loop_normal_letraB
    clrf    estado_actual
    bsf     estado_actual, UMBRAL1
    movf    keypad_value, w
    movwf   estado_temporal
    movlw   b'00111110'                 ; 'U'
    movwf   display0_value
    movlw   b'01000000'                 ; '-'
    movwf   display1_value
    movwf   display2_value
    clrf    keypad_value
    goto    main_loop

loop_normal_letraC
    clrf    estado_actual
    bsf     estado_actual, UMBRAL1
    movf    keypad_value, w
    movwf   estado_temporal
    movlw   b'00111110'                 ; 'U'
    movwf   display0_value
    movlw   b'01000000'                 ; '-'
    movwf   display1_value
    movwf   display2_value
    clrf    keypad_value
    goto    main_loop

loop_normal_ast
    ; Alternar sensor mostrado al tocar el asterisco
    btfsc   sensor_mostrado, SENSOR_TEMPERATURA
    goto    loop_ast_cambiar_a_luz
    clrf    sensor_mostrado
    bsf     sensor_mostrado, SENSOR_TEMPERATURA
    clrf    keypad_value
    goto    main_loop
    
loop_ast_cambiar_a_luz
    clrf    sensor_mostrado
    bsf     sensor_mostrado, SENSOR_LUZ
    clrf    keypad_value
    goto    main_loop

; -------------------------------------------------------
loop_estado_umbral1
    movf    keypad_value, w
    xorlw   letraD
    btfsc   STATUS, Z
    goto    loop_umbral1_cancelar

    ; validar si es numero (0-9)
    movf    keypad_value, w
    sublw   d'9'
    btfss   STATUS, C
    goto    main_loop       

    movf    keypad_value, w
    movwf   config_umbral_temp
    swapf   config_umbral_temp, f
    movf    keypad_value, w
    call    tabla
    movwf   display1_value
    movlw   b'01000000'                 ; '-'
    movwf   display2_value
    clrf    estado_actual
    bsf     estado_actual, UMBRAL2
    clrf    keypad_value
    goto    main_loop

loop_umbral1_cancelar
    clrf    estado_actual
    bsf     estado_actual, NORMAL
    clrf    config_umbral_temp
    clrf    keypad_value
    goto    main_loop

; -------------------------------------------------------
loop_estado_umbral2
    movf    keypad_value, w
    xorlw   letraD
    btfsc   STATUS, Z
    goto    loop_umbral2_volver

    movf    keypad_value, w
    sublw   d'9'
    btfss   STATUS, C
    goto    main_loop       

    movf    keypad_value, w
    iorwf   config_umbral_temp, f
    movf    keypad_value, w
    call    tabla
    movwf   display2_value

    ; aqui procesamos el bcd a 8 bits usando la rutina adaptada
    call    convertir_bcd_8bit

    ; guardar en la variable correcta
    movf    estado_temporal, w
    xorlw   letraA
    btfsc   STATUS, Z
    goto    loop_umbral2_guardar_alto

    movf    estado_temporal, w
    xorlw   letraB
    btfsc   STATUS, Z
    goto    loop_umbral2_guardar_bajo

    goto    loop_umbral2_guardar_luz

loop_umbral2_guardar_alto
    movf    config_umbral_temp, w
    movwf   umbral_alto_temperatura
    movf    umbral_8bit_tmp, w
    movwf   umbral_alto_temp_8bit       
    goto    loop_umbral2_fin

loop_umbral2_guardar_bajo
    movf    config_umbral_temp, w
    movwf   umbral_bajo_temperatura
    movf    umbral_8bit_tmp, w
    movwf   umbral_bajo_temp_8bit
    goto    loop_umbral2_fin

loop_umbral2_guardar_luz
    movf    config_umbral_temp, w
    movwf   umbral_luz
    movf    umbral_8bit_tmp, w
    movwf   umbral_luz_8bit
    goto    loop_umbral2_fin

loop_umbral2_fin
    clrf    config_umbral_temp
    clrf    estado_actual
    bsf     estado_actual, NORMAL
    clrf    keypad_value
    goto    main_loop

loop_umbral2_volver
    clrf    config_umbral_temp
    clrf    estado_actual
    bsf     estado_actual, UMBRAL1
    movlw   b'01000000'
    movwf   display1_value
    movwf   display2_value
    clrf    keypad_value
    goto    main_loop


; ************************************************************************
; Subrutina ADC a Porcentaje (Luz)
; Multiplica adc_luz * 100 sumandolo en un acumulador de 16 bits.
; El byte alto (High Byte) es el resultado automatico de dividir por 256.
calcular_porcentaje_luz
    clrf    acc_hi
    clrf    acc_lo
    movf    adc_luz, w
    btfsc   STATUS, Z
    goto    fin_adc_porcentaje      ; si es 0, dejamos luz_porcentaje en 0
    movwf   loop_cnt                ; cargamos cantidad de veces a sumar
suma_100
    movlw   d'100'
    addwf   acc_lo, f               ; sumamos al byte bajo
    btfsc   STATUS, C               ; si hay carry...
    incf    acc_hi, f               ; incrementamos byte alto
    decfsz  loop_cnt, f             ; repetimos segun el valor leido del adc
    goto    suma_100
fin_adc_porcentaje
    movf    acc_hi, w               ; cargamos el resultado de la division
    movwf   luz_porcentaje
    return


; ************************************************************************
; Subrutina Binario a BCD para Displays (acepta valores de 0 a 99 desde W)
bin_a_bcd
    movwf   math_temp               ; W contiene el valor a dividir
    clrf    bcd_decenas
restar_10
    movlw   d'10'
    subwf   math_temp, w
    btfss   STATUS, C               ; si c=0 el resultado fue negativo
    goto    fin_bcd
    movwf   math_temp               ; actualizamos el saldo
    incf    bcd_decenas, f          ; sumamos una decena
    goto    restar_10
fin_bcd
    movf    math_temp, w            ; el resto son las unidades
    movwf   bcd_unidades
    return


; ************************************************************************
; Subrutina BCD a 8-Bits
convertir_bcd_8bit
    movf    config_umbral_temp, w
    andlw   0xF0
    movwf   decenas_tmp
    swapf   decenas_tmp, f
    movf    config_umbral_temp, w
    andlw   0x0F
    movwf   unidades_tmp
    
    clrf    porcentaje_tmp
    movf    decenas_tmp, w
    btfsc   STATUS, Z
    goto    sumar_unidades_bcd
bucle_por_diez
    movlw   d'10'
    addwf   porcentaje_tmp, f
    decfsz  decenas_tmp, f
    goto    bucle_por_diez
sumar_unidades_bcd
    movf    unidades_tmp, w
    addwf   porcentaje_tmp, f
    
    movlw   HIGH(tabla_bcd_adc) 
    movwf   PCLATH
    movf    porcentaje_tmp, w
    call    tabla_bcd_adc
    clrf    PCLATH              
    movwf   umbral_8bit_tmp
    return

; ************************************************************************
; Rutina de atencion de interrupcion de timer0
isr_timer0
    banksel TMR0
    movlw   TMR0_VALUE  
    movwf   TMR0
    banksel 0
    
    decfsz  cont_adc, f
    goto    subrutina_debounce  
    
    movlw   TICKS_MEDIO_SEG
    movwf   cont_adc
    bsf     banderas, LEER_ADC

subrutina_debounce
    btfss   banderas, TECLADO_PRESIONADO
    goto    subrutina_multiplexado

    decfsz  cont_debounce, f
    goto    subrutina_multiplexado

    banksel PORTB
    movf    PORTB, w
    banksel 0
    andlw   b'11110000'
    xorlw   b'11110000'
    btfss   STATUS, Z
    goto    teclado_aun_presionado

teclado_liberado
    movlw   DEBOUNCE_VALUE
    movwf   cont_debounce
    bsf     banderas, HABILITAR_TECLADO
    bcf     banderas, TECLADO_PRESIONADO
    goto    subrutina_multiplexado

teclado_aun_presionado
    movlw   DEBOUNCE_VALUE
    movwf   cont_debounce
    goto    subrutina_multiplexado


subrutina_multiplexado
    banksel PORTE
    clrf    PORTE

    banksel display_sel
    movf    display_sel, w
    btfsc   STATUS, Z
    goto    caso_display0
    
    xorlw   d'1'
    btfsc   STATUS, Z
    goto    caso_display1
    
    goto    caso_display2

caso_display0
    movf    display0_value,w
    movwf   PORTD
    bsf     PORTE, 0
    goto fin_multiplexado
caso_display1
    movf    display1_value,w
    movwf   PORTD
    bsf     PORTE, 1
    goto fin_multiplexado
caso_display2
    movf    display2_value,w
    movwf   PORTD
    bsf     PORTE, 2
    goto fin_multiplexado

fin_multiplexado
    movf    display_sel, w
    btfsc   STATUS, Z
    goto    reset_display_sel
    decf    display_sel, f
    goto    fin_actualizacion

reset_display_sel
    movlw   d'2'
    movwf   display_sel

fin_actualizacion
    bcf     INTCON, TMR0IF
    goto    fin_isr

; ************************************************************************
; Rutina de atencion de interrupcion por cambio de estado en puerto B
isr_keypad
    banksel PORTB
    movf    PORTB, w

    btfss   banderas, HABILITAR_TECLADO
    goto    fin_isr_keypad
    
    bsf     banderas, TECLADO_PRESIONADO
    goto    leer_teclado

leer_teclado
    bcf     banderas, HABILITAR_TECLADO
    banksel PORTB
    btfss PORTB, C1
    goto columna1
    btfss PORTB, C2
    goto columna2
    btfss PORTB, C3
    goto columna3
    btfss PORTB, C4
    goto columna4
    goto fin_isr_keypad

columna1
    bsf     PORTB, 0
    bsf     PORTB, 1
    bsf     PORTB, 2
    bsf     PORTB, 3
    bcf     PORTB, 0
    btfss   PORTB, C1
    goto    tecla1
    bsf     PORTB, 0
    bcf     PORTB, 1
    btfss   PORTB, C1
    goto    tecla4
    bsf     PORTB, 1
    bcf     PORTB, 2
    btfss   PORTB, C1
    goto    tecla7
    bsf     PORTB, 2
    bcf     PORTB, 3
    btfss   PORTB, C1
    goto    teclaAst
    goto    fin_isr_keypad

columna2
    bsf     PORTB, 0
    bsf     PORTB, 1
    bsf     PORTB, 2
    bsf     PORTB, 3
    bcf     PORTB, 0
    btfss   PORTB, C2
    goto    tecla2
    bsf     PORTB, 0
    bcf     PORTB, 1
    btfss   PORTB, C2
    goto    tecla5
    bsf     PORTB, 1
    bcf     PORTB, 2
    btfss   PORTB, C2
    goto    tecla8
    bsf     PORTB, 2
    bcf     PORTB, 3
    btfss   PORTB, C2
    goto    tecla0
    goto    fin_isr_keypad

columna3
    bsf     PORTB, 0
    bsf     PORTB, 1
    bsf     PORTB, 2
    bsf     PORTB, 3
    bcf     PORTB, 0
    btfss   PORTB, C3
    goto    tecla3
    bsf     PORTB, 0
    bcf     PORTB, 1
    btfss   PORTB, C3
    goto    tecla6
    bsf     PORTB, 1
    bcf     PORTB, 2
    btfss   PORTB, C3
    goto    tecla9
    bsf     PORTB, 2
    bcf     PORTB, 3
    btfss   PORTB, C3
    goto    teclaNum
    goto    fin_isr_keypad

columna4
    bsf     PORTB, 0
    bsf     PORTB, 1
    bsf     PORTB, 2
    bsf     PORTB, 3
    bcf     PORTB, 0
    btfss   PORTB, C4
    goto    teclaA
    bsf     PORTB, 0
    bcf     PORTB, 1
    btfss   PORTB, C4
    goto    teclaB
    bsf     PORTB, 1
    bcf     PORTB, 2
    btfss   PORTB, C4
    goto    teclaC
    bsf     PORTB, 2
    bcf     PORTB, 3
    btfss   PORTB, C4
    goto    teclaD
    goto    fin_isr_keypad

tecla1
    btfsc   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   d'1'
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

tecla2
    btfsc   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   d'2'
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

tecla3
    btfsc   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   d'3'
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

tecla4
    btfsc   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   d'4'
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

tecla5
    btfsc   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   d'5'
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

tecla6
    btfsc   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   d'6'
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

tecla7
    btfsc   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   d'7'
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

tecla8
    btfsc   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   d'8'
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

tecla9
    btfsc   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   d'9'
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

tecla0
    btfsc   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   d'0'
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

teclaA
    btfss   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   letraA
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

teclaB
    btfss   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   letraB
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

teclaC
    btfss   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   letraC
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

teclaD
    btfsc   estado_actual, NORMAL
    goto    fin_isr_keypad
    movlw   letraD
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad

teclaAst
    btfss   estado_actual, NORMAL
    goto fin_isr_keypad
    movlw   simboloAst
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD
    goto fin_isr_keypad
    
teclaNum
    goto fin_isr_keypad

fin_isr_keypad
    banksel PORTB
    movlw   b'00000000'
    movwf   PORTB 
    banksel INTCON
    bcf  INTCON, RBIF
    goto fin_isr
    END
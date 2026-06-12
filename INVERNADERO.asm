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
; definicion de banderas del registro "banderas"
#DEFINE TECLADO_PRESIONADO d'0' ; estado del teclado: 0 = no presionado, 1 = presionado
#DEFINE HABILITAR_TECLADO d'1'  ; estado para habilitar la lectura del teclado en la rutina de atencion de interrupcion por cambio de estado en puerto B
#DEFINE BUFFER_KEYPAD d'2'
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
    cont_tests1     ; variable para utilizada para contar ciclos de pruebas
    cont_tests2     ; variable para utilizada para contar ciclos de pruebas
    banderas    ; variable para almacenar banderas de estado
    ;             (bit 0: estado del teclado, bit 1: habilitar lectura del teclado)
    cont_debounce   ; variable para contar ciclos de debounce del teclado
    estado_actual   ; variable que guarda el estado actual del programa (0 a 2)
    estado_temporal ; variable que guarda de manera temporal el estado actual
    sensor_mostrado ; variable para definir el sensor mostrado en plantalla en estado normal
    keypad_value    ; variable para guardar la tecla presionada fuera de la isr del keypad
    config_umbral_temp  ; variable temporal para construccion del umbral (nibble alto=decenas, nibble bajo=unidades)
    umbral_alto_temperatura ; umbral superior de temperatura en BCD (ej: 0x35 = 35 grados)
    umbral_bajo_temperatura ; umbral inferior de temperatura en BCD (ej: 0x20 = 20 grados)
    umbral_luz          ; umbral de luminosidad en BCD (ej: 0x50 = 50%)
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
    ; el orden de los segmentos es: a, b, c, d, e, f, g, dp
    ; se considera que el bit 0 es a y el bit 7 es dp
    ; entonces el orden es : dp g f e d c b a
    ; se utiliza logica positiva, es decir, un bit en 1 enciende el segmento correspondiente

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

ORG 0x040

main
    ; inicializacion de variables
    banksel 0
    movlw   d'2'
    movwf   display_sel
    movlw   b'00111111'     ; valor para mostrar el numero 0 en el display de 7 segmentos
    movwf   display0_value
    movlw   b'00111111'
    movwf   display1_value
    movlw   b'00111111'
    movwf   display2_value
    movlw   DEBOUNCE_VALUE
    movwf   cont_debounce   ; inicializo el contador del debounce del teclado
    clrf    banderas        ; inicializo el registro de banderas
    bsf     banderas, HABILITAR_TECLADO ; arrancar con el teclado habilitado
    clrf    estado_actual
    bsf     estado_actual, NORMAL
    clrf    estado_temporal
    clrf    sensor_mostrado
    bsf     sensor_mostrado, SENSOR_TEMPERATURA
    movlw   0x35        ; umbral alto temperatura: 35 grados
    movwf   umbral_alto_temperatura
    movlw   0x15        ; umbral bajo temperatura: 15 grados
    movwf   umbral_bajo_temperatura
    movlw   0x50        ; umbral de luz: 50%
    movwf   umbral_luz
    clrf    config_umbral_temp

    ; configuración del oscilador interno
    banksel OSCCON
    movlw   b'01100000'     ; Configurar oscilador interno a 4MHz
    movwf   OSCCON

    ; configuracion de pines para usar el display de 7 segmentos

    banksel TRISD
    clrf    TRISD
    banksel PORTD
    clrf    PORTD

    ; configuracion del puerto E para seleccionar el display a mostrar
    banksel ANSEL
    bcf ANSEL,7
    bcf ANSEL,6
    bcf ANSEL,5
    banksel TRISE
    clrf    TRISE
    banksel PORTE
    clrf    PORTE


    ; configuracion de timer0
    ;   bit7 nRBPU  = 0 -> pull-ups PORTB habilitados globalmente
    ;   bit6 INTEDG = 1 -> flanco INT externa (no utilizada)
    ;   bit5 T0CS   = 0 -> TMR0 fuente interna (Fosc/4)
    ;   bit4 T0SE   = 0 -> irrelevante con fuente interna
    ;   bit3 PSA    = 0 -> prescaler asignado a TMR0
    ;   bit2 PS2    = 1 -+
    ;   bit1 PS1    = 0  +-> PS=100, prescaler 1:32
    ;   bit0 PS0    = 0 -+
    banksel OPTION_REG
    movlw   b'01000100'
    movwf   OPTION_REG

    ; cargar valor de recarga para timer0
    banksel TMR0
    movlw   TMR0_VALUE  
    movwf   TMR0

    ; configuracion de interrupciones para keypad 4x4
    banksel ANSELH
    clrf    ANSELH
    banksel TRISB
    movlw   b'11110000' ; configurar RB4-RB7 como entradas para el keypad
    movwf   TRISB
    banksel PORTB
    movlw   b'00000000' 
    movwf   PORTB
    banksel IOCB
    movlw   b'11110000' ; habilitar interrupciones por cambio de estado en RB4-RB7
    movwf   IOCB
    banksel WPUB
    movlw   b'11110000' ; habilitar pull-ups en RB4-RB7
    movwf   WPUB
    ; habilitar interrupciones

    banksel INTCON
    clrf    INTCON  ; limpiar registros de interrupciones
    bsf     INTCON, TMR0IE  ; habilitar interrupcion de timer0
    bsf     INTCON, RBIE    ; habilitar interrupcion por cambio de estado en puerto B
    bsf     INTCON, GIE ; habilitar interrupciones globales

    goto main_loop


main_loop
    btfss   banderas, BUFFER_KEYPAD     ; verifico si hubo un ingreso por teclado
    goto    main_loop                   ; si no hubo, sigo esperando

    bcf     banderas, BUFFER_KEYPAD     ; bajo la bandera

    ; despachar segun estado actual
    btfsc   estado_actual, NORMAL
    goto    loop_estado_normal
    btfsc   estado_actual, UMBRAL1
    goto    loop_estado_umbral1
    goto    loop_estado_umbral2         ; por descarte

; -------------------------------------------------------
loop_estado_normal
    ; en estado normal solo A, B, C y * son validas
    ; las demas fueron filtradas en la ISR

    movf    keypad_value, w
    xorlw   letraA
    btfsc   STATUS, Z
    goto    loop_normal_letraA          ; entrar a config umbral alto temperatura

    movf    keypad_value, w
    xorlw   letraB
    btfsc   STATUS, Z
    goto    loop_normal_letraB          ; entrar a config umbral bajo temperatura

    movf    keypad_value, w
    xorlw   letraC
    btfsc   STATUS, Z
    goto    loop_normal_letraC          ; entrar a config umbral luz

    goto    loop_normal_ast             ; por descarte es simboloAst

loop_normal_letraA
    clrf    estado_actual
    bsf     estado_actual, UMBRAL1
    movf    keypad_value, w             ; recuperar valor del keypad para guardar
    movwf   estado_temporal             ; guardar que umbral estamos configurando (letraA)
    ; mostrar 'u' en display0, guiones en display1 y display2
    movlw   b'00111110'                 ; codigo 7seg de 'U'
    movwf   display0_value
    movlw   b'01000000'                 ; codigo 7seg de '-'
    movwf   display1_value
    movwf   display2_value
    goto    main_loop

loop_normal_letraB
    clrf    estado_actual
    bsf     estado_actual, UMBRAL1
    movf    keypad_value, w
    movwf   estado_temporal
    movlw   b'00111110'
    movwf   display0_value
    movlw   b'01000000'
    movwf   display1_value
    movwf   display2_value
    goto    main_loop

loop_normal_letraC
    clrf    estado_actual
    bsf     estado_actual, UMBRAL1
    movf    keypad_value, w
    movwf   estado_temporal
    movlw   b'00111110'
    movwf   display0_value
    movlw   b'01000000'
    movwf   display1_value
    movwf   display2_value
    goto    main_loop

loop_normal_ast
    ; alternar sensor mostrado entre temperatura y luz
    btfsc   sensor_mostrado, SENSOR_TEMPERATURA
    goto    loop_ast_cambiar_a_luz
    clrf    sensor_mostrado
    bsf     sensor_mostrado, SENSOR_TEMPERATURA
    goto    main_loop
loop_ast_cambiar_a_luz
    clrf    sensor_mostrado
    bsf     sensor_mostrado, SENSOR_LUZ
    goto    main_loop

; -------------------------------------------------------
loop_estado_umbral1
    ; espera el primer digito (decena) o D para cancelar

    movf    keypad_value, w
    xorlw   letraD
    btfsc   STATUS, Z
    goto    loop_umbral1_cancelar

    ; es un digito numerico: guardarlo como nibble alto de config_umbral_temp
    ; keypad_value tiene el valor 0-9
    ; para ponerlo en el nibble alto: swap y AND
    movf    keypad_value, w
    movwf   config_umbral_temp          ; guardar temporalmente
    swapf   config_umbral_temp, f       ; llevar al nibble alto
    ; display1 muestra el digito ingresado, display2 muestra guion
    movf    keypad_value, w
    call    tabla                       ; convertir a codigo 7seg
    movwf   display1_value
    movlw   b'01000000'                 ; '-'
    movwf   display2_value
    ; avanzar a UMBRAL2
    clrf    estado_actual
    bsf     estado_actual, UMBRAL2
    goto    main_loop

loop_umbral1_cancelar
    clrf    estado_actual
    bsf     estado_actual, NORMAL
    clrf    config_umbral_temp
    goto    main_loop

; -------------------------------------------------------
loop_estado_umbral2
    ; espera el segundo digito (unidad) o D para volver a UMBRAL1

    movf    keypad_value, w
    xorlw   letraD
    btfsc   STATUS, Z
    goto    loop_umbral2_volver

    ; es un digito numerico: ponerlo en nibble bajo y cargar el umbral
    movf    keypad_value, w
    iorwf   config_umbral_temp, f       ; nibble bajo = unidad, nibble alto ya tenia la decena

    ; mostrar el digito ingresado en display2
    movf    keypad_value, w
    call    tabla
    movwf   display2_value

    ; guardar en el umbral correspondiente segun estado_temporal
    movf    estado_temporal, w
    xorlw   letraA
    btfsc   STATUS, Z
    goto    loop_umbral2_guardar_alto

    movf    estado_temporal, w
    xorlw   letraB
    btfsc   STATUS, Z
    goto    loop_umbral2_guardar_bajo

    goto    loop_umbral2_guardar_luz     ; por descarte es letraC

loop_umbral2_guardar_alto
    movf    config_umbral_temp, w
    movwf   umbral_alto_temperatura
    goto    loop_umbral2_fin

loop_umbral2_guardar_bajo
    movf    config_umbral_temp, w
    movwf   umbral_bajo_temperatura
    goto    loop_umbral2_fin

loop_umbral2_guardar_luz
    movf    config_umbral_temp, w
    movwf   umbral_luz
    goto    loop_umbral2_fin

loop_umbral2_fin
    clrf    config_umbral_temp
    clrf    estado_actual
    bsf     estado_actual, NORMAL
    movlw   b'00111111'                 ; restaurar displays a 0 al volver a normal
    movwf   display0_value
    movwf   display1_value
    movwf   display2_value
    goto    main_loop

loop_umbral2_volver
    ; D: volver a UMBRAL1, limpiar nibble alto
    clrf    config_umbral_temp
    clrf    estado_actual
    bsf     estado_actual, UMBRAL1
    movlw   b'01000000'                 ; '-'
    movwf   display1_value
    movwf   display2_value
    goto    main_loop

; ************************************************************************
; Rutina de atencion de interrupcion de timer0
isr_timer0
    banksel TMR0
    movlw   TMR0_VALUE  ; recargar timer0 para obtener una interrupcion cada 3.33ms
    movwf   TMR0
    banksel 0

subrutina_debounce
    btfss   banderas, TECLADO_PRESIONADO    ; si no hay tecla pendiente, saltar al multiplexado
    goto    subrutina_multiplexado

    decfsz  cont_debounce, f                ; decrementar contador de debounce
    goto    subrutina_multiplexado          ; todavia no llego a 0, seguir

    ; llego a 0, por lo tanto verifico si el usuario ya solto la tecla
    banksel PORTB
    movf    PORTB, w                        ; leemos el estado de las columnas
    banksel 0                               ; regresamos al banco 0 para usar STATUS
    andlw   b'11110000'                     ; aislamos los pines RB4-RB7
    xorlw   b'11110000'                     ; si todas son 1 (tecla soltada), Z se vuelve 1
    btfss   STATUS, Z
    goto    teclado_aun_presionado          ; Z=0 -> Sigue presionando

teclado_liberado
    ; la tecla fue soltada y paso el tiempo de rebote. Habilitamos nueva lectura.
    movlw   DEBOUNCE_VALUE                  ; recargar contador para el proximo uso
    movwf   cont_debounce
    bsf     banderas, HABILITAR_TECLADO     ; volvemos a aceptar lecturas
    bcf     banderas, TECLADO_PRESIONADO    ; apagamos este temporizador
    goto    subrutina_multiplexado

teclado_aun_presionado
    ; el usuario mantiene la tecla presionada. Reiniciar contador y seguir bloqueando.
    movlw   DEBOUNCE_VALUE
    movwf   cont_debounce
    goto    subrutina_multiplexado


subrutina_multiplexado
    banksel PORTE
    clrf    PORTE           ; apagar todos los displays (evita ghosting)

    banksel display_sel     ; asegurarnos de estar en el banco 0
    movf    display_sel, w
    btfsc   STATUS, Z
    goto    caso_display0   ; si es 0, va al display 0
    
    xorlw   d'1'
    btfsc   STATUS, Z
    goto    caso_display1   ; si era 1, va al display 1
    
    goto    caso_display2   ; por descarte es el display 2

caso_display0
    movf    display0_value,w    ; cargar el valor a mostrar en display0
    movwf   PORTD           ; mostrar valor en display0
    bsf     PORTE, 0        ; encender display0
    goto fin_multiplexado
caso_display1
    movf    display1_value,w    ; cargar el valor a mostrar en display1
    movwf   PORTD           ; mostrar valor en display1
    bsf     PORTE, 1        ; encender display1
    goto fin_multiplexado
caso_display2
    movf    display2_value,w    ; cargar el valor a mostrar en display2
    movwf   PORTD           ; mostrar valor en display2
    bsf     PORTE, 2        ; encender display2
    goto fin_multiplexado

fin_multiplexado
    ; avanzar display_sel ciclicamente: 2 -> 1 -> 0 -> 2
    movf    display_sel, w
    btfsc   STATUS, Z       ; si display_sel ya es 0, resetear
    goto    reset_display_sel
    decf    display_sel, f  ; paso al siguiente display
    goto    fin_actualizacion

reset_display_sel
    movlw   d'2'
    movwf   display_sel

fin_actualizacion
    bcf     INTCON, TMR0IF
    goto    fin_isr

; fin de la rutina de atencion de interrupcion de timer0    
; ************************************************************************

; ************************************************************************
; Rutina de atencion de interrupcion por cambio de estado en puerto B (keypad)
isr_keypad
    ; limpiar mismatch leyendo PORTB antes de cualquier otra cosa
    banksel PORTB
    movf    PORTB, w

    btfss   banderas, HABILITAR_TECLADO ; verificar si la lectura del teclado esta habilitada
    goto    fin_isr_keypad          ; si no esta habilitada, ignorar rebote
    
    bsf     banderas, TECLADO_PRESIONADO ; indica al timer0 que empiece el debounce
    goto    leer_teclado            ; si esta habilitada, ir a leer el teclado

leer_teclado
    bcf     banderas, HABILITAR_TECLADO ; deshabilitar hasta proximo ciclo de debounce
    ; compruebo que columna se presiono
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
    ; subir todas las filas, luego bajar de a una para identificar la fila
    bsf     PORTB, 0
    bsf     PORTB, 1
    bsf     PORTB, 2
    bsf     PORTB, 3
    bcf     PORTB, 0            ; activo solo la fila 1
    btfss   PORTB, C1           ; reviso si la lectura persiste
    goto    tecla1     ; se presiono 1
    bsf     PORTB, 0
    bcf     PORTB, 1            ; activo solo la fila 2
    btfss   PORTB, C1           ; reviso si la lectura persiste
    goto    tecla4     ; se presiono 4
    bsf     PORTB, 1
    bcf     PORTB, 2            ; activo solo la fila 3
    btfss   PORTB, C1           ; reviso si la lectura persiste
    goto    tecla7     ; se presiono 7
    bsf     PORTB, 2
    bcf     PORTB, 3            ; activo solo la fila 4
    btfss   PORTB, C1           ; reviso si la lectura persiste
    goto    teclaAst     ; se presiono *
    goto    fin_isr_keypad      ; caso descarte, finalizar la interrupcion

columna2
    bsf     PORTB, 0
    bsf     PORTB, 1
    bsf     PORTB, 2
    bsf     PORTB, 3
    bcf     PORTB, 0            ; activo solo la fila 1
    btfss   PORTB, C2           ; reviso si la lectura persiste
    goto    tecla2     ; se presiono 2
    bsf     PORTB, 0
    bcf     PORTB, 1            ; activo solo la fila 2
    btfss   PORTB, C2           ; reviso si la lectura persiste
    goto    tecla5     ; se presiono 5
    bsf     PORTB, 1
    bcf     PORTB, 2            ; activo solo la fila 3
    btfss   PORTB, C2           ; reviso si la lectura persiste
    goto    tecla8     ; se presiono 8
    bsf     PORTB, 2
    bcf     PORTB, 3            ; activo solo la fila 4
    btfss   PORTB, C2           ; reviso si la lectura persiste
    goto    tecla0     ; se presiono 0
    goto    fin_isr_keypad      ; caso descarte, finalizar la interrupcion

columna3
    bsf     PORTB, 0
    bsf     PORTB, 1
    bsf     PORTB, 2
    bsf     PORTB, 3
    bcf     PORTB, 0            ; activo solo la fila 1
    btfss   PORTB, C3           ; reviso si la lectura persiste
    goto    tecla3     ; se presiono 3
    bsf     PORTB, 0
    bcf     PORTB, 1            ; activo solo la fila 2
    btfss   PORTB, C3           ; reviso si la lectura persiste
    goto    tecla6     ; se presiono 6
    bsf     PORTB, 1
    bcf     PORTB, 2            ; activo solo la fila 3
    btfss   PORTB, C3           ; reviso si la lectura persiste
    goto    tecla9     ; se presiono 9
    bsf     PORTB, 2
    bcf     PORTB, 3            ; activo solo la fila 4
    btfss   PORTB, C3           ; reviso si la lectura persiste
    goto    teclaNum     ; se presiono #
    goto    fin_isr_keypad      ; caso descarte, finalizar la interrupcion

columna4
    bsf     PORTB, 0
    bsf     PORTB, 1
    bsf     PORTB, 2
    bsf     PORTB, 3
    bcf     PORTB, 0            ; activo solo la fila 1
    btfss   PORTB, C4           ; reviso si la lectura persiste
    goto    teclaA     ; se presiono A
    bsf     PORTB, 0
    bcf     PORTB, 1            ; activo solo la fila 2
    btfss   PORTB, C4           ; reviso si la lectura persiste
    goto    teclaB     ; se presiono B
    bsf     PORTB, 1
    bcf     PORTB, 2            ; activo solo la fila 3
    btfss   PORTB, C4           ; reviso si la lectura persiste
    goto    teclaC     ; se presiono C
    bsf     PORTB, 2
    bcf     PORTB, 3            ; activo solo la fila 4
    btfss   PORTB, C4           ; reviso si la lectura persiste
    goto    teclaD     ; se presiono D
    goto    fin_isr_keypad      ; caso descarte, finalizar la interrupcion

tecla1
    btfsc   estado_actual, NORMAL   ; verifico no estar en el estado base
    goto fin_isr_keypad             ; salgo si estoy

    movlw   d'1'
    movwf   keypad_value            ; guardo el valor en el buffer del keypad
    bsf     banderas, BUFFER_KEYPAD ; aviso que el buffer cambio
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
    btfss   estado_actual, NORMAL   ; me aseguro de estar en el modo base
    goto fin_isr_keypad             ; salgo si no estoy en modo base

    movlw   letraA                  ; guardo el valor en el buffer del keypad
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD ; aviso que el buffer cambio

    goto fin_isr_keypad

teclaB
    btfss   estado_actual, NORMAL   ; me aseguro de estar en el modo base
    goto fin_isr_keypad             ; salgo si no estoy en modo base

    movlw   letraB                  ; guardo el valor en el buffer del keypad
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD ; aviso que el buffer cambio

    goto fin_isr_keypad
teclaC
    btfss   estado_actual, NORMAL   ; me aseguro de estar en el modo base
    goto fin_isr_keypad             ; salgo si no estoy en modo base

    movlw   letraC                  ; guardo el valor en el buffer del keypad
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD ; aviso que el buffer cambio

    goto fin_isr_keypad
teclaD
    btfsc   estado_actual, NORMAL   ; verifico estar en algun estado de umbral
    goto    fin_isr_keypad          ; salgo si no lo estoy

    movlw   letraD                  ; guardo el valor en el buffer del keypad
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD ; aviso que el buffer cambio

    goto fin_isr_keypad

teclaAst
    btfss   estado_actual, NORMAL   ; verifico que estoy en el modo base
    goto fin_isr_keypad             ; si no estoy en estado base, salgo

    movlw   simboloAst                  ; guardo el valor en el buffer del keypad
    movwf   keypad_value
    bsf     banderas, BUFFER_KEYPAD ; aviso que el buffer cambio

    goto fin_isr_keypad
    
teclaNum
    goto fin_isr_keypad ; no implementado

fin_isr_keypad
    banksel PORTB
    movlw   b'00000000' ; devuelvo los puertos del puerto B a su configuracion inicial
    movwf   PORTB 
    banksel INTCON
    bcf  INTCON, RBIF   ; limpiar bandera de interrupcion por cambio de estado en puerto B
    goto fin_isr
; fin de la rutina de atencion de interrupcion del puerto B (keypad)    
; ************************************************************************
    END
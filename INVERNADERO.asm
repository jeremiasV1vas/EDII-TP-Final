list        p=16f887    ; list directive to define processor
    #include    <p16f887.inc>   ; processor specific variable definitions


; '__CONFIG' directive is used to embed configuration data within .asm file.
; The labels following the directive are located in the respective .inc file.
; See respective data sheet for additional information on configuration word.

    __CONFIG    _CONFIG1, _LVP_OFF & _FCMEN_ON & _IESO_OFF & _BOR_OFF & _CPD_OFF & _CP_OFF & _MCLRE_ON & _PWRTE_ON & _WDT_OFF & _INTRC_OSC_NOCLKOUT
    __CONFIG    _CONFIG2, _WRT_OFF & _BOR21V



;***** VARIABLE DEFINITIONS
#DEFINE TMR0_VALUE d'152'   ; valor de recarga para timer0, con prescaler 1:32 y Fosc=4MHz, para obtener una interrupcion cada 3.33ms
#DEFINE DEBOUNCE_VALUE d'5' ; cantidad de ciclos de timer0 para considerar un rebote como valido (5 ciclos = 16.65ms)
#DEFINE TECLADO_PRESIONADO d'0' ; estado del teclado: 0 = no presionado, 1 = presionado
#DEFINE HABILITAR_TECLADO d'1'  ; estado para habilitar la lectura del teclado en la rutina de atencion de interrupcion por cambio de estado en puerto B
#DEFINE C1 d'4'     ; definicion de pines del puerto B usados como columnas
#DEFINE C2 d'5'
#DEFINE C3 d'6'
#DEFINE C4 d'7'


cblock 0x20 ; inicio de bloque de variables en banco 0
    display_sel     ; variable para seleccionar el display a mostrar (2-0)
    display0_value  ; variable para almacenar el valor a mostrar en el display 0
    display1_value  ; variable para almacenar el valor a mostrar en el display 1
    display2_value  ; variable para almacenar el valor a mostrar en el display 2
    w_temp          ; variable used for context saving
    status_temp     ; variable used for context saving
    pclath_temp     ; variable used for context saving
    cont_tests1     ; variable para utilizada para contar ciclos de pruebas
    cont_tests2     ; variable para utilizada para contar ciclos de pruebas
    banderas    ; variable para almacenar banderas de estado
    ;             (bit 0: estado del teclado, bit 1: habilitar lectura del teclado)
    cont_debounce   ; variable para contar ciclos de debounce del teclado
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
    movlw   d'9'
    movwf   cont_tests1
    clrf    banderas        ; inicializo el registro de banderas
    bsf     banderas, HABILITAR_TECLADO ; arrancar con el teclado habilitado

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

    goto main_loop

; ************************************************************************
; Rutina de atencion de interrupcion de timer0
isr_timer0

    movlw   TMR0_VALUE  ; recargar timer0 para obtener una interrupcion cada 3.33ms
    movwf   TMR0

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
    ; la tecla fue soltada y pasó el tiempo de rebote. Habilitamos nueva lectura.
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
    clrf    PORTE       ; apagar todos los displays (evita ghosting)

    ; salto indexado para mostrar el display correspondiente
    banksel 0
    movf    display_sel,w   ; cargar display_sel en W para usarlo como indice
    addwf   PCL, f      ; selecciona el display
    goto    caso_display0
    goto    caso_display1
    goto    caso_display2

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

    ; verificar si fue evento de soltar (todas las columnas en HIGH)
    andlw   b'11110000'
    xorlw   b'11110000'
    btfsc   STATUS, Z
    goto    fin_isr_keypad          ; fue soltar, ignorar

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
    goto    no_implementado     ; se presiono 1
    bsf     PORTB, 0
    bcf     PORTB, 1            ; activo solo la fila 2
    btfss   PORTB, C1           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono 4
    bsf     PORTB, 1
    bcf     PORTB, 2            ; activo solo la fila 3
    btfss   PORTB, C1           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono 7
    bsf     PORTB, 2
    bcf     PORTB, 3            ; activo solo la fila 4
    btfss   PORTB, C1           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono *
    goto    fin_isr_keypad      ; caso descarte, finalizar la interrupcion

columna2
    bsf     PORTB, 0
    bsf     PORTB, 1
    bsf     PORTB, 2
    bsf     PORTB, 3
    bcf     PORTB, 0            ; activo solo la fila 1
    btfss   PORTB, C2           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono 2
    bsf     PORTB, 0
    bcf     PORTB, 1            ; activo solo la fila 2
    btfss   PORTB, C2           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono 5
    bsf     PORTB, 1
    bcf     PORTB, 2            ; activo solo la fila 3
    btfss   PORTB, C2           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono 8
    bsf     PORTB, 2
    bcf     PORTB, 3            ; activo solo la fila 4
    btfss   PORTB, C2           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono 0
    goto    fin_isr_keypad      ; caso descarte, finalizar la interrupcion

columna3
    bsf     PORTB, 0
    bsf     PORTB, 1
    bsf     PORTB, 2
    bsf     PORTB, 3
    bcf     PORTB, 0            ; activo solo la fila 1
    btfss   PORTB, C3           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono 3
    bsf     PORTB, 0
    bcf     PORTB, 1            ; activo solo la fila 2
    btfss   PORTB, C3           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono 6
    bsf     PORTB, 1
    bcf     PORTB, 2            ; activo solo la fila 3
    btfss   PORTB, C3           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono 9
    bsf     PORTB, 2
    bcf     PORTB, 3            ; activo solo la fila 4
    btfss   PORTB, C3           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono #
    goto    fin_isr_keypad      ; caso descarte, finalizar la interrupcion

columna4
    bsf     PORTB, 0
    bsf     PORTB, 1
    bsf     PORTB, 2
    bsf     PORTB, 3
    bcf     PORTB, 0            ; activo solo la fila 1
    btfss   PORTB, C4           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono A
    bsf     PORTB, 0
    bcf     PORTB, 1            ; activo solo la fila 2
    btfss   PORTB, C4           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono B
    bsf     PORTB, 1
    bcf     PORTB, 2            ; activo solo la fila 3
    btfss   PORTB, C4           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono C
    bsf     PORTB, 2
    bcf     PORTB, 3            ; activo solo la fila 4
    btfss   PORTB, C4           ; reviso si la lectura persiste
    goto    no_implementado     ; se presiono D
    goto    fin_isr_keypad      ; caso descarte, finalizar la interrupcion

no_implementado
    banksel 0
    movf    cont_tests1, w      ; se le agrega ', w' para que guarde en W
    call    tabla
    movwf   display0_value
    decfsz  cont_tests1,f
    goto    fin_isr_keypad
    movlw   d'9'
    movwf   cont_tests1

    goto    fin_isr_keypad

fin_isr_keypad
    banksel PORTB
    movlw   b'00000000' ; devuelvo los puertos del puerto B a su configuracion inicial
    movwf   PORTB 
    banksel INTCON
    bcf  INTCON, RBIF   ; limpiar bandera de interrupcion por cambio de estado en puerto B
    goto fin_isr
    END
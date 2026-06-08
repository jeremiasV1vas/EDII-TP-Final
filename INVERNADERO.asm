list		p=16f887	; list directive to define processor
	#include	<p16f887.inc>	; processor specific variable definitions


; '__CONFIG' directive is used to embed configuration data within .asm file.
; The labels following the directive are located in the respective .inc file.
; See respective data sheet for additional information on configuration word.

	__CONFIG    _CONFIG1, _LVP_OFF & _FCMEN_ON & _IESO_OFF & _BOR_OFF & _CPD_OFF & _CP_OFF & _MCLRE_ON & _PWRTE_ON & _WDT_OFF & _INTRC_OSC_NOCLKOUT
	__CONFIG    _CONFIG2, _WRT_OFF & _BOR21V



;***** VARIABLE DEFINITIONS
#DEFINE TMR0_VALUE d'152'	; valor de recarga para timer0, con prescaler 1:32 y Fosc=4MHz, para obtener una interrupcion cada 3.33ms


cblock 0x20	; inicio de bloque de variables en banco 0
	display_sel		; variable para seleccionar el display a mostrar (2-0)
	display0_value	; variable para almacenar el valor a mostrar en el display 0
	display1_value	; variable para almacenar el valor a mostrar en el display 1
	display2_value	; variable para almacenar el valor a mostrar en el display 2
	w_temp			; variable used for context saving
	status_temp		; variable used for context saving
	pclath_temp		; variable used for context saving
	cont_tests1		; variable para utilizada para contar ciclos de pruebas
	cont_tests2		; variable para utilizada para contar ciclos de pruebas
endc

;**********************************************************************
	ORG     0x000             ; processor reset vector

	nop
  	goto    main              ; go to beginning of program


	ORG     0x004             ; interrupt vector location

	movwf   w_temp            ; save off current W register contents
	movf	STATUS,w          ; move status register into W register
	movwf	status_temp       ; save off contents of STATUS register
	movf	PCLATH,w	  ; move pclath register into w register
	movwf	pclath_temp	  ; save off contents of PCLATH register

	btfsc	INTCON, TMR0IF	; verificar que la interrupcion fue por timer0
	goto isr_timer0		; si fue por timer0, ir a rutina de atencion de timer0

	btfsc	INTCON, RBIF	; verificar que la interrupcion fue por cambio de estado en puerto B
	goto isr_keypad		; si fue por cambio de estado en puerto B, ir a rutina de atencion de keypad

fin_isr
	movf	pclath_temp,w	  ; retrieve copy of PCLATH register
	movwf	PCLATH		  ; restore pre-isr PCLATH register contents
	movf    status_temp,w     ; retrieve copy of STATUS register
	movwf	STATUS            ; restore pre-isr STATUS register contents
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
	retlw   b'00111111'	; 0
	retlw   b'00000110'	; 1
	retlw   b'01011011'	; 2
	retlw   b'01001111'	; 3
	retlw   b'01100110'	; 4
	retlw   b'01101101'	; 5
	retlw   b'01111101'	; 6
	retlw   b'00000111'	; 7
	retlw   b'01111111'	; 8
	retlw   b'01101111'	; 9

ORG 0x040

main
	; inicializacion de variables
	banksel 0
	movlw   d'2'
	movwf   display_sel
	movlw	b'00111111'		; valor para mostrar el numero 0 en el display de 7 segmentos
	movwf	display0_value
	movlw	b'00111111'
	movwf	display1_value
	movlw	b'00111111'
	movwf	display2_value

	; configuracion de pines para usar el display de 7 segmentos

	banksel TRISD
	clrf    TRISD
	banksel PORTD
	clrf    PORTD

	; configuracion del puerto E para seleccionar el display a mostrar
	banksel ANSEL
	bcf	ANSEL,7
	bcf	ANSEL,6
	bcf	ANSEL,5
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
	movwf	OPTION_REG

	; cargar valor de recarga para timer0

	movlw	TMR0_VALUE	
	movwf	TMR0

	; configuracion de interrupciones para keypad 4x4
	banksel ANSELH
	clrf	ANSELH
	banksel TRISB
	movlw   b'00001111'	; configurar RB0-RB3 como entradas para el keypad
	movwf   TRISB
	banksel PORTB
	movlw   b'00000000'	
	movwf   PORTB
	banksel IOCB
	movlw   b'00001111'	; habilitar interrupciones por cambio de estado en RB0-RB3
	movwf   IOCB
	banksel WPUB
	movlw   b'00001111'	; habilitar pull-ups en RB0-RB3
	movwf   WPUB
	; habilitar interrupciones

	banksel INTCON
	clrf    INTCON	; limpiar registros de interrupciones
	bsf		INTCON, TMR0IE	; habilitar interrupcion de timer0
	bsf 	INTCON, RBIE	; habilitar interrupcion por cambio de estado en puerto B
	bsf		INTCON, GIE	; habilitar interrupciones globales

	goto main_loop


main_loop

	goto main_loop

; ************************************************************************
; Rutina de atencion de interrupcion de timer0
isr_timer0

	movlw	TMR0_VALUE	; recargar timer0 para obtener una interrupcion cada 3.33ms
	movwf	TMR0

	banksel PORTE
	clrf    PORTE		; apagar todos los displays (evita ghosting)

	; salto indexado para mostrar el display correspondiente

	banksel 0
	movf	display_sel,w	; cargar display_sel en W para usarlo como indice
	addwf   PCL, f		; selecciona el display
	goto	caso_display0
	goto	caso_display1
	goto	caso_display2

caso_display0
	movf	display0_value,w	; cargar el valor a mostrar en display0
	movwf   PORTD			; mostrar valor en display0
	bsf     PORTE, 0		; encender display0
	goto fin_multiplexado
caso_display1
	movf	display1_value,w	; cargar el valor a mostrar en display1
	movwf   PORTD			; mostrar valor en display1
	bsf     PORTE, 1		; encender display1
	goto fin_multiplexado
caso_display2
	movf	display2_value,w	; cargar el valor a mostrar en display2
	movwf   PORTD			; mostrar valor en display2
	bsf     PORTE, 2		; encender display2
	goto fin_multiplexado

fin_multiplexado
    ; avanzar display_sel ciclicamente: 2 -> 1 -> 0 -> 2
    movf    display_sel, w
    btfsc   STATUS, Z       ; si display_sel ya es 0, resetear
    goto    reset_display_sel
    decf    display_sel, f
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

	END
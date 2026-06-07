list		p=16f887	; list directive to define processor
	#include	<p16f887.inc>	; processor specific variable definitions


; '__CONFIG' directive is used to embed configuration data within .asm file.
; The labels following the directive are located in the respective .inc file.
; See respective data sheet for additional information on configuration word.

	__CONFIG    _CONFIG1, _LVP_OFF & _FCMEN_ON & _IESO_OFF & _BOR_OFF & _CPD_OFF & _CP_OFF & _MCLRE_ON & _PWRTE_ON & _WDT_OFF & _INTRC_OSC_NOCLKOUT
	__CONFIG    _CONFIG2, _WRT_OFF & _BOR21V



;***** VARIABLE DEFINITIONS
w_temp		EQU	0x7D		; variable used for context saving
status_temp	EQU	0x7E		; variable used for context saving
pclath_temp	EQU	0x7F		; variable used for context saving


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

; isr code can go here or be located as a call subroutine elsewhere

	movf	pclath_temp,w	  ; retrieve copy of PCLATH register
	movwf	PCLATH		  ; restore pre-isr PCLATH register contents
	movf    status_temp,w     ; retrieve copy of STATUS register
	movwf	STATUS            ; restore pre-isr STATUS register contents
	swapf   w_temp,f
	swapf   w_temp,w          ; restore pre-isr W register contents
	retfie


main

	; configuracion de registros necesarios para usar el puerto B por interrupciones
	; con un teclado matricial 4x4 conectado a RB0-RB3 y RB4-RB7 respectivamente
	banksel ANSEL
	movlw	0xFF		; configurar todos los pines del puerto B como digitales
	movwf	ANSEL

	banksel PORTB
	movlw   b'00000000'	; configurar el puerto B con valores iniciales de 0
	movwf   PORTB

	banksel TRISB
	movlw   b'00001111'	; configurar RB0-RB3 como entradas y RB4-RB7 como salidas
	movwf   TRISB

	banksel IOCB
	movlw   b'00001111'	; habilitar interrupciones por cambio de estado en RB0-RB3
	movwf   IOCB



	END
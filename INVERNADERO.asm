list        p=16f887        ; directiva para definir el procesador
    #include    <p16f887.inc>   ; definiciones de variables especificas del procesador


; directivas de configuracion del microcontrolador
    __CONFIG    _CONFIG1, _LVP_OFF & _FCMEN_ON & _IESO_OFF & _BOR_OFF & _CPD_OFF & _CP_OFF & _MCLRE_ON & _PWRTE_ON & _WDT_OFF & _INTRC_OSC_NOCLKOUT
    __CONFIG    _CONFIG2, _WRT_OFF & _BOR21V



; ***** DEFINICIONES CONSTANTES *****
#DEFINE TMR0_VALUE d'152'       ; valor de recarga para timer0 (prescaler 1:32, Fosc=4MHz -> interrupcion cada 3.33ms)
#DEFINE DEBOUNCE_VALUE d'15'    ; cantidad de ciclos de timer0 para validar un rebote (15 ciclos = ~50ms)
#DEFINE TICKS_MEDIO_SEG d'150'  ; cantidad de interrupciones de timer0 para alcanzar medio segundo (150 * 3.33ms)

; definicion de banderas del registro "banderas"
#DEFINE TECLADO_PRESIONADO d'0' ; estado del teclado: 0 = no presionado, 1 = presionado
#DEFINE HABILITAR_TECLADO d'1'  ; bandera para habilitar la lectura en la interrupcion del puerto B
#DEFINE BUFFER_KEYPAD d'2'      ; bandera para indicar que hay una tecla guardada lista para procesar
#DEFINE LEER_ADC d'3'           ; bandera para indicar que transcurrieron 500ms y se debe muestrear el adc

; definicion de pines del puerto B usados como columnas del teclado
#DEFINE C1 d'4'     
#DEFINE C2 d'5'
#DEFINE C3 d'6'
#DEFINE C4 d'7'

; definicion de los estados de la maquina de estados principal
#DEFINE NORMAL d'0'             ; estado base del programa (muestra valores y controla actuadores)
#DEFINE UMBRAL1 d'1'            ; estado para programar el primer digito (decenas) del umbral
#DEFINE UMBRAL2 d'2'            ; estado para programar el segundo digito (unidades) del umbral

; definicion de letras que el teclado matricial puede devolver
#DEFINE letraA b'00010000'
#DEFINE letraB b'00100000'
#DEFINE letraC b'00110000'
#DEFINE letraD b'01000000'
#DEFINE simboloAst b'01010000'
#DEFINE simboloNum b'01100000'

; definicion de sensores para la interfaz visual
#DEFINE SENSOR_TEMPERATURA d'0' ; constante para indicar que se muestra la temperatura
#DEFINE SENSOR_LUZ d'1'         ; constante para indicar que se muestra la luz


; ***** VARIABLES BANCO 0 *****
cblock 0x20                     ; inicio de bloque de variables en banco 0
    display_sel                 ; selector del display actual en el multiplexado (2, 1 o 0)
    display0_value              ; valor en formato 7 segmentos para el display izquierdo
    display1_value              ; valor en formato 7 segmentos para el display central
    display2_value              ; valor en formato 7 segmentos para el display derecho
    
    banderas                    ; registro que agrupa los bits de banderas de estado
    cont_debounce               ; contador decremental para el antirrebote del teclado
    cont_adc                    ; contador decremental para medir los 500ms del adc
    
    estado_actual               ; almacena el estado actual de la maquina (NORMAL, UMBRAL1, UMBRAL2)
    estado_temporal             ; almacena la tecla (A, B o C) para saber que umbral se esta modificando
    sensor_mostrado             ; almacena que sensor se esta visualizando en los displays
    keypad_value                ; buffer que guarda la ultima tecla presionada validada
    config_umbral_temp          ; variable para construir el umbral ingresado (nibble alto=decenas, bajo=unidades)
    
    ; variables de umbrales en formato BCD (ingreso del usuario)
    umbral_alto_temperatura     ; limite superior de temperatura
    umbral_bajo_temperatura     ; limite inferior de temperatura
    umbral_luz                  ; limite minimo de iluminacion
    
    ; variables de umbrales convertidos a formato binario puro (8 bits) para comparaciones matematicas
    umbral_alto_temp_8bit       ; limite superior en 8 bits
    umbral_bajo_temp_8bit       ; limite inferior en 8 bits
    umbral_luz_8bit             ; limite de luz en 8 bits
    
    ; variables de gestion del modulo ADC
    adc_canal_actual            ; bit 0 define el canal: 0 = leyendo AN0 (Temp), 1 = leyendo AN1 (Luz)
    adc_temperatura             ; lectura cruda del ADC para el sensor LM35
    adc_luz                     ; lectura cruda del ADC para la LDR
    
    ; variables temporales para rutinas de conversion matematica (BCD a 8 bits y Binario a BCD)
    unidades_tmp                ; guarda temporalmente las unidades extraidas
    decenas_tmp                 ; guarda temporalmente las decenas extraidas
    porcentaje_tmp              ; guarda el calculo de multiplicacion por 10
    umbral_8bit_tmp             ; guarda el valor devuelto por la tabla de conversion
    bcd_decenas                 ; resultado de decenas calculado desde binario para mostrar
    bcd_unidades                ; resultado de unidades calculado desde binario para mostrar
    math_temp                   ; registro de trabajo para bucles de resta sucesiva
    
    ; variables especificas para el calculo del porcentaje de luz (ADC * 100 / 256)
    acc_hi                      ; byte alto del acumulador de 16 bits (contiene la division por 256)
    acc_lo                      ; byte bajo del acumulador de 16 bits
    loop_cnt                    ; iterador para el bucle de multiplicacion por sumas sucesivas
    luz_porcentaje              ; guarda el porcentaje final 0-99 listo para mostrar y transmitir
endc

; ***** VARIABLES DE INTERRUPCION *****
cblock 0x70                     ; variables mapeadas en todos los bancos para guardado de contexto
    w_temp                      ; guarda el registro W al entrar a una interrupcion
    status_temp                 ; guarda el registro STATUS al entrar a una interrupcion
    pclath_temp                 ; guarda el registro PCLATH al entrar a una interrupcion
endc

; ************************************************************************
; VECTOR DE RESET
    ORG     0x000             

    nop
    goto    main                ; salta al inicio del programa principal


; ************************************************************************
; VECTOR DE INTERRUPCIONES
    ORG     0x004             

    ; guardado de contexto
    movwf   w_temp              ; guarda W actual
    movf    STATUS,w            
    movwf   status_temp         ; guarda STATUS actual
    movf    PCLATH,w      
    movwf   pclath_temp         ; guarda PCLATH actual

    ; despacho de interrupciones
    btfsc   INTCON, TMR0IF      ; verifica bandera de desbordamiento de Timer0
    goto    isr_timer0          ; si es 1, salta a la rutina de Timer0

    btfsc   INTCON, RBIF        ; verifica bandera de cambio de estado en puerto B
    goto    isr_keypad          ; si es 1, salta a la rutina del teclado

fin_isr
    ; restauracion de contexto
    movf    pclath_temp,w     
    movwf   PCLATH              ; restaura PCLATH
    movf    status_temp,w     
    movwf   STATUS              ; restaura STATUS
    swapf   w_temp,f
    swapf   w_temp,w            ; restaura W (se usa swap para no afectar STATUS)
    retfie                      ; retorna de la interrupcion habilitando GIE

; ************************************************************************
; TABLA DE CONVERSION: BCD a 7 SEGMENTOS
ORG 0x020

tabla
    ; retorna el mapa de bits para displays de catodo comun (1 enciende, 0 apaga)
    ; formato: dp g f e d c b a
    addwf   PCL, f              ; suma el valor de W al contador de programa para saltar
    retlw   b'00111111'         ; digito 0
    retlw   b'00000110'         ; digito 1
    retlw   b'01011011'         ; digito 2
    retlw   b'01001111'         ; digito 3
    retlw   b'01100110'         ; digito 4
    retlw   b'01101101'         ; digito 5
    retlw   b'01111101'         ; digito 6
    retlw   b'00000111'         ; digito 7
    retlw   b'01111111'         ; digito 8
    retlw   b'01101111'         ; digito 9

; ************************************************************************
; TABLA DE CONVERSION: PORCENTAJE A ADC DE 8 BITS
ORG 0x100
tabla_bcd_adc
    ; convierte un valor 0-99 ingresado por el usuario en su equivalente ADC (0-255)
    ; se aloja en 0x100 para garantizar que addwf PCL no desborde la pagina
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


; ************************************************************************
; INICIO DEL PROGRAMA PRINCIPAL
ORG 0x200

main
    ; --- configuracion del oscilador interno ---
    banksel OSCCON
    movlw   b'01100000'         ; configura oscilador interno a 4MHz
    movwf   OSCCON

    ; --- inicializacion de variables de sistema ---
    banksel 0
    movlw   d'2'
    movwf   display_sel         ; arranca apuntando al display derecho
    movlw   b'00111111'         ; carga el codigo del cero en los tres displays
    movwf   display0_value
    movwf   display1_value
    movwf   display2_value
    
    movlw   DEBOUNCE_VALUE
    movwf   cont_debounce       ; inicializa temporizador de antirrebote
    movlw   TICKS_MEDIO_SEG
    movwf   cont_adc            ; inicializa temporizador de lectura analoga
    
    clrf    banderas            ; limpia todos los bits de estado
    bsf     banderas, HABILITAR_TECLADO ; libera el teclado para primera lectura
    
    clrf    estado_actual
    bsf     estado_actual, NORMAL ; fuerza inicio en modo visualizacion normal
    clrf    estado_temporal
    clrf    sensor_mostrado
    bsf     sensor_mostrado, SENSOR_TEMPERATURA ; por defecto visualiza temperatura
    clrf    config_umbral_temp
    clrf    adc_canal_actual    ; inicializa para leer el canal AN0
    clrf    adc_temperatura
    clrf    adc_luz

    ; --- configuracion de puertos para displays (Hardware) ---
    banksel TRISD
    clrf    TRISD               ; Puerto D como salidas completas (segmentos)
    banksel PORTD
    clrf    PORTD               ; limpia salidas
    banksel ANSEL
    bcf     ANSEL,7             ; asegura que pines del puerto E sean digitales
    bcf     ANSEL,6
    bcf     ANSEL,5
    banksel TRISE
    clrf    TRISE               ; Puerto E como salidas (transistores multiplexado)
    banksel PORTE
    clrf    PORTE               ; apaga displays

    ; --- configuracion de puerto C (Actuadores y Comunicacion UART) ---
    banksel TRISC
    movlw   b'10000000'         ; RC7 (RX) entrada, RC6 (TX) y RC0-RC2 (cargas) salidas
    movwf   TRISC
    banksel PORTC
    clrf    PORTC               ; apagar todos los actuadores inicialmente por seguridad

    ; --- configuracion modulo USART (HC-05 a 9600 baudios) ---
    banksel TXSTA
    movlw   b'00100100'         ; modo asincrono, TX habilitado, alta velocidad (BRGH=1)
    movwf   TXSTA
    banksel RCSTA
    movlw   b'10000000'         ; habilita el puerto serial (SPEN=1)
    movwf   RCSTA
    banksel SPBRG
    movlw   d'25'               ; formula: (4MHz / (16 * 9600)) - 1 = 25
    movwf   SPBRG

    ; --- configuracion conversor analogo-digital (ADC) ---
    banksel ADCON1
    movlw   0x00                ; justificacion a la izquierda (solo ADRESH), Vref = VDD y VSS
    movwf   ADCON1
    banksel TRISA
    bsf     TRISA, 0            ; configura RA0 como entrada (LM35)
    bsf     TRISA, 1            ; configura RA1 como entrada (LDR)
    banksel ANSEL
    movlw   b'00000011'         ; activa funciones analogas para AN0 y AN1
    movwf   ANSEL
    banksel ANSELH
    clrf    ANSELH              ; el resto de pines analogos se fuerzan a digital
    banksel ADCON0
    movlw   b'01000001'         ; Fosc/8, selecciona canal AN0, modulo ADC encendido (ADON=1)
    movwf   ADCON0

    ; --- configuracion timer0 (base de tiempo del multiplexado) ---
    banksel OPTION_REG
    movlw   b'01000100'         ; asigna prescaler 1:32 al TMR0, reloj interno
    movwf   OPTION_REG
    banksel TMR0
    movlw   TMR0_VALUE          ; carga offset para contar exactos 3.33ms
    movwf   TMR0

    ; --- configuracion teclado matricial (Interrupcion IOC) ---
    banksel TRISB
    movlw   b'11110000'         ; RB4-RB7 como entradas (filas), RB0-RB3 como salidas (columnas)
    movwf   TRISB
    banksel PORTB
    clrf    PORTB               ; las salidas a cero activan la busqueda de columnas
    banksel IOCB
    movlw   b'11110000'         ; habilita la interrupcion por cambio en pines RB4-RB7
    movwf   IOCB
    banksel WPUB
    movlw   b'11110000'         ; activa resistencias pull-up internas en entradas
    movwf   WPUB

    ; --- habilitacion general de interrupciones ---
    banksel INTCON
    clrf    INTCON              ; limpia posibles banderas atoradas
    bsf     INTCON, TMR0IE      ; habilita interrupcion de Timer0
    bsf     INTCON, RBIE        ; habilita interrupcion del Puerto B
    bsf     INTCON, GIE         ; habilita el manejador global de interrupciones

    goto main_loop              ; salta al bucle infinito


; ************************************************************************
; BUCLE PRINCIPAL (MAQUINA DE ESTADOS)
main_loop
    ; --- subrutina de muestreo ADC no bloqueante ---
    btfss   banderas, LEER_ADC  ; verifica si timer0 conto 500ms
    goto    revisar_teclado     ; si no, saltea la lectura
    
    bcf     banderas, LEER_ADC  ; baja la bandera
    bsf     ADCON0, GO          ; dispara la conversion del canal actual
esperar_adc
    btfsc   ADCON0, GO          ; el bit GO baja cuando la conversion termina
    goto    esperar_adc         ; espera activa de escasos microsegundos
    
    movf    ADRESH, w           ; guarda el resultado de 8 bits en W
    btfsc   adc_canal_actual, 0 ; evalua que canal acaba de leerse
    goto    guardar_an1

guardar_an0
    movwf   adc_temperatura     ; guarda el valor correspondiente al LM35
    bsf     adc_canal_actual, 0 ; invierte la bandera para indicar proxima lectura en canal 1
    movlw   b'01000101'         ; reconfigura ADCON0: mantiene on, selecciona AN1
    movwf   ADCON0
    goto    revisar_teclado     ; no hace logica hasta leer ambos canales

guardar_an1
    movwf   adc_luz             ; guarda el valor correspondiente a la LDR
    bcf     adc_canal_actual, 0 ; retorna bandera a canal 0
    movlw   b'01000001'         ; reconfigura ADCON0: mantiene on, selecciona AN0
    movwf   ADCON0
    
    ; --- analisis logico de la muestra completada ---
    btfss   estado_actual, NORMAL   ; impide controlar y enviar datos si el usuario esta configurando
    goto    revisar_teclado         
    
    call    control_actuadores      ; actualiza salidas de potencia segun umbrales
    call    enviar_datos_bluetooth  ; emite el paquete "TxxLxx\n" por puerto serial

revisar_teclado
    ; --- gestion del buffer de pulsaciones ---
    btfss   banderas, BUFFER_KEYPAD ; si hay un dato fresco en keypad_value = 1
    goto    actualizar_pantalla     ; si no hay tecla, procede a refrescar datos visuales
    bcf     banderas, BUFFER_KEYPAD ; acusa recibo bajando la bandera

    ; --- despachador de la maquina de estados principal ---
    btfsc   estado_actual, NORMAL
    goto    loop_estado_normal      ; si esta en NORMAL analiza ingresos (A, B, C, *)
    btfsc   estado_actual, UMBRAL1
    goto    loop_estado_umbral1     ; si esta en ingreso de decenas
    goto    loop_estado_umbral2     ; si esta en ingreso de unidades

actualizar_pantalla
    ; evita sobrescribir las letras de configuracion ("U - -") si el usuario navega el menu
    btfss   estado_actual, NORMAL
    goto    main_loop

    ; decide si envia temperatura o luz a la subrutina de multiplexado
    btfsc   sensor_mostrado, SENSOR_TEMPERATURA
    goto    mostrar_temp
    goto    mostrar_luz

mostrar_temp
    ; formula LM35: cada bit del ADC son 19.53mV. LM35 da 10mV/C. 
    ; temp en C = ADC * 1.95. Se aproxima a multiplicacion por 2 mediante rotacion
    bcf     STATUS, C
    rlf     adc_temperatura, w
    
    ; --- filtro antidesborde de tabla para temperatura ---
    movwf   math_temp       
    sublw   d'99'               ; 99 - W
    btfss   STATUS, C           ; si hay borrow, W era mayor a 99
    goto    limitar_t
    movf    math_temp, w        ; si estaba en rango, se recupera el valor validado
    goto    bcd_t
limitar_t
    movlw   d'99'               ; clava el maximo visual en 99
bcd_t:
    call    bin_a_bcd           ; descompone en decenas y unidades

    movlw   b'01111000'         ; codigo manual 7 segmentos para letra 't'
    movwf   display0_value
    movf    bcd_decenas, w      
    call    tabla               ; solicita codificacion visual de decenas
    movwf   display1_value
    movf    bcd_unidades, w
    call    tabla               ; solicita codificacion visual de unidades
    movwf   display2_value
    goto    main_loop           ; cierra ciclo

mostrar_luz
    call    calcular_porcentaje_luz ; procesa la lectura cruda en escala 0-99
    
    ; --- filtro antidesborde de tabla para luminosidad ---
    movf    luz_porcentaje, w
    movwf   math_temp
    sublw   d'99'
    btfss   STATUS, C
    goto    limitar_l
    movf    math_temp, w
    goto    bcd_l
limitar_l
    movlw   d'99'               ; maximo visual en 99
bcd_l:
    call    bin_a_bcd

    movlw   b'00111000'         ; codigo manual 7 segmentos para letra 'L'
    movwf   display0_value
    movf    bcd_decenas, w
    call    tabla
    movwf   display1_value
    movf    bcd_unidades, w
    call    tabla
    movwf   display2_value
    goto    main_loop           ; cierra ciclo

; -------------------------------------------------------
; BLOQUE DE ESTADO: NORMAL (Procesamiento de Comandos)
loop_estado_normal
    ; compara la tecla presionada con las opciones validas del menu
    movf    keypad_value, w
    xorlw   letraA
    btfsc   STATUS, Z
    goto    loop_normal_letraA  ; invoca configuracion de umbral superior de temp

    movf    keypad_value, w
    xorlw   letraB
    btfsc   STATUS, Z
    goto    loop_normal_letraB  ; invoca configuracion de umbral inferior de temp

    movf    keypad_value, w
    xorlw   letraC
    btfsc   STATUS, Z
    goto    loop_normal_letraC  ; invoca configuracion de umbral de luz

    goto    loop_normal_ast     ; por descarte asume asterisco (cambio de visualizacion)

loop_normal_letraA
    clrf    estado_actual
    bsf     estado_actual, UMBRAL1  ; transiciona al estado ingreso primer digito
    movf    keypad_value, w
    movwf   estado_temporal         ; guarda 'A' para saber donde guardar el resultado final
    movlw   b'00111110'                 
    movwf   display0_value          ; muestra 'U'
    movlw   b'01000000'                 
    movwf   display1_value          ; muestra '-'
    movwf   display2_value          ; muestra '-'
    clrf    keypad_value            ; limpia buffer previniendo doble ingreso
    clrf    PORTC                   ; desactiva actuadores por seguridad mientras se configura
    goto    main_loop

loop_normal_letraB
    clrf    estado_actual
    bsf     estado_actual, UMBRAL1
    movf    keypad_value, w
    movwf   estado_temporal         ; guarda 'B'
    movlw   b'00111110'                 
    movwf   display0_value
    movlw   b'01000000'                 
    movwf   display1_value
    movwf   display2_value
    clrf    keypad_value
    clrf    PORTC
    goto    main_loop

loop_normal_letraC
    clrf    estado_actual
    bsf     estado_actual, UMBRAL1
    movf    keypad_value, w
    movwf   estado_temporal         ; guarda 'C'
    movlw   b'00111110'                 
    movwf   display0_value
    movlw   b'01000000'                 
    movwf   display1_value
    movwf   display2_value
    clrf    keypad_value
    clrf    PORTC
    goto    main_loop

loop_normal_ast
    ; si presiona asterisco, intercala la variable logica de visualizacion
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
; BLOQUE DE ESTADO: UMBRAL1 (Ingreso de Decenas)
loop_estado_umbral1
    movf    keypad_value, w
    xorlw   letraD
    btfsc   STATUS, Z
    goto    loop_umbral1_cancelar   ; tecla D cancela la operacion actual

    ; validacion numerica: descarta letras accidentales
    movf    keypad_value, w
    sublw   d'9'
    btfss   STATUS, C               ; si C=0, numero ingresado es mayor a 9
    goto    main_loop       

    ; empaqueta el primer digito desplazandolo al nibble alto
    movf    keypad_value, w
    movwf   config_umbral_temp      ; guarda ej. 0x05
    swapf   config_umbral_temp, f   ; transforma a 0x50 (5 decenas)
    
    ; dibuja el primer numero en el display central
    movf    keypad_value, w
    call    tabla
    movwf   display1_value
    movlw   b'01000000'                 
    movwf   display2_value          ; mantiene guion a la derecha
    
    clrf    estado_actual
    bsf     estado_actual, UMBRAL2  ; transiciona a espera de unidades
    clrf    keypad_value
    goto    main_loop

loop_umbral1_cancelar
    clrf    estado_actual
    bsf     estado_actual, NORMAL   ; aborta y retorna al estado base
    clrf    config_umbral_temp      ; limpia basura
    clrf    keypad_value
    goto    main_loop

; -------------------------------------------------------
; BLOQUE DE ESTADO: UMBRAL2 (Ingreso de Unidades)
loop_estado_umbral2
    movf    keypad_value, w
    xorlw   letraD
    btfsc   STATUS, Z
    goto    loop_umbral2_volver     ; tecla D funciona como borrado retroactivo (Backspace)

    ; validacion numerica
    movf    keypad_value, w
    sublw   d'9'
    btfss   STATUS, C
    goto    main_loop       

    ; fusion del digito actual con el nibble guardado
    movf    keypad_value, w         ; ej. nuevo valor 0x03
    iorwf   config_umbral_temp, f   ; OR logico: 0x50 OR 0x03 = 0x53 (Valor BCD final)
    
    ; muestra el resultado en el display de unidades
    movf    keypad_value, w
    call    tabla
    movwf   display2_value

    ; transforma el formato visual a un byte de maquina para su uso interno
    call    convertir_bcd_8bit

    ; logica de enrutamiento basada en la variable temporal guardada inicialmente
    movf    estado_temporal, w
    xorlw   letraA
    btfsc   STATUS, Z
    goto    loop_umbral2_guardar_alto

    movf    estado_temporal, w
    xorlw   letraB
    btfsc   STATUS, Z
    goto    loop_umbral2_guardar_bajo

    goto    loop_umbral2_guardar_luz ; por descarte era configuracion de luz

loop_umbral2_guardar_alto
    movf    config_umbral_temp, w
    movwf   umbral_alto_temperatura
    movf    umbral_8bit_tmp, w
    movwf   umbral_alto_temp_8bit   ; persiste el valor ADC traducido para el comparador
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
    clrf    config_umbral_temp      ; limpieza total de buffers temporales
    clrf    estado_actual
    bsf     estado_actual, NORMAL   ; cierre exitoso, retorno a visualizacion
    clrf    keypad_value
    goto    main_loop

loop_umbral2_volver
    clrf    config_umbral_temp
    clrf    estado_actual
    bsf     estado_actual, UMBRAL1  ; retrocede de estado
    movlw   b'01000000'             ; vuelve a colocar los guiones de espera
    movwf   display1_value
    movwf   display2_value
    clrf    keypad_value
    goto    main_loop


; ************************************************************************
; SUBRUTINAS DE LOGICA DE SISTEMA
; ************************************************************************

; Subrutina: Control de Actuadores
; Compara lecturas y aplica logica positiva sobre los BJT del puerto C
control_actuadores
    ; evaluacion limite superior: verifica si hay exceso de calor
    movf    umbral_alto_temp_8bit, w
    subwf   adc_temperatura, w
    btfsc   STATUS, C               ; si C=1, ADC supero el Umbral Alto
    goto    encender_ventilador
    
    ; evaluacion limite inferior: verifica si falta calor
    movf    umbral_bajo_temp_8bit, w
    subwf   adc_temperatura, w
    btfss   STATUS, C               ; si C=0, ADC descendio bajo el Umbral Bajo
    goto    encender_calefactor
    
    ; si no se cumplen las condiciones extremas (rango seguro):
    bcf     PORTC, 0                ; apaga transistor del ventilador
    bcf     PORTC, 1                ; apaga transistor de resistencia termica
    goto    control_iluminacion
    
encender_ventilador
    bsf     PORTC, 0                ; satura transistor RC0
    bcf     PORTC, 1                ; asegura apagado del calefactor por seguridad (exclusividad logica)
    goto    control_iluminacion

encender_calefactor
    bcf     PORTC, 0                ; asegura apagado del ventilador
    bsf     PORTC, 1                ; satura transistor RC1

control_iluminacion
    ; evalua escasez de luz
    movf    umbral_luz_8bit, w
    subwf   adc_luz, w
    btfss   STATUS, C               ; si C=0, luminosidad externa es insuficiente
    goto    encender_leds
    
    bcf     PORTC, 2                ; luminosidad suficiente, apaga tira LED
    return
    
encender_leds
    bsf     PORTC, 2                ; satura transistor RC2 activando modulo LED
    return


; Subrutina: Transmision de Datos Bluetooth
; Empaqueta lecturas en formato de cadena TXXLXX\n para el software MIT App Inventor
enviar_datos_bluetooth
    ; envio de prefijo de temperatura
    movlw   'T'
    call    tx_byte
    
    ; recodifica la temperatura cruda a BCD para su impresion en consola
    bcf     STATUS, C
    rlf     adc_temperatura, w
    movwf   math_temp
    sublw   d'99'
    btfss   STATUS, C
    goto    bt_limitar_t
    movf    math_temp, w
    goto    bt_bcd_t
bt_limitar_t
    movlw   d'99'
bt_bcd_t:
    call    bin_a_bcd
    
    ; convierte decenas y unidades calculadas a caracteres ASCII
    movf    bcd_decenas, w
    addlw   '0'                     ; el offset ASCII del caracter '0' es 0x30
    call    tx_byte
    movf    bcd_unidades, w
    addlw   '0'                     
    call    tx_byte

    ; envio de prefijo de luz
    movlw   'L'
    call    tx_byte
    
    ; recalcula la luz y la codifica a caracteres
    call    calcular_porcentaje_luz
    movf    luz_porcentaje, w
    movwf   math_temp
    sublw   d'99'
    btfss   STATUS, C
    goto    bt_limitar_l
    movf    math_temp, w
    goto    bt_bcd_l
bt_limitar_l
    movlw   d'99'
bt_bcd_l:
    call    bin_a_bcd
    
    ; envia porcion numerica de luz
    movf    bcd_decenas, w
    addlw   '0'             
    call    tx_byte
    movf    bcd_unidades, w
    addlw   '0'             
    call    tx_byte
    
    ; envio de secuencia de fin de linea (Delimitador LF)
    movlw   0x0A
    call    tx_byte
    return

tx_byte
    ; control de hardware UART para transmision byte a byte
    btfss   PIR1, 4                 ; el bit TXIF (4) avisa si el buffer de hardware se vacio
    goto    tx_byte                 ; espera bloqueante corta
    movwf   TXREG                   ; carga byte a transmitir en la cola serial
    return


; ************************************************************************
; SUBRUTINAS MATEMATICAS Y DE CONVERSION
; ************************************************************************

; Subrutina: Calcular porcentaje de luz (Valor_ADC * 100 / 256)
calcular_porcentaje_luz
    clrf    acc_hi
    clrf    acc_lo
    movf    adc_luz, w
    btfsc   STATUS, Z               ; si ADC dio 0 absoluto, evita calculos
    goto    fin_adc_porcentaje      
    movwf   loop_cnt                ; usa el valor leido como cantidad de iteraciones (Multiplicacion)
suma_100
    movlw   d'100'
    addwf   acc_lo, f               ; acumula 100 en byte bajo
    btfsc   STATUS, C               
    incf    acc_hi, f               ; transfiere acarreo al byte alto
    decfsz  loop_cnt, f             
    goto    suma_100
fin_adc_porcentaje
    movf    acc_hi, w               ; el byte alto contiene intrinsecamente la division por 256
    movwf   luz_porcentaje
    return

; Subrutina: Binario puro a formato BCD (Limites 0-99)
bin_a_bcd
    movwf   math_temp               ; adquiere parametro de entrada             
    clrf    bcd_decenas
restar_10
    movlw   d'10'
    subwf   math_temp, w            ; resta diez de manera ciclica
    btfss   STATUS, C               ; corta cuando el resultado provoca acarreo negativo
    goto    fin_bcd
    movwf   math_temp               ; aplica la resta al valor oficial            
    incf    bcd_decenas, f          ; contabiliza una decena exitosa        
    goto    restar_10
fin_bcd
    movf    math_temp, w            ; el saldo de la division son las unidades residuales
    movwf   bcd_unidades
    return

; Subrutina: Formato empaquetado BCD a binario de 8 bits
convertir_bcd_8bit
    ; aisla decenas y las ubica en bits LSB
    movf    config_umbral_temp, w
    andlw   0xF0
    movwf   decenas_tmp
    swapf   decenas_tmp, f
    ; aisla unidades intactas
    movf    config_umbral_temp, w
    andlw   0x0F
    movwf   unidades_tmp
    clrf    porcentaje_tmp
    
    ; reordena a valor lineal (Decenas * 10)
    movf    decenas_tmp, w
    btfsc   STATUS, Z
    goto    sumar_unidades_bcd
bucle_por_diez
    movlw   d'10'
    addwf   porcentaje_tmp, f
    decfsz  decenas_tmp, f
    goto    bucle_por_diez
sumar_unidades_bcd
    ; (Decenas * 10) + Unidades = Porcentaje Entero
    movf    unidades_tmp, w
    addwf   porcentaje_tmp, f
    
    ; carga valor en puntero PCLATH y mapea con tabla inversa
    movlw   HIGH(tabla_bcd_adc)     ; garantiza correcta paginacion de tabla extensa
    movwf   PCLATH
    movf    porcentaje_tmp, w
    call    tabla_bcd_adc
    clrf    PCLATH                  ; vital: restablece pagina base
    movwf   umbral_8bit_tmp         ; devuelve el calculo listo para el comparador
    return

; ************************************************************************
; GESTION DE INTERRUPCIONES
; ************************************************************************

; Rutina de Timer0 (Ejecucion periodica cada 3.33 milisegundos)
isr_timer0
    banksel TMR0
    movlw   TMR0_VALUE              ; recarga modulo de timer interno
    movwf   TMR0
    banksel 0
    
    ; gestion de reloj auxiliar lento (500ms) para lectura de sensores
    decfsz  cont_adc, f
    goto    subrutina_debounce  
    
    movlw   TICKS_MEDIO_SEG         ; al llegar a cero, reinicia contador macro
    movwf   cont_adc
    bsf     banderas, LEER_ADC      ; autoriza main_loop a usar el bus del ADC

subrutina_debounce
    ; maquina de estados de filtrado de ruido para teclado
    btfss   banderas, TECLADO_PRESIONADO
    goto    subrutina_multiplexado  ; si no hay evento, avanza directo a dibujo

    decfsz  cont_debounce, f
    goto    subrutina_multiplexado  ; si esta procesando, consume ticks muertos

    ; validacion de tecla sostenida
    banksel PORTB
    movf    PORTB, w
    banksel 0
    andlw   b'11110000'
    xorlw   b'11110000'
    btfss   STATUS, Z
    goto    teclado_aun_presionado

teclado_liberado
    ; libera hardware aceptando nueva digitacion
    movlw   DEBOUNCE_VALUE
    movwf   cont_debounce
    bsf     banderas, HABILITAR_TECLADO
    bcf     banderas, TECLADO_PRESIONADO
    goto    subrutina_multiplexado

teclado_aun_presionado
    ; dedo en la tecla, reengancha cuenta
    movlw   DEBOUNCE_VALUE
    movwf   cont_debounce
    goto    subrutina_multiplexado

subrutina_multiplexado
    ; algoritmo de persistencia visual de pantallas (POV)
    banksel PORTE
    clrf    PORTE                   ; limpia el canal previniendo ecos visuales (ghosting)

    banksel display_sel
    movf    display_sel, w
    btfsc   STATUS, Z
    goto    caso_display0           ; enruta hardware segun la fase del ciclo
    
    xorlw   d'1'
    btfsc   STATUS, Z
    goto    caso_display1
    
    goto    caso_display2

caso_display0
    movf    display0_value,w
    movwf   PORTD                   ; manda mapa de bits de variable izquierda a los leds
    bsf     PORTE, 0                ; enciende transistor habilitador izquierdo
    goto fin_multiplexado
caso_display1
    movf    display1_value,w
    movwf   PORTD
    bsf     PORTE, 1                ; habilita medio
    goto fin_multiplexado
caso_display2
    movf    display2_value,w
    movwf   PORTD
    bsf     PORTE, 2                ; habilita derecho
    goto fin_multiplexado

fin_multiplexado
    ; logica de rotacion de anillo 2->1->0->2...
    movf    display_sel, w
    btfsc   STATUS, Z
    goto    reset_display_sel
    decf    display_sel, f
    goto    fin_actualizacion

reset_display_sel
    movlw   d'2'
    movwf   display_sel

fin_actualizacion
    bcf     INTCON, TMR0IF          ; fundamental: baja bandera para prevenir recursion
    goto    fin_isr


; Rutina de Teclado Matricial (Interrupcion IOCB - Interrupcion al cambio)
isr_keypad
    ; el micro manda llamar esta rutina si cualquier pin RB4 a RB7 sufre cambio
    banksel PORTB
    movf    PORTB, w                ; lectura dummy obligatoria para liberar desajuste de lectura (mismatch)

    btfss   banderas, HABILITAR_TECLADO
    goto    fin_isr_keypad          ; si hay una operacion activa, descarta rebotes analogos
    
    bsf     banderas, TECLADO_PRESIONADO ; traba la puerta activando contador debounce
    goto    leer_teclado

leer_teclado
    bcf     banderas, HABILITAR_TECLADO ; apaga permisos de lectura
    banksel PORTB
    ; ubica sobre que columna recayo el evento
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
    ; aisla fila inyectando cero logico escalonado
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

; rutinas de asignacion de buffer final
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
    ; repone la linea base de las salidas para habilitar nueva busqueda
    banksel PORTB
    movlw   b'00000000'
    movwf   PORTB 
    banksel INTCON
    bcf  INTCON, RBIF               ; asegura bajar bandera para salir limpio
    goto fin_isr
    END
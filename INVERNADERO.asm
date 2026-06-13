list        p=16f887        ; directiva para definir el procesador
    #include    <p16f887.inc>   ; definiciones de registros y variables especificas del microcontrolador


; directivas de configuracion (fuses)
    __CONFIG    _CONFIG1, _LVP_OFF & _FCMEN_ON & _IESO_OFF & _BOR_OFF & _CPD_OFF & _CP_OFF & _MCLRE_ON & _PWRTE_ON & _WDT_OFF & _INTRC_OSC_NOCLKOUT
    __CONFIG    _CONFIG2, _WRT_OFF & _BOR21V



; ***** DEFINICIONES CONSTANTES *****
#DEFINE TMR0_VALUE d'152'       ; valor de recarga para timer0 (prescaler 1:32, Fosc=4MHz -> interrupcion cada ~3.33ms)
#DEFINE DEBOUNCE_VALUE d'15'    ; cantidad de ciclos de timer0 para validar un rebote mecanico (15 ciclos = ~50ms)
#DEFINE TICKS_MEDIO_SEG d'150'  ; cantidad de interrupciones de timer0 para alcanzar medio segundo (150 * 3.33ms)

; definicion de bits para el registro de banderas de control
#DEFINE TECLADO_PRESIONADO d'0' ; estado logico del teclado: 0 = en reposo, 1 = tecla en validacion
#DEFINE HABILITAR_TECLADO d'1'  ; bandera para habilitar la captura en la interrupcion del puerto B
#DEFINE BUFFER_KEYPAD d'2'      ; bandera para notificar al flujo principal que existe una tecla pendiente
#DEFINE LEER_ADC d'3'           ; bandera temporizada para disparar el muestreo de los sensores analogicos

; asignacion de pines del puerto B para el escaneo de columnas del teclado matricial
#DEFINE C1 d'4'     
#DEFINE C2 d'5'
#DEFINE C3 d'6'
#DEFINE C4 d'7'

; definicion de estados para la maquina de estados principal (interfaz de usuario)
#DEFINE NORMAL d'0'             ; estado operativo base: visualizacion de sensores y control de cargas
#DEFINE UMBRAL1 d'1'            ; estado de configuracion: captura de la decena del umbral
#DEFINE UMBRAL2 d'2'            ; estado de configuracion: captura de la unidad del umbral

; decodificacion de los comandos literales del teclado matricial
#DEFINE letraA b'00010000'
#DEFINE letraB b'00100000'
#DEFINE letraC b'00110000'
#DEFINE letraD b'01000000'
#DEFINE simboloAst b'01010000'
#DEFINE simboloNum b'01100000'

; selectores de visualizacion para los displays de 7 segmentos
#DEFINE SENSOR_TEMPERATURA d'0' 
#DEFINE SENSOR_LUZ d'1'         


; ***** VARIABLES BANCO 0 *****
cblock 0x20                     
    display_sel                 ; selector del canal activo en la rutina de multiplexado (2, 1 o 0)
    display0_value              ; registro de mapa de bits (7 segmentos) para el display izquierdo
    display1_value              ; registro de mapa de bits para el display central
    display2_value              ; registro de mapa de bits para el display derecho
    
    banderas                    ; registro aglutinador de banderas logicas booleanas
    cont_debounce               ; contador decremental del filtro antirrebote
    cont_adc                    ; contador decremental para base de tiempo de muestreo (500ms)
    
    estado_actual               ; puntero del estado activo en la maquina principal
    estado_temporal             ; guarda el comando inicial (A, B, C) para enrutar el guardado del umbral
    sensor_mostrado             ; define el parametro fisico visualizado en tiempo real
    keypad_value                ; buffer de transferencia para la tecla presionada
    config_umbral_temp          ; registro de construccion numerica (nibble alto=decenas, bajo=unidades)
    
    ; variables operativas de parametros del usuario
    umbral_alto_temperatura     ; limite de activacion de refrigeracion (formato BCD)
    umbral_bajo_temperatura     ; limite de activacion de calefaccion (formato BCD)
    umbral_luz                  ; limite inferior de iluminacion ambiental (formato BCD)
    
    ; variables de calculo interno estandarizadas a magnitud numerica de 8 bits
    umbral_alto_temp_8bit       ; limite termico superior lineal
    umbral_bajo_temp_8bit       ; limite termico inferior lineal
    umbral_luz_8bit             ; limite luminico convertido al dominio de resolucion del ADC (0-255)
    
    ; gestores del conversor analogo-digital
    adc_canal_actual            ; flag de conmutacion: 0 = canal AN0 (Temp), 1 = canal AN1 (Luz)
    adc_temperatura             ; byte resultante de la conversion de tension termica
    adc_luz                     ; byte resultante de la conversion del divisor resistivo optico
    
    ; registros temporales para algoritmos matematicos y de conversion
    unidades_tmp                
    decenas_tmp                 
    porcentaje_tmp              
    umbral_8bit_tmp             
    bcd_decenas                 ; decena procesada para inyeccion al display
    bcd_unidades                ; unidad procesada para inyeccion al display
    math_temp                   ; registro pivot para operaciones aritmeticas
    
    ; registros especificos para escalado de luminosidad porcentual
    acc_hi                      ; byte mas significativo del acumulador
    acc_lo                      ; byte menos significativo del acumulador
    loop_cnt                    ; iterador de algoritmo de multiplicacion
    luz_porcentaje              ; magnitud luminica escalada a rango 0-99
endc

; ***** VARIABLES DE CONTEXTO (INTERRUPCIONES) *****
cblock 0x70                     ; memoria no bancada para accesibilidad global
    w_temp                      ; resguardo del registro de trabajo
    status_temp                 ; resguardo de banderas de la ALU
    pclath_temp                 ; resguardo del puntero de pagina de codigo
endc

; ************************************************************************
; VECTOR DE RESET
    ORG     0x000             

    nop
    goto    main                


; ************************************************************************
; VECTOR DE INTERRUPCIONES
    ORG     0x004             

    ; resguardo del estado maquina (Context Saving)
    movwf   w_temp              
    movf    STATUS,w            
    movwf   status_temp         
    movf    PCLATH,w      
    movwf   pclath_temp         

    ; enrutamiento de fuentes de interrupcion
    btfsc   INTCON, TMR0IF      ; polling sobre bandera de desbordamiento de Timer0
    goto    isr_timer0          

    btfsc   INTCON, RBIF        ; polling sobre bandera de cambio de flanco en Puerto B
    goto    isr_keypad          

fin_isr
    ; restauracion de la maquina
    movf    pclath_temp,w     
    movwf   PCLATH              
    movf    status_temp,w     
    movwf   STATUS              
    swapf   w_temp,f
    swapf   w_temp,w            
    retfie                      ; retorno seguro con rehabilitacion de interrupciones

; ************************************************************************
; MEMORIA DE DATOS CONSTANTES (ROM)
ORG 0x020

tabla
    ; decodificador BCD a 7 Segmentos (Configuracion Catodo Comun, Logica Positiva)
    addwf   PCL, f              
    retlw   b'00111111'         ; 0
    retlw   b'00000110'         ; 1
    retlw   b'01011011'         ; 2
    retlw   b'01001111'         ; 3
    retlw   b'01100110'         ; 4
    retlw   b'01101101'         ; 5
    retlw   b'01111101'         ; 6
    retlw   b'00000111'         ; 7
    retlw   b'01111111'         ; 8
    retlw   b'01101111'         ; 9

ORG 0x100
tabla_bcd_adc
    ; transferencia no lineal: Porcentaje (0-99) a resolucion de hardware (0-255)
    ; ubicada en segmento de pagina independiente para aislar desbordamientos del PCL
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
; INICIO DE EJECUCION (SETUP)
ORG 0x200

main
    ; --- parametros del oscilador central ---
    banksel OSCCON
    movlw   b'01100000'         ; setea oscilador interno primario a 4.0 MHz
    movwf   OSCCON

    ; --- carga de valores iniciales de sistema ---
    banksel 0
    movlw   d'2'
    movwf   display_sel         
    movlw   b'00111111'         
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

    ; --- definicion topologica de puertos visuales ---
    banksel TRISD
    clrf    TRISD               ; bus de segmentos 
    banksel PORTD
    clrf    PORTD               
    banksel ANSEL
    bcf     ANSEL,7             ; configuracion E/S digital para control de display
    bcf     ANSEL,6
    bcf     ANSEL,5
    banksel TRISE
    clrf    TRISE               ; bus de multiplexores 
    banksel PORTE
    clrf    PORTE               

    ; --- definicion topologica de cargas y telecomunicaciones ---
    banksel TRISC
    movlw   b'10000000'         ; bit 7 RX, bit 6 TX, bits 0-2 etapas BJT de potencia
    movwf   TRISC
    banksel PORTC
    clrf    PORTC               ; forzamiento a cero logico preventivo sobre transistores

    ; --- parametrizacion modulo EUSART (Emision Bluetooth) ---
    banksel TXSTA
    movlw   b'00100100'         ; modo asincrono, habilitacion de TX, generador BRG de alta velocidad
    movwf   TXSTA
    banksel RCSTA
    movlw   b'10000000'         ; habilitacion general del modulo de puerto serie
    movwf   RCSTA
    banksel SPBRG
    movlw   d'25'               ; divisor de baud rate para 9600 bps nominales a 4 MHz
    movwf   SPBRG

    ; --- parametrizacion bloque analogico ---
    banksel ADCON1
    movlw   0x00                ; lectura justificada a la izquierda, tensiones de referencia nativas (Vdd/Vss)
    movwf   ADCON1
    banksel TRISA
    bsf     TRISA, 0            ; asignacion pin LM35
    bsf     TRISA, 1            ; asignacion pin LDR
    banksel ANSEL
    movlw   b'00000011'         ; activacion fisica de conversion A/D en AN0 y AN1
    movwf   ANSEL
    banksel ANSELH
    clrf    ANSELH              ; supresion de lectura analogica en resto del banco
    banksel ADCON0
    movlw   b'01000001'         ; prescaler Fosc/8, preseleccion canal AN0, encendido de nucleo ADC
    movwf   ADCON0

    ; --- parametrizacion nucleo Timer0 ---
    banksel OPTION_REG
    movlw   b'01000100'         ; asignacion de prescaler 1:32 acoplado al reloj del sistema
    movwf   OPTION_REG
    banksel TMR0
    movlw   TMR0_VALUE          ; base de interrupcion precalculada
    movwf   TMR0

    ; --- parametrizacion interrupciones de teclado (IOC) ---
    banksel TRISB
    movlw   b'11110000'         ; filas matriciales de entrada, columnas de salida
    movwf   TRISB
    banksel PORTB
    clrf    PORTB               ; fijacion a 0V para sensado de derivacion en filas
    banksel IOCB
    movlw   b'11110000'         ; enmascaramiento de flancos para detectar pulsaciones
    movwf   IOCB
    banksel WPUB
    movlw   b'11110000'         ; activacion pull-up internas previniendo estados flotantes
    movwf   WPUB

    ; --- integracion global de interrupciones ---
    banksel INTCON
    clrf    INTCON              
    bsf     INTCON, TMR0IE      
    bsf     INTCON, RBIE        
    bsf     INTCON, GIE         

    goto main_loop              


; ************************************************************************
; BUCLE PRINCIPAL Y GESTION DE TAREAS
main_loop
    ; --- gestion asincrona de medicion fisica ---
    btfss   banderas, LEER_ADC  ; evaluacion de temporizador macro
    goto    revisar_teclado     
    
    bcf     banderas, LEER_ADC  
    bsf     ADCON0, GO          ; trigger por software del integrador analogo
esperar_adc
    btfsc   ADCON0, GO          ; polling de bandera de finalizacion (Hardware)
    goto    esperar_adc         
    
    movf    ADRESH, w           ; captura del registro alineado
    btfsc   adc_canal_actual, 0 ; enrutamiento cruzado de lecturas
    goto    guardar_an1

guardar_an0
    movwf   adc_temperatura     
    bsf     adc_canal_actual, 0 ; preparacion para escaneo secuencial
    movlw   b'01000101'         ; conmutacion logica a MUX canal 1
    movwf   ADCON0
    goto    revisar_teclado     

guardar_an1
    movwf   adc_luz             
    bcf     adc_canal_actual, 0 
    movlw   b'01000001'         ; conmutacion logica a MUX canal 0
    movwf   ADCON0
    
    ; --- ejecucion de control en lazo cerrado ---
    btfss   estado_actual, NORMAL   ; validacion de estado de maquina
    goto    revisar_teclado         ; inhibicion de reaccion durante ingreso manual
    
    call    control_actuadores      ; rutina principal de evaluacion de umbrales termicos y luminicos
    call    enviar_datos_bluetooth  ; emision periodica por UART de telemetria

revisar_teclado
    ; --- consumo de eventos de hardware de interfaz ---
    btfss   banderas, BUFFER_KEYPAD 
    goto    actualizar_pantalla     
    bcf     banderas, BUFFER_KEYPAD 

    btfsc   estado_actual, NORMAL
    goto    loop_estado_normal      
    btfsc   estado_actual, UMBRAL1
    goto    loop_estado_umbral1     
    goto    loop_estado_umbral2     

actualizar_pantalla
    ; --- renderizado asincrono de informacion telemetrica ---
    btfss   estado_actual, NORMAL
    goto    main_loop

    btfsc   sensor_mostrado, SENSOR_TEMPERATURA
    goto    mostrar_temp
    goto    mostrar_luz

mostrar_temp
    ; transformacion de magnitud electrica a magnitud fisica
    ; resolucion: 19.5mV/bit. respuesta LM35: 10mV/C. 
    ; temp = ADC * (19.5/10) = ADC * 1.95. aproximacion entera: x2 (rlf)
    bcf     STATUS, C
    rlf     adc_temperatura, w
    
    movwf   math_temp       
    sublw   d'99'               ; validacion de rango para el motor grafico (Display)
    btfss   STATUS, C           
    goto    limitar_t
    movf    math_temp, w        
    goto    bcd_t
limitar_t
    movlw   d'99'               ; saturacion numerica logica
bcd_t:
    call    bin_a_bcd           

    movlw   b'01111000'         ; inyeccion en memoria de grafica 't'
    movwf   display0_value
    movf    bcd_decenas, w      
    call    tabla               
    movwf   display1_value
    movf    bcd_unidades, w
    call    tabla               
    movwf   display2_value
    goto    main_loop           

mostrar_luz
    call    calcular_porcentaje_luz 
    
    movf    luz_porcentaje, w
    movwf   math_temp
    sublw   d'99'               ; validacion de desbordamiento grafico
    btfss   STATUS, C
    goto    limitar_l
    movf    math_temp, w
    goto    bcd_l
limitar_l
    movlw   d'99'               
bcd_l:
    call    bin_a_bcd

    movlw   b'00111000'         ; inyeccion en memoria de grafica 'L'
    movwf   display0_value
    movf    bcd_decenas, w
    call    tabla
    movwf   display1_value
    movf    bcd_unidades, w
    call    tabla
    movwf   display2_value
    goto    main_loop           

; -------------------------------------------------------
; MAQUINA DE ESTADOS: FASE DE REPOSO
loop_estado_normal
    ; evaluacion del byte de comando
    movf    keypad_value, w
    xorlw   letraA
    btfsc   STATUS, Z
    goto    loop_normal_letraA  ; operacion sobre umbral alto temp

    movf    keypad_value, w
    xorlw   letraB
    btfsc   STATUS, Z
    goto    loop_normal_letraB  ; operacion sobre umbral bajo temp

    movf    keypad_value, w
    xorlw   letraC
    btfsc   STATUS, Z
    goto    loop_normal_letraC  ; operacion sobre umbral luminoso

    goto    loop_normal_ast     ; operacion de conmutacion de pantalla

loop_normal_letraA
    clrf    estado_actual
    bsf     estado_actual, UMBRAL1  
    movf    keypad_value, w
    movwf   estado_temporal         
    movlw   b'00111110'                 
    movwf   display0_value          ; despliegue grafico 'U'
    movlw   b'01000000'                 
    movwf   display1_value          ; despliegue grafico '-'
    movwf   display2_value          
    clrf    keypad_value            
    clrf    PORTC                   ; proteccion contra comportamiento no determinista del hardware
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
    clrf    keypad_value
    clrf    PORTC
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
    clrf    keypad_value
    clrf    PORTC
    goto    main_loop

loop_normal_ast
    ; multiplexado logico del motor grafico
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
; MAQUINA DE ESTADOS: FASE DE NIBBLE ALTO
loop_estado_umbral1
    movf    keypad_value, w
    xorlw   letraD
    btfsc   STATUS, Z
    goto    loop_umbral1_cancelar   ; instruccion de escape/cancelacion

    movf    keypad_value, w
    sublw   d'9'
    btfss   STATUS, C               ; aislamiento de valores numericos puros
    goto    main_loop       

    ; empaquetamiento BCD: desplazamiento a nibble mas significativo
    movf    keypad_value, w
    movwf   config_umbral_temp      
    swapf   config_umbral_temp, f   
    
    movf    keypad_value, w
    call    tabla
    movwf   display1_value          ; inyeccion a bloque grafico
    movlw   b'01000000'                 
    movwf   display2_value          
    
    clrf    estado_actual
    bsf     estado_actual, UMBRAL2  
    clrf    keypad_value
    goto    main_loop

loop_umbral1_cancelar
    clrf    estado_actual
    bsf     estado_actual, NORMAL   
    clrf    config_umbral_temp      ; purga del registro de composicion
    clrf    keypad_value
    goto    main_loop

; -------------------------------------------------------
; MAQUINA DE ESTADOS: FASE DE NIBBLE BAJO
loop_estado_umbral2
    movf    keypad_value, w
    xorlw   letraD
    btfsc   STATUS, Z
    goto    loop_umbral2_volver     ; instruccion de borrado parcial (backspace)

    movf    keypad_value, w
    sublw   d'9'
    btfss   STATUS, C
    goto    main_loop       

    ; finalizacion de trama BCD: union logica de nibbles
    movf    keypad_value, w         
    iorwf   config_umbral_temp, f   
    
    movf    keypad_value, w
    call    tabla
    movwf   display2_value

    ; descompresion BCD a binario lineal para logica matematica de control
    call    convertir_bcd_a_decimal

    ; direccionamiento de datos en memoria segun parametro temporal guardado
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
    movf    porcentaje_tmp, w       ; transferencia de magnitud decimal (Ej: 35)
    movwf   umbral_alto_temp_8bit   
    goto    loop_umbral2_fin

loop_umbral2_guardar_bajo
    movf    config_umbral_temp, w
    movwf   umbral_bajo_temperatura
    movf    porcentaje_tmp, w       ; transferencia de magnitud decimal (Ej: 15)
    movwf   umbral_bajo_temp_8bit
    goto    loop_umbral2_fin

loop_umbral2_guardar_luz
    movf    config_umbral_temp, w
    movwf   umbral_luz
    
    ; aplica transformacion no lineal de magnitud ingresada por el usuario (0-99%) a resolucion fisica de conversion (0-255)
    movlw   HIGH(tabla_bcd_adc)     
    movwf   PCLATH
    movf    porcentaje_tmp, w
    call    tabla_bcd_adc
    clrf    PCLATH
    movwf   umbral_luz_8bit         
    goto    loop_umbral2_fin

loop_umbral2_fin
    clrf    config_umbral_temp      
    clrf    estado_actual
    bsf     estado_actual, NORMAL   ; cierre del modo programacion
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
; SUBRUTINAS DE LÓGICA MECATRONICA Y COMUNICACIONES
; ************************************************************************

; Subrutina: Ejecucion de Control de Potencia
; Administra las senales para las etapas transistorizadas NPN del microcontrolador
control_actuadores
    ; calcula temperatura real linealizada (ADC * 2) para posibilitar algebra directa
    bcf     STATUS, C
    rlf     adc_temperatura, w
    movwf   math_temp               
    
    ; analisis de sobretemperatura (Refrigeracion)
    movf    umbral_alto_temp_8bit, w
    subwf   math_temp, w            ; magnitud fisica menos umbral
    btfsc   STATUS, C               ; bit C evalua desbordamiento de sustraccion
    goto    encender_ventilador
    
    ; analisis de hipotermia (Calefaccion)
    movf    umbral_bajo_temp_8bit, w
    subwf   math_temp, w            
    btfss   STATUS, C               
    goto    encender_calefactor
    
    ; estado de histéresis inactiva (Rango confort)
    bcf     PORTC, 0                ; bloquea base BJT Ventilador
    bcf     PORTC, 1                ; bloquea base BJT Resistencia Termica
    goto    control_iluminacion
    
encender_ventilador
    bsf     PORTC, 0                ; satura transistor RC0
    bcf     PORTC, 1                ; proteccion de hardware: forzar apagado de contraparte termica
    goto    control_iluminacion

encender_calefactor
    bcf     PORTC, 0                
    bsf     PORTC, 1                ; satura transistor RC1

control_iluminacion
    ; evaluacion de nivel de incidencia de luz ambiente contra patron escalado
    movf    umbral_luz_8bit, w
    subwf   adc_luz, w
    btfss   STATUS, C               ; si iluminacion relativa es menor a calibracion
    goto    encender_leds
    
    bcf     PORTC, 2                ; iluminacion optima, apaga circuito lumínico
    return
    
encender_leds
    bsf     PORTC, 2                ; satura transistor RC2 activando carga luminosa
    return


; Subrutina: Pila de Transmision EUSART Bluetooth
; Formula trama compatible con algoritmos de lectura por delimitador en sistemas externos
enviar_datos_bluetooth
    movlw   'T'
    call    tx_byte
    
    ; reconstruccion visual de magnitud para trama ASCII
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
    
    ; traslacion del binario BCD a codigo estandarizado ASCII
    movf    bcd_decenas, w
    addlw   '0'                     
    call    tx_byte
    movf    bcd_unidades, w
    addlw   '0'                     
    call    tx_byte

    movlw   'L'
    call    tx_byte
    
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
    
    movf    bcd_decenas, w
    addlw   '0'             
    call    tx_byte
    movf    bcd_unidades, w
    addlw   '0'             
    call    tx_byte
    
    ; byte de control de salto de linea (LF = 0x0A) como indicador de final de registro
    movlw   0x0A
    call    tx_byte
    return

tx_byte
    ; gestion de buffers de transmision de hardware
    btfss   PIR1, 4                 ; control de bandera de vaciado TXIF
    goto    tx_byte                 
    movwf   TXREG                   ; carga dato en shift register de transmision
    return


; ************************************************************************
; LIBRERIA DE ALGORITMOS ARITMETICOS
; ************************************************************************

; Subrutina: Formula porcentaje (Resolucion ADC * 100 / 256)
calcular_porcentaje_luz
    clrf    acc_hi
    clrf    acc_lo
    movf    adc_luz, w
    btfsc   STATUS, Z               ; evaluacion de division por cero logico
    goto    fin_adc_porcentaje      
    movwf   loop_cnt                
suma_100
    ; acumulacion en vector de 16 bits
    movlw   d'100'
    addwf   acc_lo, f               
    btfsc   STATUS, C               
    incf    acc_hi, f               
    decfsz  loop_cnt, f             
    goto    suma_100
fin_adc_porcentaje
    ; truncamiento a nivel de byte (Aplica implicitamente division sobre base 256)
    movf    acc_hi, w               
    movwf   luz_
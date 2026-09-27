; ==========================================================================
; F-1 SPIRIT con scroll suave para V9968 - el parche
; ==========================================================================
; Se ensambla sobre las paginas 0 y 15 originales (`incbin`) mas una pagina
; nueva, la 16; tools/parchea_v9968.py monta con ellas la ROM de 256 KB. La
; idea completa esta en v9968/LEEME.md; aqui, lo justo:
;
; EL PROBLEMA. La ventana de la pista son 15 x 24 tiles copiados del buffer
; circular E400 a la tabla de nombres: el fondo se mueve de 8 en 8 pixeles
; aunque la camara (E300) y los sprites van pixel a pixel. El registro de
; scroll vertical R#23 no sirve: moveria tambien el marcador, que va al lado
; de la pista y no encima o debajo.
;
; LA SOLUCION. Cada columna de la ventana, en cada tercio de la pantalla,
; pasa a tener OCHO patrones propios y consecutivos: 64 bytes seguidos que
; son 64 lineas de pixeles de esa columna. Con R#25 CMD=1 los comandos del
; VDP funcionan en SCREEN 2 con coordenadas de SCREEN 8, y esos 64 bytes son
; un trozo de 64 x 1. Un mapa de la pista en la VRAM alta guarda cada
; columna del buffer (256 lineas) en una fila de 256 bytes, asi que hacer
; scroll fino es copiar con HMMM desde la linea que diga la camara: 18
; comandos por repintado (3 tercios x 3 grupos de 5 columnas x patron y
; color). El mapa se rellena tile a tile (dos HMMM de 8 x 1 por celda) solo
; cuando el juego pinta filas nuevas.
;
; Las tablas del juego (0x0000 y 0x2000) no se tocan nunca: son el atlas del
; que se copian los tiles. En modo fino el VDP pinta con tablas propias en
; 0x10000/0x12000 (R#3, R#4 y R#10); las filas de patrones donde viven los
; tiles del marcador (0x00-0x1F y 0xC0-0xFF) se copian del juego.
;
; EL TIEMPO. El juego da un paso de logica cada tres interrupciones (F0FC) y
; repinta dentro de la interrupcion. Para que nada cambie:
; - el repintado va al principio del VBLANK, antes del sonido (0x4046), y
;   las tiras del tercio de arriba incluso antes que los sprites (V9_ANTES):
;   todo esta en la VRAM antes de que el haz llegue, sin cortes;
; - lo que no se ve (filas ocultas, columna de margen) va despues del sonido
;   (0x405A, V9_CELDAS_FONDO);
; - una interrupcion que llega mientras tanto no se pierde: en su salida
;   (0x40B5) se le hace su sonido y cuenta en el reloj (V9_ANIDADA).
; ==========================================================================

	include "v9968/comun.asm"
	include "work/v9968/ram_simbolos.asm"	; las etiquetas V9R_ de ram.asm

; ==========================================================================
; PAGINA 0: los ganchos. Un `call`/`jp` de tres bytes (y algun `nop`) donde
; habia una instruccion que se rehace en la RAM (ram.asm) o en la pagina 15;
; el del borrado de la RAM de INIT es algo mas largo.
; ==========================================================================
	org 04000h
	incbin "work/v9968/p00.bin"

	; el borrado de la RAM de INIT (0xE000-0xF0FF), con la pila ya en 0xF0F0
	; y las interrupciones cerradas. Lo hace V9_ARRANQUE, que ademas copia el
	; codigo de la RAM: tiene que estar antes del primer `ei` (0x4302), que
	; desde ahi cualquier interrupcion sale por 0x40B5. La 15 va a 0xA000
	; (el cartucho ya esta ahi, 0x4102); hasta 0x42C1 nadie mira 0xA000.
	org G_BORRA_RAM		; ld hl,0E000h / ld de,0E001h / ld bc,010FFh / ld (hl),0 / ldir
	ld a,00Fh
	ld (MAPPER_A000),a
	call V9_ARRANQUE
	jr G_BORRA_RAM_SIGUE	; (lo que queda de la instruccion, sin tocar)

	org G_SALIDA_INT	; call RDVDP
	call V9R_ANIDADA

	org G_INIT		; call 0BF50h
	call V9_INIT

	org G_SONIDO		; call SONIDO_PASO
	call V9R_SONIDO

	org G_REPINTA		; call nc,REPINTA_PENDIENTE
	call nc,V9R_REPINTA_405A

	org G_VENTANA_1J	; ld ix,0E2C0h
	jp V9R_VENTANA

	org G_VENTANA_J2	; ld iy,0E380h
	jp V9R_H_VJ2

	org G_VENTANA_2J	; ld a,(00007h)
	call V9R_H_V2J

	org G_VUELCA_768	; push hl / ld hl,03800h
	jp V9R_H_VUELCA

	org G_BORRA_VENTANA	; ld b,018h / ld hl,03802h
	call V9R_H_BORRA_VENT
	nop
	nop

	org G_BORRA_SPRITES	; ld a,0E0h / ld hl,0EA80h
	call V9R_H_BORRA_SPR
	nop
	nop

	org G_CORTINILLA	; ld hl,0E1C4h
	call V9R_H_CORTINILLA

	org G_CASILLA_HUD	; ld hl,03965h
	call V9R_H_ROTULO

	org G_LISTA_TILES	; push hl / pop ix
	call V9R_H_LISTA

	org G_FILA_PISTA_FIN	; jp MAPEA_1_2_3
	jp V9R_H_FILA

	org G_OBJETO		; ld (ix-003h),000h
	call V9R_H_OBJETO
	nop

; ==========================================================================
; PAGINA 15 (0xA000): en su hueco de 716 bytes a 0xFF (0xBC84-0xBF4F), lo
; que se llama con la 15 en 0xA000: el arranque (V9_ARRANQUE y V9_INIT), la
; recuperacion de interrupciones (V9_ANIDADA) y la imagen de la RAM.
; ==========================================================================
	org 0A000h
	incbin "work/v9968/p15.bin"

	org P15_ANIDADA
	jp V9_ANIDADA		; la RAM llega aqui por una direccion fija

; V9_ARRANQUE: en lugar del borrado de la RAM de INIT (0x4117). Borra la del
; juego y la del parche (0xE000-0xF37F) y copia el codigo de la RAM. El
; borrado se lleva la pila por delante, asi que la vuelta va en IX.
V9_ARRANQUE:
	pop ix
	ld hl,0E000h
	ld de,0E001h
	ld bc,0137Fh
	ld (hl),000h
	ldir
	ld hl,V9_IMAGEN_RAM
	ld de,V9_RAM_CODIGO
	ld bc,V9_IMAGEN_LARGO
	ldir
	ld a,0FFh
	ld (V9_COL0),a		; ninguna columna calculada todavia
	ld (V9_COL_NUEVA),a	; ni columna de margen que rellenar
	jp (ix)

; V9_INIT: en lugar del `call 0BF50h` de INIT (0x4138): que VDP hay (en la
; pagina 16). El `ret` vuelve a 0x413B, que mapea 1/2/3 y abre las
; interrupciones.
V9_INIT:
	call BUSCA_CONSOLA
	di			; la deteccion cambia R#15: sin interrupciones
	ld hl,P16_DETECTA
	jp V9R_LEJOS

; --------------------------------------------------------------------------
; V9_ANIDADA: desde V9R_ANIDADA (0x40B5) con la 15 en 0xA000, las
; interrupciones cerradas y B = S#0, si esta interrupcion o la de fuera ha
; pasado por el renderer. Devuelve en A la pagina para 0xA000.
; - Con el candado del bit 1 de E1C5 puesto, es una interrupcion que ha
;   entrado mientras la de fuera repintaba (0x4020): la de fuera esta entre
;   0x4049 y 0x4060, con D/E/F puestas salvo la 16 en 0x6000 si esta en el
;   renderer. Se hace su sonido, su cola y su cuenta atras, y se apunta.
; - Sin el, es la salida de la interrupcion que ha repintado (o de una que
;   ha entrado en su logica): se baja la marca y, si este RDVDP se ha comido
;   un VBLANK que llego con las interrupciones cerradas, se hace su parte.
; El reloj del juego (F0FC): la de fuera todavia no ha mirado si toca paso
; de logica (0x409E), y al darlo PONE F0FC A CERO. Una de dentro cuenta en
; el acto si la de fuera no llega a 3 con la suya (el paso que le tocaba a
; esta sale al acabar el repintado: tarde, pero sale); si ya llegaba, se
; aparta en V9_TICS y se suma aqui, en la salida, detras del cero. Asi cada
; VBLANK cuenta una vez y ninguno se pierde.
; --------------------------------------------------------------------------
V9_ANIDADA:
	ld a,(E_CANDADOS)
	and 002h
	jr nz,V9_ANID_DENTRO
	ld (V9_EN_VENTANA),a	; A = 0
	bit 7,b
	jr z,V9_ANID_RELOJ
	ld hl,V9_TICS
	inc (hl)
	call V9_TIC
V9_ANID_RELOJ:
	ld hl,V9_TICS
	ld a,(hl)
	ld (hl),0
	ld hl,RELOJ_INT
	add a,(hl)
	ld (hl),a
	ld a,(SOMBRA_A000)	; los bancos ya son los de antes de la interrupcion
	ret
V9_ANID_DENTRO:
	ld hl,RELOJ_INT
	ld a,(hl)
	inc a			; lo que va a ver la de fuera con la suya (0x4085)
	cp 003h
	jr nc,V9_ANID_APARTA
	ld (hl),a		; no llega a paso: esta cuenta ya, y el paso sale
	jr V9_ANID_TIC		; al acabar el repintado, sin perder nada
V9_ANID_APARTA:
	ld hl,V9_TICS		; ya da paso sin esta: para despues del cero
	inc (hl)
V9_ANID_TIC:
	call V9_TIC
	ld a,00Fh
	ret

; Lo que hace la interrupcion por cada fotograma (0x4029-0x4067) salvo el
; repintado, el reloj y la logica, dejando 0x6000 y 0x8000 como digan sus
; sombras
V9_TIC:
	ld hl,(SOMBRA_6000)	; L = la de 0x6000, H = la de 0x8000
	push hl
	ld a,00Dh
	ld (MAPPER_6000),a
	inc a
	ld (MAPPER_8000),a
	call SONIDO_PASO
	ld a,00Dh		; el driver deja la 2 en 0x8000 (0x4049)
	ld (MAPPER_6000),a
	inc a
	ld (MAPPER_8000),a
	inc a
	ld (MAPPER_A000),a
	call VACIA_COLA_SONIDO
	call SONIDO_6422
	call CUENTA_ATRAS_F0F7
	pop hl
	ld a,l
	ld (MAPPER_6000),a
	ld a,h
	ld (MAPPER_8000),a
	ret

; (la imagen de la RAM va en la pagina 15)
V9_IMAGEN_RAM:
	incbin "work/v9968/ram.bin"
V9_IMAGEN_LARGO	equ $ - V9_IMAGEN_RAM

V9_FIN_P15:

; ==========================================================================
; PAGINA 16 (nueva, en 0x6000): el renderer. Solo se mapea mientras se usa,
; con V9R_LEJOS (ram.asm), y empieza por una tabla de saltos fija.
; ==========================================================================
	org 06000h

	jp V9_VENTANA_1J	; P16_VENTANA_1J
	jp V9_VIGILA		; P16_VIGILA
	jp V9_DETECTA		; P16_DETECTA
	jp V9_FILA		; P16_FILA
	jp V9_OBJETO		; P16_OBJETO
	jp V9_CELDAS_FONDO	; P16_FONDO

; --------------------------------------------------------------------------
; V9_FILA: al final de PINTA_FILA_PISTA (por V9R_H_FILA), IX = el coche del
; jugador 1 (el filtro esta en la RAM).
; OJO: el juego la llama en CADA paso de logica (0x5C0C), no solo cuando la
; pista avanza una fila, y casi siempre repinta la misma fila con lo mismo.
; Solo se apunta como sucia si cambia la fila, la pieza o la fila dentro de
; la pieza. Si ha caido un objeto (COLOCA_OBJETO deja su mitad baja en la
; fila de debajo y el aviso en (ix-3)), sus dos filas se apuntan cuando el
; juego carga sus patrones, en el paso siguiente (V9_OBJETO).
; --------------------------------------------------------------------------
V9_FILA:
	ld a,(ix+040h)		; la fila que calcula FILA_BUFFER_NOMBRES (0x56F7)
	sub 040h
	rrca
	rrca
	rrca
	and 01Fh
	ld c,a
	ld hl,V9_ULTIMA
	cp (hl)
	jr nz,V9_FILA_NUEVA
	inc hl
	ld a,(ix+046h)
	cp (hl)
	jr nz,V9_FILA_PIEZA
	inc hl
	ld a,(ix+045h)
	cp (hl)
	jr nz,V9_FILA_FPIEZA
	jr V9_FILA_OBJETO	; la misma fila con lo mismo
V9_FILA_NUEVA:
	ld (hl),c
	inc hl
	ld a,(ix+046h)
V9_FILA_PIEZA:
	ld (hl),a
	inc hl
	ld a,(ix+045h)
V9_FILA_FPIEZA:
	ld (hl),a
	ld a,c
	call V9_MARCA_SUCIA
V9_FILA_OBJETO:
	ld a,(ix-003h)
	or a
	ret z
	ld a,c			; ha caido un objeto en esta fila y la de debajo:
	or 080h			; sus patrones llegan en el paso que viene (V9_OBJETO)
	ld (V9_OBJ),a
	ret

; V9_OBJETO: desde TILES_OBJETO_PISTA (0x4701, por V9R_H_OBJETO) con un
; objeto apuntado en V9_OBJ. Ya estan sus patrones: sus dos filas, sucias.
V9_OBJETO:
	ld a,(ix+009h)		; los del jugador 1
	dec a
	ret nz
	ld a,(V9_OBJ)
	and 01Fh
	ld (V9_OBJ),a		; (bit 7 fuera: atendido)
	call V9_MARCA_SUCIA
	ld a,(V9_OBJ)
	inc a
	and 01Fh

; A = fila del buffer (0..31): su bit en V9_SUCIAS
V9_MARCA_SUCIA:
	ld c,a
	call V9_BIT_SUCIA
	ld a,b
	or (hl)
	ld (hl),a
	ret

; --------------------------------------------------------------------------
; V9_DETECTA: que VDP hay. El modo fino necesita comandos en G2 (V9958 o
; V9968) y en 0x98, y que sean rapidos: con un V9958 no da tiempo (la carrera
; baja a unos 12 pasos por segundo en vez de 20), asi que solo se pone con el
; V9968 y su modo HS, salvo con la opcion V9958_FINO (comun.asm).
; --------------------------------------------------------------------------
V9_DETECTA:
	ld a,(0002Dh)		; version de MSX de la BIOS: 2 = MSX2+, 3 = turboR
	cp 002h
	ret c
	call V9_ID
	cp 002h			; V9958, o V9968 con V58 = 1 (su valor al encender)
	jr z,V9_DET_68
	cp 003h			; V9968 con V58 = 0
	ret nz
V9_DET_68:
	; Es un V9968? Al encender dice que es un V9958 (ID 2, R#21 V58 = 1) para
	; que el software de MSX2+ lo reconozca. Con V58 = 0 da su ID de verdad,
	; el 3. El RTL actual solo deja escribir R#20/R#21 con el candado del
	; puerto 4 (0x9C) quitado: bit 7 a 0 (y los bits 0-2 a 0, que no borren
	; ninguna bandera). Por si 0x9C fuera un espejo del puerto de datos en
	; esta maquina, la VRAM se apunta antes a un sitio que no usa nadie.
	ld a,0F8h
	out (VDP_CTRL),a
	ld a,03Fh + 040h	; escribir en 0x3FF8
	out (VDP_CTRL),a
	xor a
	out (VDP_PUERTO4),a	; el candado, quitado
	ld bc,256 * 000h + 080h + 21	; R#21 = 0: V58 = 0
	call V9R_REG
	call V9_ID
	push af
	ld bc,256 * 03Bh + 080h + 21	; R#21 = 0x3B: V58 = 1 en el V9968, y el
	call V9R_REG			; valor de siempre en un V9938/V9958
	pop af
	ld hl,V9_CAPS
	cp 003h
	jr z,V9_DET_V9968
	if V9958_FINO		; un V9958
	set 0,(hl)
	jr V9_DET_CMD
	else
	ret
	endif
V9_DET_V9968:
	ld (hl),003h
	ld bc,256 * (001h + V9968_S16 * 080h) + 080h + 20	; R#20: HS [+ S16]
	call V9R_REG
	ld a,080h
	out (VDP_PUERTO4),a	; y el candado otra vez puesto
V9_DET_CMD:
	ld bc,256 * 040h + 080h + 25	; R#25: CMD = 1
	jp V9R_REG

; A = el ID del VDP (S#1, bits 5..1)
V9_ID:
	ld a,1
	call V9_R15
	in a,(VDP_CTRL)
	ld b,a
	xor a
	call V9_R15
	ld a,b
	rrca
	and 01Fh
	ret

; A -> R#15
V9_R15:
	out (VDP_CTRL),a
	ld a,080h + 15
	out (VDP_CTRL),a
	ret

; --------------------------------------------------------------------------
; V9_VIGILA: desde la interrupcion (0x405A), con el modo fino puesto. Si el
; juego ha salido de la carrera, se vuelve a las tablas del juego y, si la
; ventana sigue en pantalla, se repinta como siempre.
; --------------------------------------------------------------------------
V9_VIGILA:
	call V9_ESTADO_OK
	jr z,V9_ANTES
	ld hl,03802h		; la esquina de arriba de la ventana...
	call V9_LEE_VRAM
	cp 020h			; ...con el nombre de su tira?
	call V9R_GRUESO		; (respeta las banderas)
	ret nz
	jp V9_GRUESA_1J

; --------------------------------------------------------------------------
; V9_ANTES: el principio de la ventana, ANTES de que el juego copie los
; sprites (1.4 ms), para que las tiras del tercio de arriba esten en la VRAM
; antes de que el haz llegue a el (unos 4.5 ms despues del VBLANK en NTSC).
; Desde V9_VIGILA, con el modo fino puesto y el juego en la carrera. Solo si
; el repintado va a pintar la ventana de un jugador (E1D5 y el bit 5 de
; E1C2, como 0x40BB y 0x450C); lo demas, en V9_VENTANA_1J.
; --------------------------------------------------------------------------
V9_ANTES:
	ld a,(0E1D5h)
	or a
	ret z
	ld a,(0E1C2h)
	and 020h
	ret nz
	ld a,2
	ld (V9_EN_VENTANA),a
	ld (V9_ANTICIPO),a	; (2: sale gruesa, si no llega a 1)
	ld bc,256 * 040h + 080h + 25	; R#25: CMD = 1
	call V9_REG
	call V9_PREPARA
	call V9_CELDAS
	ld a,(V9_COMPLETA)
	or a
	ret z
	call V9_TIRAS		; hasta el tercio 0
	ld a,1
	ld (V9_ANTICIPO),a
	ret

; Z si el juego esta en la carrera (o en su pausa): estados 2 y 5 de E1C0,
; subestados 0x0B y 0x16 de E250
V9_ESTADO_OK:
	ld a,(E_ESTADO)
	cp 005h
	jr z,V9_ESTADO_SUB
	cp 002h
	ret nz
V9_ESTADO_SUB:
	ld a,(E_SUBESTADO)
	and 07Fh
	cp 00Bh
	ret z
	cp 016h
	ret

; A = VRAM(HL), direccion de 14 bits
V9_LEE_VRAM:
	di
	ld a,l
	out (VDP_CTRL),a
	ld a,h
	out (VDP_CTRL),a
	ex (sp),hl
	ex (sp),hl
	in a,(VDP_DATOS)
	ret

; --------------------------------------------------------------------------
; V9_VENTANA_1J: la ventana de un jugador (0x4513, por V9R_VENTANA), desde el
; repintado de la interrupcion o desde 0x4BE9. Si el mapa de la VRAM tiene
; todo lo que se ve, modo fino; si no, el volcado de siempre.
; --------------------------------------------------------------------------
; Las interrupciones se dejan abiertas: cada acceso al VDP que no se puede
; partir (las dos escrituras de un registro, la espera con R#15 = 2, un
; comando) va entre `di` y `ei`, como hace la BIOS. Asi ningun VBLANK se
; queda esperando tanto como para perderse. La interrupcion que entra aqui
; dentro sale enseguida por el candado del bit 1 de E1C5, y en esa salida
; (0x40B5, V9R_ANIDADA) se le hace su parte de sonido y de reloj (F0FC): la
; marca V9_EN_VENTANA lo permite hasta el final de esta interrupcion.
V9_VENTANA_1J:
	ld a,(E_CANDADOS)	; desde la interrupcion (0x405A), con el candado
	and 002h
	jr z,V9_V1J_GRUESA	; desde 0x4BE9 (la logica): lo de siempre, que
	ld (V9_EN_VENTANA),a	; justo despues se vuelven a cargar los tiles
	ld hl,V9_ANTICIPO	; lo ha empezado V9_ANTES?
	ld a,(hl)
	ld (hl),0
	dec a
	jr z,V9_V1J_RESTO
	dec a
	jr z,V9_V1J_GRUESA
	call V9_ESTADO_OK
	jr nz,V9_V1J_GRUESA
	ld bc,256 * 040h + 080h + 25	; R#25: CMD = 1 (por si alguien lo hubiera cambiado)
	call V9_REG
	call V9_PREPARA
	call V9_CELDAS		; lo que se ve...
	ld a,(V9_COMPLETA)
	or a
	jr z,V9_V1J_GRUESA
	call V9_TIRAS		; ...a la pantalla cuanto antes (lo que no se ve,
V9_V1J_RESTO:			; V9_CELDAS_FONDO, despues del sonido: 0x405A)
	call V9_TIRAS_RESTO
	call V9_NOMBRES_FINOS
	ld ix,0E2C0h		; como los deja la ventana original
	ld iy,0E2C0h
	ret
V9_V1J_GRUESA:
	call V9R_GRUESO
V9_GRUESA_1J:
	ld ix,0E2C0h
	jp VENTANA_1J_SIGUE

; --------------------------------------------------------------------------
; V9_PREPARA: tiles cambiados, camara, columnas visibles y filas sucias
; --------------------------------------------------------------------------
V9_PREPARA:
	ld hl,(V9_TILES)
	ld a,h
	or l
	jr z,V9_PREP_CAMARA
	; el cargador ha escrito tiles: todo el mapa a rehacer, y mientras tanto
	; el volcado de siempre
	ld hl,0
	ld (V9_TILES),hl
	call V9R_GRUESO
	ld hl,V9_VALIDAS
	ld b,128
	xor a
V9_PREP_BORRA:
	ld (hl),a
	inc hl
	djnz V9_PREP_BORRA
	ld hl,V9_SUCIAS
	ld (hl),a
	inc hl
	ld (hl),a
	inc hl
	ld (hl),a
	inc hl
	ld (hl),a
	call V9_VACIA_LLENAS
V9_PREP_CAMARA:
	ld a,(E_CAMARA_Y)
	ld (V9_CAMY),a
	ld b,a
	and 007h
	ld (V9_FASE),a
	ld a,24			; con la camara en fila justa se ven 24 filas...
	jr z,V9_PREP_NV
	inc a			; ...y si no, 25: la de abajo asoma FASE lineas
V9_PREP_NV:
	ld (V9_NV),a
	ld a,b
	rrca
	rrca
	rrca
	and 01Fh
	ld (V9_FILA0),a
	ld a,(E_CAMARA_X)
	rrca
	rrca
	rrca
	and 01Fh
	ld hl,V9_COL0
	cp (hl)
	call nz,V9_COLUMNAS
	; las filas que el juego ha repintado: si ya no se ven, a rehacer; la
	; que asoma por abajo se queda como estaba (tiene lo que se ve ahi). Se
	; va de byte en byte, que casi siempre estan los cuatro a cero.
	ld c,0
V9_PREP_BYTE:
	ld a,c
	rrca
	rrca
	rrca
	add a,V9_SUCIAS & 0FFh
	ld l,a
	ld h,V9_SUCIAS / 256
	ld a,(hl)
	or a
	jr nz,V9_PREP_BITS
	ld a,c
	add a,8
	ld c,a
	cp 32
	jr nz,V9_PREP_BYTE
	ret
V9_PREP_BITS:
	ld (V9_FALTAN),a	; (de paso, los bits que quedan del byte)
V9_PREP_BIT:
	ld hl,V9_FALTAN
	srl (hl)
	call c,V9_PREP_FILA
	inc c
	ld a,c
	and 007h
	jr nz,V9_PREP_BIT
	ld a,c
	cp 32
	jr nz,V9_PREP_BYTE
	ret

; C = una fila sucia
V9_PREP_FILA:
	ld a,(V9_FILA0)
	ld d,a
	ld a,c
	sub d
	and 01Fh		; su posicion en la ventana
	ld d,a
	ld a,(V9_NV)
	dec a
	cp d
	ret nc			; se ve: se queda sucia hasta que deje de verse
	call V9_BIT_SUCIA
	ld a,b
	cpl
	ld d,a
	and (hl)
	ld (hl),a		; ya no esta sucia...
	ld a,l
	add a,V9_LLENAS - V9_SUCIAS
	ld l,a
	ld a,d
	and (hl)
	ld (hl),a		; ...ni llena...
	ld a,c
	add a,a
	add a,a
	add a,V9_VALIDAS & 0FFh
	ld l,a
	ld h,V9_VALIDAS / 256
	xor a			; ...ni le vale ninguna celda
	ld (hl),a
	inc l
	ld (hl),a
	inc l
	ld (hl),a
	inc l
	ld (hl),a
	ret

; ninguna fila llena: cuando cambia mucho la ventana, o todo el mapa
V9_VACIA_LLENAS:
	xor a
	ld hl,V9_LLENAS
	ld (hl),a
	inc hl
	ld (hl),a
	inc hl
	ld (hl),a
	inc hl
	ld (hl),a
	ret

; C = fila: HL = su byte en V9_SUCIAS, B = su bit, Z si no esta sucia
V9_BIT_SUCIA:
	ld a,c
	and 007h
	add a,V9_MASCARAS & 0FFh
	ld l,a
	ld h,V9_MASCARAS / 256
	ld b,(hl)
	ld a,c
	rrca
	rrca
	rrca
	and 003h
	add a,V9_SUCIAS & 0FFh
	ld l,a
	ld h,V9_SUCIAS / 256
	ld a,b
	and (hl)
	ret

; --------------------------------------------------------------------------
; V9_COLUMNAS: A = columna del mapa de la izquierda de la ventana (0..31),
; HL = V9_COL0 con la de antes. V9_VIS son las 15 columnas que se ven y una
; mas a cada lado, de margen: cuando la ventana se mueve una columna, la que
; entra ya esta en la VRAM y solo falta la de margen que llega, que V9_CELDAS
; rellena entera y de una vez (V9_COL_NUEVA). Si se mueve mas, todo a mirar.
; --------------------------------------------------------------------------
V9_COLUMNAS:
	ld b,(hl)
	ld (hl),a
	ld c,a			; C = la nueva
	ld a,(V9_COL_NUEVA)	; si la de margen de la vez anterior esta sin
	inc a			; rellenar (no hubo repintado fino), V9_LLENAS
	jr nz,V9_COLS_TODAS	; ya no dice la verdad
	ld a,c
	sub b
	and 01Fh
	dec a
	jr z,V9_COLS_DER	; una a la derecha: llega la de despues
	add a,2
	and 01Fh
	jr z,V9_COLS_IZQ	; una a la izquierda: llega la de antes
V9_COLS_TODAS:
	call V9_VACIA_LLENAS
	ld a,0FFh
	jr V9_COLS_NUEVA
V9_COLS_DER:
	ld a,c
	add a,15
	jr V9_COLS_MARGEN
V9_COLS_IZQ:
	ld a,c
	dec a
V9_COLS_MARGEN:
	and 01Fh
V9_COLS_NUEVA:
	ld (V9_COL_NUEVA),a
	ld hl,V9_VIS
	xor a
	ld (hl),a
	inc hl
	ld (hl),a
	inc hl
	ld (hl),a
	inc hl
	ld (hl),a
	ld a,c
	dec a
	and 01Fh
	ld c,a			; de la de antes de la ventana...
	ld b,17			; ...a la de despues
V9_COLS_BUCLE:
	ld a,c
	and 007h
	add a,V9_MASCARAS & 0FFh
	ld l,a
	ld h,V9_MASCARAS / 256
	ld d,(hl)		; D = su bit...
	ld a,c
	rrca
	rrca
	rrca
	and 003h
	add a,V9_VIS & 0FFh
	ld l,a
	ld h,V9_VIS / 256	; ...y HL = su byte
	ld a,d
	or (hl)
	ld (hl),a
	ld a,c
	inc a
	and 01Fh
	ld c,a
	djnz V9_COLS_BUCLE
	ret

; --------------------------------------------------------------------------
; V9_CELDAS: rellena en el mapa de la VRAM las celdas que faltan. La columna
; de margen que haya llegado, entera; luego lo visible y, con lo que quede,
; las filas ocultas. Deja V9_COMPLETA = 1 si todo lo visible esta.
; --------------------------------------------------------------------------
V9_CELDAS:
	ld a,1
	ld (V9_COMPLETA),a
	xor a
	ld (V9_NUEVAS),a
	call V9_TODAS_LLENAS	; con las 32 filas llenas no hay nada que hacer
	ret z
	ld a,(V9_FINO)
	or a
	ld a,N_ENTRADA		; entrando: unas pocas por repintado
	jr z,V9_CEL_PRESUP
	ld a,0FFh		; en modo fino, todo lo visible
V9_CEL_PRESUP:
	ld (V9_PRESUP),a
	xor a			; (los registros de celda, cuando haga falta)
	ld (V9_REGS_CELDA),a
	jp V9_RECORRE		; las filas que se ven

; V9_CELDAS_FONDO: con lo visible ya en pantalla, lo que no se ve: la
; columna de margen que haya llegado, entera, y las filas ocultas mientras
; quede presupuesto. Desde 0x405A (V9R_REPINTA_405A), despues del sonido.
V9_CELDAS_FONDO:
	xor a
	ld (V9_REGS_CELDA),a
	ld a,(V9_COL_NUEVA)
	inc a
	jr z,V9_FONDO_FILAS
	call V9_CEL_REGISTROS
	ld a,(V9_COL_NUEVA)
	ld c,a
	ld a,0FFh
	ld (V9_COL_NUEVA),a
	call V9_COLUMNA
V9_FONDO_FILAS:
	call V9_TODAS_LLENAS
	ret z
	ld a,N_ADELANTO
	ld (V9_PRESUP),a
	ld a,1
	jp V9_RECORRE

; Z si las 32 filas estan en V9_LLENAS
V9_TODAS_LLENAS:
	ld hl,V9_LLENAS
	ld a,(hl)
	inc hl
	and (hl)
	inc hl
	and (hl)
	inc hl
	and (hl)
	inc a
	ret

; los registros fijos de los HMMM de celda, si no estan ya
V9_CEL_LAZY:
	ld a,(V9_REGS_CELDA)
	or a
	ret nz
V9_CEL_REGISTROS:
	ld a,1
	ld (V9_REGS_CELDA),a
	ld hl,V9_T_CELDA
	call V9_BLK_CARGA
	jp V9_ENVIA

; --------------------------------------------------------------------------
; V9_COLUMNA: C = columna del mapa: la columna de margen que acaba de
; llegar, en todas las filas en que falte y de una vez (con el presupuesto
; por filas costaria una fila entera por celda). Las que se ven y el juego
; ya ha repintado (ver V9_PREPARA) se dejan: pierden V9_LLENAS y las atiende
; V9_FILA_CELDAS como cualquier otra.
; --------------------------------------------------------------------------
V9_COLUMNA:
	ld a,c
	and 007h
	add a,V9_MASCARAS & 0FFh
	ld l,a
	ld h,V9_MASCARAS / 256
	ld d,(hl)		; D = su bit...
	ld a,c
	rrca
	rrca
	rrca
	and 003h
	ld e,a			; ...y E = su byte en cada fila de V9_VALIDAS
	ld b,0			; B = posicion en la ventana
V9_COL_FILA:
	ld a,(V9_FILA0)
	add a,b
	and 01Fh
	ld (V9_S),a
	add a,a
	add a,a
	add a,e
	add a,V9_VALIDAS & 0FFh
	ld l,a
	ld h,V9_VALIDAS / 256
	ld a,(hl)
	and d
	jp nz,V9_COL_SIGUE	; esta
	ld a,(V9_NV)
	dec a
	cp b
	jr c,V9_COL_VALE	; oculta
	ld a,(V9_SUCIAS)	; (casi nunca hay ninguna sucia)
	or a
	jr nz,V9_COL_MIRA
	ld a,(V9_SUCIAS+1)
	or a
	jr nz,V9_COL_MIRA
	ld a,(V9_SUCIAS+2)
	or a
	jr nz,V9_COL_MIRA
	ld a,(V9_SUCIAS+3)
	or a
	jr z,V9_COL_VALE
V9_COL_MIRA:
	push hl
	push bc
	ld a,(V9_S)
	ld c,a
	call V9_BIT_SUCIA
	jr z,V9_COL_LIMPIA
	ld a,l			; se ve y esta sucia: fuera de V9_LLENAS
	add a,V9_LLENAS - V9_SUCIAS
	ld l,a
	ld a,b
	cpl
	and (hl)
	ld (hl),a
	pop bc
	pop hl
	jr V9_COL_SIGUE
V9_COL_LIMPIA:
	pop bc
	pop hl
V9_COL_VALE:
	ld a,(hl)
	or d
	ld (hl),a		; valida desde ya
	ld a,b			; el tercio del atlas, como en V9_FC_VALE
	cp 25
	jr c,V9_COL_T1
	xor a
V9_COL_T1:
	cp 24
	jr c,V9_COL_T2
	ld a,16
V9_COL_T2:
	and 018h
	ld l,a
	add a,PAT_JUEGO
	ld (V9_SYP),a
	ld a,l
	add a,COL_JUEGO
	ld (V9_SYC),a
	ld a,(V9_S)		; el tile: E400 + 32 * fila + columna
	rrca
	rrca
	rrca
	ld l,a
	and 003h
	add a,E_BUFFER_J1 / 256
	ld h,a
	ld a,l
	and 0E0h
	or c
	ld l,a
	push de
	di
	ld a,2
	out (VDP_CTRL),a
	ld a,080h + 15
	out (VDP_CTRL),a
V9_COL_ESPERA:
	in a,(VDP_CTRL)
	rrca
	jr c,V9_COL_ESPERA
	ld a,(V9_S)		; DX = fila * 8
	add a,a
	add a,a
	add a,a
	out (VDP_CTRL),a
	ld a,080h + 36
	out (VDP_CTRL),a
	ld a,(hl)
	call V9_CELDA
	call V9_FC_R15
	pop de
V9_COL_SIGUE:
	inc b
	ld a,b
	cp 32
	jp nz,V9_COL_FILA
	ret

; Las filas del mapa de la pasada A (0 = las que se ven, 1 = las ocultas) que
; no estan en V9_LLENAS. Se recorren los bits a cero de byte en byte: con el
; coche en marcha suele faltar una fila, y parado ninguna.
V9_RECORRE:
	ld (V9_PASADA),a
	ld c,0
V9_REC_BYTE:
	ld a,c
	rrca
	rrca
	rrca
	add a,V9_LLENAS & 0FFh
	ld l,a
	ld h,V9_LLENAS / 256
	ld a,(hl)
	cpl
	ld (V9_FALTAN),a
	or a
	jr nz,V9_REC_BIT
	ld a,c
	add a,8
	ld c,a
	cp 32
	jr nz,V9_REC_BYTE
	ret
V9_REC_BIT:
	ld hl,V9_FALTAN
	srl (hl)
	jr nc,V9_REC_SIGUE	; esta llena
	ld a,(V9_FILA0)
	ld b,a
	ld a,c
	sub b
	and 01Fh
	ld b,a			; su posicion en la ventana
	ld a,(V9_NV)
	dec a
	cp b			; acarreo: oculta
	ld a,(V9_PASADA)
	adc a,0			; pasada + oculta: 0 o 2 si toca en esta pasada,
	rrca			; 1 si no
	jr c,V9_REC_SIGUE
	push bc
	ld a,b
	call V9_FILA_CELDAS
	pop bc
	ld a,(V9_COMPLETA)
	or a
	ret z
	; sin presupuesto, las ocultas ya pueden esperar; las que se ven se
	; siguen mirando: puede que no les falte nada (solo cambio la ventana), y
	; si les falta, V9_FC_AGOTADO baja V9_COMPLETA
	ld a,(V9_PRESUP)
	or a
	jr nz,V9_REC_SIGUE
	ld a,(V9_PASADA)
	or a
	ret nz
V9_REC_SIGUE:
	inc c
	ld a,c
	and 007h
	jr nz,V9_REC_BIT
	ld a,c
	cp 32
	jr nz,V9_REC_BYTE
	ret

; --------------------------------------------------------------------------
; V9_FILA_CELDAS: A = posicion en la ventana (0 arriba). Las celdas que le
; falten a esa fila, mientras quede presupuesto.
; --------------------------------------------------------------------------
V9_FILA_CELDAS:
	ld b,a
	ld (V9_POS),a
	ld a,(V9_FILA0)
	add a,b
	and 01Fh
	ld (V9_S),a
	add a,a
	add a,a
	add a,V9_VALIDAS & 0FFh
	ld l,a
	ld h,V9_VALIDAS / 256
	ld (V9_PVAL),hl		; HL = sus 32 bits de validez
	ld de,V9_VIS
	ld ix,V9_FALTA		; faltan = V9_VIS & ~validas
	ld c,0
	ld b,4
V9_FC_MASC:
	ld a,(hl)
	cpl
	ex de,hl
	and (hl)
	ex de,hl
	ld (ix+0),a
	or c
	ld c,a
	inc hl
	inc de
	inc ix
	djnz V9_FC_MASC
	ld a,c
	or a
	jp z,V9_FC_LLENA	; no falta nada: llena
	; falta algo. Si es una fila que se ve y el juego ya la ha repintado, lo
	; que tenia se ha perdido (ver V9_PREPARA): entrando, no se puede pasar
	; a fino todavia
	ld a,(V9_POS)
	ld b,a
	ld a,(V9_NV)
	dec a
	cp b
	jr c,V9_FC_VALE		; oculta
	ld a,(V9_S)
	ld c,a
	call V9_BIT_SUCIA
	jr z,V9_FC_VISIBLE
	ld a,(V9_FINO)
	or a
	jr nz,V9_FC_VISIBLE
	ld (V9_COMPLETA),a
	ret
V9_FC_VISIBLE:
	ld a,1			; si se ve, las tiras hay que copiarlas otra vez
	ld (V9_NUEVAS),a
V9_FC_VALE:
	; De que tercio del atlas se copia. Algunos tiles tienen un dibujo en cada
	; tercio (las lineas del borde de la pista, el cartel de RAYS): el juego
	; cuenta con que se ven en un tercio concreto. Se coge el del tercio en
	; el que esta la fila ahora (0-7 arriba, 8-15 en medio, 16-24 abajo) y,
	; para las ocultas, el de arriba, que es por donde van a entrar.
	ld a,(V9_POS)
	cp 25
	jr c,V9_FC_TERCIO
	xor a
V9_FC_TERCIO:
	cp 24
	jr c,V9_FC_TERCIO2
	ld a,16			; la que asoma por abajo
V9_FC_TERCIO2:
	and 018h		; 8 * tercio
	ld e,a
	add a,PAT_JUEGO
	ld (V9_SYP),a
	ld a,e
	add a,COL_JUEGO
	ld (V9_SYC),a
	; HL = la fila en el buffer E400
	ld a,(V9_S)
	rrca
	rrca
	rrca
	ld l,a
	and 003h
	add a,E_BUFFER_J1 / 256
	ld h,a
	ld a,l
	and 0E0h
	ld l,a
	ld (V9_FILA_RAM),hl
	call V9_CEL_LAZY
	; Toda la fila sin interrupciones y con R#15 = 2: esperar a que acabe
	; un comando es leer el puerto. Son 17 celdas como mucho (unos 9000 T);
	; el VBLANK que llegue mientras espera, no se pierde.
	di
	ld a,2
	out (VDP_CTRL),a
	ld a,080h + 15
	out (VDP_CTRL),a
V9_FC_ESPERA:
	in a,(VDP_CTRL)
	rrca
	jr c,V9_FC_ESPERA
	ld a,(V9_S)		; DX = fila * 8
	add a,a
	add a,a
	add a,a
	out (VDP_CTRL),a
	ld a,080h + 36
	out (VDP_CTRL),a
	ld hl,V9_FALTA
	ld ix,(V9_PVAL)
	ld c,0			; C = columna del mapa
V9_FC_BYTE:
	ld a,(hl)
	or a
	jr z,V9_FC_VACIO
	ld d,001h		; D = el bit de la columna C
V9_FC_BIT:
	rrca
	jr nc,V9_FC_NO
	ex af,af'
	ld a,(V9_PRESUP)
	or a
	jr z,V9_FC_AGOTADO
	dec a
	ld (V9_PRESUP),a
	ld a,(ix+0)
	or d
	ld (ix+0),a		; valida desde ya
	push hl
	ld hl,(V9_FILA_RAM)
	ld a,l
	or c
	ld l,a
	ld a,(hl)		; el tile
	pop hl
	call V9_CELDA
	ex af,af'
V9_FC_NO:
	inc c
	rlc d
	jr nc,V9_FC_BIT		; ocho bits
	jr V9_FC_BYTE_SIGUE
V9_FC_VACIO:
	ld a,c
	add a,8
	ld c,a
V9_FC_BYTE_SIGUE:
	inc hl
	inc ix
	ld a,c
	cp 32
	jr nz,V9_FC_BYTE
	call V9_FC_R15
V9_FC_LLENA:			; hecha entera: a V9_LLENAS
	ld a,(V9_S)
	ld c,a
	call V9_BIT_SUCIA
	ld a,l
	add a,V9_LLENAS - V9_SUCIAS
	ld l,a
	ld a,b
	or (hl)
	ld (hl),a
	ret
V9_FC_AGOTADO:
	call V9_FC_R15		; sin presupuesto: si es de las que se ven (pasada
	ld a,(V9_PASADA)	; 0), queda a medias
	or a
	ret nz
	ld (V9_COMPLETA),a
	ret
V9_FC_R15:
	xor a
	out (VDP_CTRL),a
	ld a,080h + 15
	out (VDP_CTRL),a
	ei
	ret

; A = tile, C = columna del mapa (0..31), sin interrupciones y con R#15 = 2.
; Dos HMMM de 8 x 1: los patrones y los colores del tile (del tercio del
; atlas de V9_SYP/V9_SYC) a la linea 8*fila del mapa. El resto de registros
; ya esta puesto (V9_T_CELDA y DX). NY se gasta en cada comando.
V9_CELDA:
	ld e,a
V9_CEL_ESPERA1:
	in a,(VDP_CTRL)
	rrca
	jr c,V9_CEL_ESPERA1
	ld a,e
	and 01Fh
	add a,a
	add a,a
	add a,a
	out (VDP_CTRL),a
	ld a,080h + 32		; SX = (tile & 31) * 8
	out (VDP_CTRL),a
	ld a,e
	rlca
	rlca
	rlca
	and 007h
	ld e,a			; tile / 32: la fila de la tabla
	ld a,(V9_SYP)
	add a,e
	out (VDP_CTRL),a
	ld a,080h + 34		; SY
	out (VDP_CTRL),a
	ld a,c
	add a,MAPA_PAT & 0FFh
	out (VDP_CTRL),a
	ld a,080h + 38		; DY (el byte alto ya vale 1)
	out (VDP_CTRL),a
	ld a,1
	out (VDP_CTRL),a
	ld a,080h + 42		; NY
	out (VDP_CTRL),a
	ld a,HMMM
	out (VDP_CTRL),a
	ld a,080h + 46
	out (VDP_CTRL),a
V9_CEL_ESPERA2:
	in a,(VDP_CTRL)
	rrca
	jr c,V9_CEL_ESPERA2
	ld a,(V9_SYC)
	add a,e
	out (VDP_CTRL),a
	ld a,080h + 34
	out (VDP_CTRL),a
	ld a,c
	add a,MAPA_COL & 0FFh
	out (VDP_CTRL),a
	ld a,080h + 38
	out (VDP_CTRL),a
	ld a,1
	out (VDP_CTRL),a
	ld a,080h + 42
	out (VDP_CTRL),a
	ld a,HMMM
	out (VDP_CTRL),a
	ld a,080h + 46
	out (VDP_CTRL),a
	ret

; espera a que el VDP acabe el comando: el bit 0 (CE) de S#2. Se llama con
; las interrupciones CERRADAS (R#15 no puede quedarse en 2 si entra una: la
; interrupcion leeria S#2 en vez de S#0) y deja R#15 = 0.
V9_ESPERA:
	ld a,2
	out (VDP_CTRL),a
	ld a,080h + 15
	out (VDP_CTRL),a
V9_ESPERA_B:
	in a,(VDP_CTRL)
	rrca
	jr c,V9_ESPERA_B
	xor a
	out (VDP_CTRL),a
	ld a,080h + 15
	out (VDP_CTRL),a
	ret

; B = valor, C = 0x80 + registro, sin partir
V9_REG:
	di
	ld a,b
	out (VDP_CTRL),a
	ld a,c
	out (VDP_CTRL),a
	ei
	ret

; V9_BLK -> R#32..R#46 (esperando antes a que acabe el comando anterior)
V9_ENVIA:
	di
	call V9_ESPERA
	ld a,32
	out (VDP_CTRL),a
	ld a,080h + 17		; R#17 = 32, con autoincremento
	out (VDP_CTRL),a
	ld hl,V9_BLK
	ld bc,256 * 15 + VDP_IND
	otir
	ei
	ret

; HL = plantilla de 15 bytes -> V9_BLK
V9_BLK_CARGA:
	ld de,V9_BLK
	ld bc,15
	ldir
	ret

; --------------------------------------------------------------------------
; V9_TIRAS: el mapa ya tiene todo lo visible. Tablas propias, filas del HUD
; si hace falta, y las tiras del tercio de arriba (3 grupos x patron y color);
; las de los tercios 1 y 2, V9_TIRAS_RESTO, que el haz tarda mas en llegar.
; Si no ha cambiado nada, ninguna (V9_TIR_PEND = 0).
; --------------------------------------------------------------------------
V9_TIRAS:
	xor a
	ld (V9_TIR_PEND),a
	ld a,(V9_FINO)
	or a
	jr nz,V9_TIR_YA
	inc a			; se entra en modo fino: HUD y nombres de la ventana
	ld (V9_FINO),a
	ld (V9_ESPEJO),a
	ld (V9_NOMBRES),a
	jr V9_TIR_COPIA
V9_TIR_YA:
	; si no ha cambiado nada (camara, columnas, celdas que se ven, HUD), las
	; tiras que hay en las tablas siguen valiendo: con el coche parado no
	; se copia nada
	ld a,(V9_ESPEJO)
	ld hl,V9_NUEVAS
	or (hl)
	jr nz,V9_TIR_COPIA
	ld a,(V9_CAMY)
	ld hl,V9_ULT_CAMY
	cp (hl)
	jr nz,V9_TIR_COPIA
	ld a,(V9_COL0)
	ld hl,V9_ULT_COL0
	cp (hl)
	ret z			; (V9_TIRAS_RESTO pone los registros)
V9_TIR_COPIA:
	ld a,(V9_CAMY)
	ld (V9_ULT_CAMY),a
	ld a,(V9_COL0)
	ld (V9_ULT_COL0),a
	ld a,(V9_ESPEJO)
	or a
	jr z,V9_TIR_TIRAS
	xor a
	ld (V9_ESPEJO),a
	ld hl,V9_T_ESPEJO
	call V9_BLK_CARGA
	ld hl,V9_TABLA_ESPEJO
	ld b,8
V9_TIR_ESPEJO:
	ld a,(hl)
	inc hl
	ld (V9_BLK+2),a		; SY
	ld a,(hl)
	inc hl
	ld (V9_BLK+6),a		; DY
	ld a,(hl)
	inc hl
	ld (V9_BLK+10),a	; NY
	push hl
	push bc
	call V9_ENVIA
	pop bc
	pop hl
	djnz V9_TIR_ESPEJO
V9_TIR_TIRAS:
	ld hl,V9_T_TIRA		; lo que no cambia de un comando a otro
	call V9_BLK_CARGA
	call V9_ENVIA
	ld a,1
	ld (V9_TIR_PEND),a
	ld bc,256 * 0 + 1	; el tercio 0

; B = primer tercio, C = el de despues del ultimo. Los comandos seguidos, sin
; interrupciones y con R#15 = 2: son unos 1.1 ms por tercio, casi todo
; esperando al VDP.
V9_TIR_TERCIOS:
	ld a,c
	ld (V9_TIR_HASTA),a
	di
	ld a,2
	out (VDP_CTRL),a
	ld a,080h + 15
	out (VDP_CTRL),a
V9_TIR_TERCIO:
	push bc
	ld a,b
	rrca
	rrca
	ld c,a			; 64 * tercio
	ld a,(V9_CAMY)
	add a,c
	ld (V9_SX),a		; la linea del mapa que va arriba de este tercio
	ld a,b
	add a,a
	add a,a
	add a,a
	inc a
	ld (V9_DYT),a		; 8 * tercio + 1: la fila de la tabla de la tira 0
	ld b,0			; grupo de cinco columnas
V9_TIR_GRUPO:
	push bc
	ld a,b
	add a,a
	add a,a
	add a,b
	ld c,a
	ld a,(V9_COL0)
	add a,c
	and 01Fh
	ld c,a			; C = primera columna del mapa del grupo
	ld a,b
	rrca
	rrca
	ld e,a			; E = 64 * grupo: la X de la tira en la tabla
	ld hl,256 * (MAPA_PAT & 0FFh) + (PAT_FINO & 0FFh)
	call V9_TIRA
	ld hl,256 * (MAPA_COL & 0FFh) + (COL_FINO & 0FFh)
	call V9_TIRA
	pop bc
	inc b
	ld a,b
	cp 3
	jr nz,V9_TIR_GRUPO
	pop bc
	inc b
	ld a,(V9_TIR_HASTA)
	cp b
	jr nz,V9_TIR_TERCIO
	jp V9_FC_R15		; R#15 = 0 y las interrupciones, abiertas

; los tercios 1 y 2, si V9_TIRAS ha copiado el 0, y el VDP a pintar con las
; tablas propias (siempre: por si alguien las hubiera cambiado). Sin esperar
; al ultimo comando: estos registros no son de los comandos.
V9_TIRAS_RESTO:
	ld a,(V9_TIR_PEND)
	or a
	jr z,V9_TIR_REGS
	xor a
	ld (V9_TIR_PEND),a
	ld bc,256 * 1 + 3
	call V9_TIR_TERCIOS
V9_TIR_REGS:
	ld bc,256 * R3_FINO + 080h + 3
	call V9_REG
	ld bc,256 * R4_FINO + 080h + 4
	call V9_REG
	ld bc,256 * R10_FINO + 080h + 10
	jp V9_REG

; Cinco columnas del mapa, desde la C, a la tabla fina: H = byte bajo de la
; fila Y del mapa (patrones o colores), L = byte bajo de la tabla, E = X de
; la tira. Si las cinco columnas dan la vuelta al mapa, dos trozos. Respeta
; BC y DE, que el que llama las usa otra vez para los colores.
V9_TIRA:
	push bc
	push de
	ld a,(V9_DYT)
	add a,l
	ld l,a			; L = tabla + 8 * tercio + 1
	ld a,32
	sub c			; columnas hasta el final del mapa
	cp 5
	jr nc,V9_TIRA_UNO
	ld b,a
	push bc
	push de
	push hl
	call V9_TROZO
	pop hl
	pop de
	pop bc
	ld a,l
	add a,b
	ld l,a			; lo que falta, en las filas de la tabla que siguen
	ld a,5
	sub b
	ld b,a
	ld c,0			; y desde la columna 0 del mapa
	jr V9_TIRA_ULTIMO
V9_TIRA_UNO:
	ld b,5
V9_TIRA_ULTIMO:
	call V9_TROZO
	pop de
	pop bc
	ret

; B columnas del mapa desde la C, a la fila L de la tabla, X = E. Las 64
; lineas desde V9_SX, en uno o dos HMMM segun den la vuelta a las 256 del
; mapa.
V9_TROZO:
	ld a,(V9_SX)
	ld d,a
	neg			; lineas hasta el final del mapa
	jr z,V9_TROZO_64
	cp 64
	jr nc,V9_TROZO_64
	push af
	call V9_HMMM_TIRA	; esas...
	pop af
	ld d,a
	add a,e
	ld e,a
	ld a,64
	sub d			; ...y las que faltan, desde la linea 0 del mapa
	ld d,0
	jr V9_HMMM_TIRA
V9_TROZO_64:
	ld a,64

; Un HMMM de A (NX) x B (NY) desde (D, H + C) del mapa a (E, L) de la tabla
; (los bytes altos ya estan puestos por V9_T_TIRA). Sin interrupciones y con
; R#15 = 2: espera a que acabe el anterior leyendo el puerto. Solo toca A.
V9_HMMM_TIRA:
	push af
V9_HT_ESPERA:
	in a,(VDP_CTRL)
	rrca
	jr c,V9_HT_ESPERA
	ld a,d
	out (VDP_CTRL),a
	ld a,080h + 32		; SX
	out (VDP_CTRL),a
	ld a,h
	add a,c
	out (VDP_CTRL),a
	ld a,080h + 34		; SY
	out (VDP_CTRL),a
	ld a,e
	out (VDP_CTRL),a
	ld a,080h + 36		; DX
	out (VDP_CTRL),a
	ld a,l
	out (VDP_CTRL),a
	ld a,080h + 38		; DY
	out (VDP_CTRL),a
	pop af
	out (VDP_CTRL),a
	ld a,080h + 40		; NX
	out (VDP_CTRL),a
	ld a,b
	out (VDP_CTRL),a
	ld a,080h + 42		; NY
	out (VDP_CTRL),a
	ld a,HMMM
	out (VDP_CTRL),a
	ld a,080h + 46
	out (VDP_CTRL),a
	ret

; --------------------------------------------------------------------------
; V9_NOMBRES_FINOS: los nombres de la ventana en modo fino son fijos (cada
; celda, el patron de su tira); se escriben al entrar, y en las filas 11-12
; despues de que el HUD pinte encima.
; --------------------------------------------------------------------------
V9_NOMBRES_FINOS:
	ld a,(V9_NOMBRES)
	or a
	jr z,V9_NF_ROTULO
	xor a
	ld (V9_NOMBRES),a
	ld c,0
V9_NF_TODAS:
	call V9_NOMBRES_FILA
	inc c
	ld a,c
	cp 24
	jr nz,V9_NF_TODAS
	jr V9_NF_FIN
V9_NF_ROTULO:
	ld hl,(V9_ROTULO)
	ld a,h
	or l
	ret z
	ld c,11
	call V9_NOMBRES_FILA
	inc c
	call V9_NOMBRES_FILA
V9_NF_FIN:
	ld hl,0
	ld (V9_ROTULO),hl
	ret

; C = fila de la pantalla (0..23)
V9_NOMBRES_FILA:
	ld a,c
	and 007h
	ld e,a			; la fila dentro del tercio: se suma al patron
	rrca
	rrca
	rrca
	or 002h			; columna 2
	ld b,a			; B = byte bajo
	ld a,c
	rrca
	rrca
	rrca
	and 003h
	or 038h + 040h		; 0x3800, escritura
	ld d,a			; D = byte alto
	di
	ld a,b			; primero el bajo...
	out (VDP_CTRL),a
	ld a,d			; ...y luego el alto
	out (VDP_CTRL),a
	ei
	ld hl,V9_NOMBRE_BASE
	ld b,15
V9_NF_BUCLE:
	ld a,(hl)
	add a,e
	out (VDP_DATOS),a
	inc hl
	djnz V9_NF_BUCLE
	ret

; --------------------------------------------------------------------------
; Tablas
; --------------------------------------------------------------------------
	ds (8 - ($ & 7)) & 7, 0FFh	; que no cruce de pagina al sumarle 0..7
V9_MASCARAS:
	db 001h,002h,004h,008h,010h,020h,040h,080h

; el primer patron de la tira de cada columna de la ventana: columna j =
; 5 * grupo + i -> fila 1 + i de la tabla, bloque X = grupo
V9_NOMBRE_BASE:
	db 020h,040h,060h,080h,0A0h
	db 028h,048h,068h,088h,0A8h
	db 030h,050h,070h,090h,0B0h

; R#32..R#46: SX, SY, DX, DY, NX, NY, CLR, ARG, CMD
V9_T_CELDA:	; NX = 8, DY alto = 1; CMD = 0 (solo carga)
	db 0,0, 0,0, 0,0, 0,1, 8,0, 1,0, 0,0, 0
V9_T_ESPEJO:	; filas enteras (NX = 256) del juego a las tablas propias
	db 0,0, 0,0, 0,0, 0,1, 0,1, 1,0, 0,0, HMMM
V9_T_TIRA:	; del mapa (SY alto = 1) a las tablas propias (DY alto = 1); CMD = 0
	db 0,0, 0,1, 0,0, 0,1, 64,0, 5,0, 0,0, 0

; las filas del HUD: (SY, DY, NY). Patrones: la 0 (tile 0) y las 6-7 (0xC0 a
; 0xFF) de cada tercio, agrupadas donde son seguidas; y lo mismo en colores.
V9_TABLA_ESPEJO:
	db PAT_JUEGO + 000h, (PAT_FINO & 0FFh) + 000h, 1
	db PAT_JUEGO + 006h, (PAT_FINO & 0FFh) + 006h, 3
	db PAT_JUEGO + 00Eh, (PAT_FINO & 0FFh) + 00Eh, 3
	db PAT_JUEGO + 016h, (PAT_FINO & 0FFh) + 016h, 2
	db COL_JUEGO + 000h, (COL_FINO & 0FFh) + 000h, 1
	db COL_JUEGO + 006h, (COL_FINO & 0FFh) + 006h, 3
	db COL_JUEGO + 00Eh, (COL_FINO & 0FFh) + 00Eh, 3
	db COL_JUEGO + 016h, (COL_FINO & 0FFh) + 016h, 2

V9_FIN_P16:

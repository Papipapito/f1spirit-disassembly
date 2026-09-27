; ==========================================================================
; F-1 SPIRIT con scroll suave para V9968 - la parte de la RAM
; ==========================================================================
; Se ensambla en 0xF100 y V9_ARRANQUE (parche.asm, pagina 15) la copia ahi
; al arrancar, antes de que se abran las interrupciones. Son las rutinas que
; tienen que poder llamarse con CUALQUIER pagina mapeada: los ganchos de la
; pagina 0 saltan aqui. Cabe en 384 bytes (hasta 0xF27F); las variables van
; en 0xF280.
; ==========================================================================

	include "v9968/comun.asm"

	org V9_RAM_CODIGO

; --------------------------------------------------------------------------
; V9R_GRUESO: vuelve a las tablas del juego si el VDP estaba pintando con las
; propias (modo fino). Es lo que hacen todos los ganchos que anuncian que
; la pantalla va a cambiar. Respeta todos los registros y el estado de las
; interrupciones.
; --------------------------------------------------------------------------
V9R_GRUESO:
	push af
	ld a,(V9_FINO)
	or a
	jr z,V9R_GRUESO_FIN
	push bc
	xor a
	ld (V9_FINO),a
	ld a,i			; P/V = IFF2: si las interrupciones estaban abiertas
	push af
	di			; los dos `out` de cada registro no se pueden partir
	ld bc,256 * R3_JUEGO + 080h + 3
	call V9R_REG
	ld bc,256 * R4_JUEGO + 080h + 4
	call V9R_REG
	ld bc,256 * R10_JUEGO + 080h + 10
	call V9R_REG
	pop af
	pop bc
	jp po,V9R_GRUESO_FIN
	ei
V9R_GRUESO_FIN:
	pop af
	ret

; B = valor, C = 0x80 + registro
V9R_REG:
	ld a,b
	out (VDP_CTRL),a
	ld a,c
	out (VDP_CTRL),a
	ret

; --------------------------------------------------------------------------
; V9R_LEJOS: llama a la rutina HL de la pagina 16 con la 16 puesta en 0x6000,
; y al volver deja la que hubiera. El mapper y su sombra (F0F1) se cambian
; juntos y sin interrupciones por medio, como hace el juego (0x43FE): la
; interrupcion guarda la sombra y la restaura al salir.
; --------------------------------------------------------------------------
V9R_LEJOS:
	ld a,(SOMBRA_6000)
	push af
	ld b,PAGINA_V9
	call V9R_MAPEA_6000
	call V9R_JP_HL
	pop af
	ld b,a
V9R_MAPEA_6000:			; B = pagina para 0x6000; respeta el IFF
	ld a,i
	di
	ld a,b
	ld (MAPPER_6000),a
	ld (SOMBRA_6000),a
	ret po
	ei
	ret
V9R_JP_HL:
	jp (hl)

; --------------------------------------------------------------------------
; 0x4046, en lugar de `call SONIDO_PASO`. Con un VDP con comandos en G2 el
; repintado (sprites, ventana y HUD) va aqui, ANTES del sonido: al principio
; del VBLANK, para que todo este en la VRAM antes de que el haz empiece a
; dibujar la ventana (si no, las tiras de arriba se copian mientras se ven y
; la imagen sale cortada). El sonido se retrasa unos ms en esas
; interrupciones. Las condiciones son las de 0x4056: sin logica en curso.
; --------------------------------------------------------------------------
V9R_SONIDO:
	ld a,(V9_CAPS)
	or a
	jp z,SONIDO_PASO
	ld a,(E_CANDADOS)
	rrca
	call nc,V9R_REPINTA_YA
	jp SONIDO_PASO
V9R_REPINTA_YA:
	ld a,1
	ld (V9_HECHO),a

; el repintado de siempre, con el vigilante (pagina 16) si el modo fino esta
; puesto
V9R_REPINTA:
	ld a,(V9_FINO)
	or a
	ld hl,P16_VIGILA
	call nz,V9R_LEJOS
	jp REPINTA_PENDIENTE

; 0x405A, en lugar de `call nc,REPINTA_PENDIENTE`: si el repintado ya se ha
; hecho antes del sonido, lo que el renderer deja para despues (columna de
; margen y filas ocultas); si no, el repintado, aqui como siempre
V9R_REPINTA_405A:
	ld hl,V9_HECHO
	ld a,(hl)
	or a
	jr z,V9R_REPINTA
	ld (hl),0
	ld a,(V9_EN_VENTANA)	; ha pasado por el renderer...
	or a
	ret z
	ld a,(V9_FINO)		; ...y esta en fino
	or a
	ret z
	ld hl,P16_FONDO
	jp V9R_LEJOS

; --------------------------------------------------------------------------
; 0x40B5, la salida de la interrupcion, en lugar de `call RDVDP`. El juego
; pierde una interrupcion (ni sonido ni reloj F0FC) si le llega mientras el
; candado del bit 1 de E1C5 esta puesto, o si su VBLANK cae con las
; interrupciones cerradas y se lo come este RDVDP. Con un repintado corto
; no pasa nunca; con el renderer, que puede tardar casi un fotograma, si.
; Si esta interrupcion (o la de fuera) ha pasado por el renderer, la pagina
; 15 recupera esa interrupcion (V9_ANIDADA). B = S#0 para ella.
; --------------------------------------------------------------------------
V9R_ANIDADA:
	ld a,(V9_EN_VENTANA)
	or a
	jp z,RDVDP		; lo de siempre, casi gratis: pasa en cada interrupcion
	call RDVDP
	push af
	ld b,a
	ld a,00Fh		; la 15 en 0xA000...
	ld (MAPPER_A000),a
	call P15_ANIDADA
	ld (MAPPER_A000),a	; ...y lo que diga ella
	pop af
	ret

; 0x4513, la ventana de un jugador, con `jp`
V9R_VENTANA:
	ld a,(V9_CAPS)
	or a
	ld hl,P16_VENTANA_1J
	jr nz,V9R_LEJOS
	ld ix,0E2C0h		; sin VDP que valga, lo de siempre
	jp VENTANA_1J_SIGUE

; --------------------------------------------------------------------------
; Los ganchos: cada uno hace lo suyo y luego la instruccion que tapa el
; `call`/`jp` puesto en la pagina 0.
; --------------------------------------------------------------------------

; 0x44DF VENTANA_JUGADOR_2 (escenas fijas, boxes y repeticion), con `jp`
V9R_H_VJ2:
	call V9R_GRUESO
	ld iy,0E380h
	jp G_VENTANA_J2_SIGUE

; 0x4538 VENTANA_2_JUGADORES (pantalla partida), con `call`
V9R_H_V2J:
	call V9R_GRUESO
	ld a,(00007h)
	ret

; 0x44C4 VUELCA_768_A_NOMBRES (pantallas enteras desde E400/EC00), con `jp`
V9R_H_VUELCA:
	call V9R_GRUESO
	push hl
	ld hl,03800h
	jp G_VUELCA_768_SIGUE

; 0x44F3 BORRA_VENTANA_PISTA, con `call` y dos `nop`
V9R_H_BORRA_VENT:
	call V9R_GRUESO
	ld b,018h
	ld hl,03802h
	ret

; 0x465B BORRA_SPRITES_Y_NOMBRES (el principio de casi todas las pantallas),
; con `call` y dos `nop`
V9R_H_BORRA_SPR:
	call V9R_GRUESO
	ld a,0E0h
	ld hl,0EA80h
	ret

; 0x49C7 CORTINILLA_COLUMNA (la cortinilla que borra la pantalla), con `call`
V9R_H_CORTINILLA:
	call V9R_GRUESO
	ld hl,0E1C4h
	ret

; 0x4CD1 CARGA_LISTA_TILES_MODO: el cargador de tiles va a escribir patrones
; o colores (todas las listas pasan por aqui, una vez por lista). El mapa de
; la pista hecho con los tiles de antes ya no vale. `ld (nn),sp` deja la
; marca sin tocar ningun registro (SP nunca vale 0). Con `call`.
V9R_H_LISTA:
	ld (V9_TILES),sp
	push hl
	pop ix
	ret

; 0x491B HUD_CASILLA_DEL_JUGADOR: el HUD pinta un numero o un rotulo en las
; filas 11-12, encima de la ventana. En modo fino hay que borrarlo en el
; siguiente repintado, como hacia el volcado original. Con `call`.
V9R_H_ROTULO:
	ld (V9_ROTULO),sp
	ld hl,03965h
	ret

; 0x56D4 el final de PINTA_FILA_PISTA (`jp MAPEA_1_2_3`), con `jp`. IX es el
; coche. Lo que haya que apuntar lo decide V9_FILA (pagina 16).
V9R_H_FILA:
	ld a,(V9_CAPS)
	or a
	jp z,MAPEA_1_2_3
	ld a,(ix+009h)		; solo el buffer del jugador 1 (E400): el resto,
	dec a			; sin pasar por la pagina 16
	jp nz,MAPEA_1_2_3
	ld a,(V9_TILES+1)	; con tiles nuevos se va a rehacer todo el mapa: no
	or a			; hace falta apuntar nada (pasa en las cargas, que
	jp nz,MAPEA_1_2_3	; pintan el buffer entero)
	push hl
	push de
	push bc
	ld hl,P16_FILA
	call V9R_LEJOS
	pop bc
	pop de
	pop hl
	jp MAPEA_1_2_3

; 0x4701 TILES_OBJETO_PISTA: el juego carga ahora los patrones del objeto que
; puso en la pista en el paso anterior (tiles 206/207 del jugador 1). Las
; filas donde esta ya se rellenaron con los de antes: a rehacer (pagina 16).
; Con `call` y un `nop`; A es el dibujo y hay que devolverlo.
V9R_H_OBJETO:
	ld (ix-003h),000h
	push af
	ld a,(V9_OBJ)
	or a
	ld hl,P16_OBJETO
	call m,V9R_LEJOS
	pop af
	ret

V9R_FIN:

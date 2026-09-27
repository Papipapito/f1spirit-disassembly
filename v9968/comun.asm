; ==========================================================================
; F-1 SPIRIT con scroll suave para V9968 - definiciones comunes
; ==========================================================================
; Lo incluyen ram.asm y parche.asm. Todas las direcciones del juego que se
; usan estan aqui, con el nombre que tienen en src/f1spirit_p00.asm, y
; tests/test_v9968.py comprueba que cada una sigue apuntando a la etiqueta
; o a la instruccion que dice su comentario.
; ==========================================================================

; --------------------------------------------------------------------------
; El juego: rutinas de la pagina 0 (fija en 0x4000)
; --------------------------------------------------------------------------
REPINTA_PENDIENTE	equ 040BBh	; sprites, ventana de la pista y rotulos
MAPEA_1_2_3		equ 043FEh	; 1/2/3 en 6000/8000/A000, respeta HL y acaba en `ei`
VENTANA_1J_SIGUE	equ 04517h	; lo que sigue al `ld ix,0E2C0h` de 0x4513
VACIA_COLA_SONIDO	equ 04140h	; las ordenes de sonido pendientes (p13 0x6000)
CUENTA_ATRAS_F0F7	equ 04155h	; la cuenta atras de tiempo real, una por interrupcion
BUSCA_CONSOLA		equ 0BF50h	; p15: la busqueda de otros cartuchos que llama INIT
SONIDO_PASO		equ 06AA5h	; p13: el paso del reproductor (0x4046)
SONIDO_6422		equ 06422h	; p13: PSG R7, fundido y canales (0x4061)
RDVDP			equ 0013Eh	; BIOS: lee S#0

; Los sitios donde se engancha el parche (ver parche.asm): la instruccion
; original que se desplaza y a donde se vuelve.
G_BORRA_RAM		equ 04117h	; ld hl,0E000h / ld de,0E001h / ld bc,010FFh / ld (hl),0 / ldir
G_BORRA_RAM_SIGUE	equ 04124h
G_INIT			equ 04138h	; call 0BF50h
G_SALIDA_INT		equ 040B5h	; call RDVDP (la salida de la interrupcion)
G_REPINTA		equ 0405Ah	; call nc,REPINTA_PENDIENTE
G_SONIDO		equ 04046h	; call SONIDO_PASO
G_VENTANA_1J		equ 04513h	; ld ix,0E2C0h (4 bytes)
G_VENTANA_J2		equ 044DFh	; ld iy,0E380h (4 bytes)
G_VENTANA_J2_SIGUE	equ 044E3h
G_VENTANA_2J		equ 04538h	; ld a,(00007h)
G_VUELCA_768		equ 044C4h	; push hl / ld hl,03800h (4 bytes)
G_VUELCA_768_SIGUE	equ 044C8h
G_BORRA_VENTANA		equ 044F3h	; ld b,018h / ld hl,03802h (5 bytes)
G_BORRA_SPRITES		equ 0465Bh	; ld a,0E0h / ld hl,0EA80h (5 bytes)
G_CORTINILLA		equ 049C7h	; ld hl,0E1C4h
G_CASILLA_HUD		equ 0491Bh	; ld hl,03965h
G_LISTA_TILES		equ 04CD1h	; push hl / pop ix (CARGA_LISTA_TILES_MODO)
G_FILA_PISTA_FIN	equ 056D4h	; jp MAPEA_1_2_3
G_OBJETO		equ 04701h	; ld (ix-003h),000h (4 bytes; TILES_OBJETO_PISTA)

; --------------------------------------------------------------------------
; El juego: variables
; --------------------------------------------------------------------------
E_ESTADO		equ 0E1C0h	; 2 = demo, 5 = carrera
E_CANDADOS		equ 0E1C5h	; bit 1: interrupcion en curso; bit 0: logica en curso
RELOJ_INT		equ 0F0FCh	; interrupciones desde el ultimo paso de logica
E_SUBESTADO		equ 0E250h	; 0x0B = carrera, 0x16 = pausa (bit 7 fuera)
E_CAMARA_Y		equ 0E300h	; (E2C0+0x40): la fila de pista, en pixeles
E_CAMARA_X		equ 0E314h	; (E2C0+0x54): la columna de la ventana, en pixeles
E_BUFFER_J1		equ 0E400h	; el mapa circular de 32 x 32 del jugador 1

; --------------------------------------------------------------------------
; El VDP: el de la maquina, en 0x98 (un V9968 en lugar del V9958 de un
; MSX2+). El puerto 4 (0x9C) solo existe en el V9968. El V9968 en cartucho
; (puertos 0x88-0x8C) no esta soportado: habria que cambiar todos los `out`.
; --------------------------------------------------------------------------
VDP_DATOS		equ 098h
VDP_CTRL		equ 099h
VDP_IND			equ 09Bh
VDP_PUERTO4		equ 09Ch

HMMM			equ 0D0h
LMMM			equ 090h	; con la operacion IMP

; las copias de R#0 y R#1 que guarda la BIOS
RG0SAV			equ 0F3DFh
RG1SAV			equ 0F3E0h

; --------------------------------------------------------------------------
; La VRAM. Las tablas del juego (colores en 0x0000, patrones en 0x2000,
; nombres en 0x3800) no se tocan: son el ATLAS del que salen los tiles. En
; modo fino el VDP pinta con tablas propias en los 64 KB altos. Las
; coordenadas son las de los comandos con R#25 CMD=1: 256 bytes por fila,
; o sea Y = direccion / 256.
; --------------------------------------------------------------------------
PAT_JUEGO		equ 020h	; 0x2000
COL_JUEGO		equ 000h	; 0x0000
PAT_FINO		equ 0120h	; 0x12000: patrones propios (3 tercios)
COL_FINO		equ 0100h	; 0x10000: colores propios
MAPA_PAT		equ 0140h	; 0x14000: el mapa de pista, una fila Y por columna
MAPA_COL		equ 0160h	; 0x16000: y sus colores

R3_FINO			equ 07Fh	; colores en 0x10000 (A16 va en R#10)
R4_FINO			equ 027h	; patrones en 0x12000, con las dos mascaras
R10_FINO		equ 004h
R3_JUEGO		equ 07Fh	; los del juego (tabla de 0x4328) ...
R4_JUEGO		equ 007h
R10_JUEGO		equ 000h	; ... y R#10, que un MSX1 no tiene

; --------------------------------------------------------------------------
; La pagina nueva. La ROM parcheada mide 256 KB: las 16 paginas del juego y
; detras la 16, con el renderer, que se mapea en 0x6000 (como las paginas
; 1, 4, 7, 10 y 13) solo mientras se usa, por medio de V9R_LEJOS (RAM). Sus
; entradas empiezan por una tabla de saltos fija, para que la RAM las
; conozca sin depender del ensamblado de la pagina.
; --------------------------------------------------------------------------
PAGINA_V9		equ 16
MAPPER_6000		equ 07000h	; escribir aqui pone una pagina en 0x6000
MAPPER_8000		equ 09000h
MAPPER_A000		equ 0B000h
SOMBRA_6000		equ 0F0F1h	; y el juego lo apunta aqui (0x43FE)
SOMBRA_8000		equ 0F0F2h
SOMBRA_A000		equ 0F0F3h
P15_ANIDADA		equ 0BC84h	; jp V9_ANIDADA: lo primero del hueco de la pagina 15
P16_VENTANA_1J		equ 06000h	; jp V9_VENTANA_1J
P16_VIGILA		equ 06003h	; jp V9_VIGILA
P16_DETECTA		equ 06006h	; jp V9_DETECTA
P16_FILA		equ 06009h	; jp V9_FILA
P16_OBJETO		equ 0600Ch	; jp V9_OBJETO
P16_FONDO		equ 0600Fh	; jp V9_CELDAS_FONDO

; --------------------------------------------------------------------------
; La RAM del parche: 0xF100-0xF37F, hasta la zona de la BIOS (0xF380). INIT
; borraba 0xE000-0xF0FF; el parche alarga ese borrado hasta 0xF37F y copia
; aqui su codigo en el mismo sitio (0x4117), antes de que se abran las
; interrupciones. La pila del juego empieza en 0xF0F0 y crece hacia abajo.
; --------------------------------------------------------------------------
V9_RAM_CODIGO		equ 0F100h	; el codigo de ram.asm (hasta 0xF27F)

V9_CAPS			equ 0F280h	; bit 0: VDP con comandos en G2; bit 1: V9968
V9_FINO			equ 0F281h	; 1 = el VDP esta pintando con las tablas propias
V9_TILES		equ 0F282h	; (2) <> 0: el cargador ha escrito tiles
V9_ROTULO		equ 0F284h	; (2) <> 0: el HUD ha pintado en la fila 11/12
V9_ESPEJO		equ 0F286h	; 1 = copiar las filas del HUD al entrar
V9_NOMBRES		equ 0F287h	; 1 = reescribir la ventana entera
V9_COL0			equ 0F288h	; columna del mapa de la izquierda de la ventana (0..31)
V9_FILA0		equ 0F289h	; fila de arriba (0..31) de este repintado
V9_FASE			equ 0F28Ah	; camara Y & 7
V9_NV			equ 0F28Bh	; filas visibles: 24, o 25 si FASE <> 0
V9_PRESUP		equ 0F28Ch	; celdas que quedan en este repintado
V9_COMPLETA		equ 0F28Dh	; 0 si falta algo de lo visible
V9_CAMY			equ 0F28Eh
V9_POS			equ 0F28Fh	; posicion en la ventana de la fila que se rellena
V9_SUCIAS		equ 0F290h	; (4) filas que el juego ha repintado
V9_VIS			equ 0F294h	; (4) las 15 columnas que se ven y una mas a cada lado
V9_LLENAS		equ 0F298h	; (4) filas del mapa con todas las columnas de V9_VIS
V9_FALTA		equ 0F29Ch	; (4) las columnas que le faltan a la fila que se rellena
V9_PVAL			equ 0F2A0h	; (2) sus bits en V9_VALIDAS
V9_COL_NUEVA		equ 0F2A2h	; la columna de margen que ha entrado (0xFF: ninguna)
V9_FILA_RAM		equ 0F2B6h	; (2) la fila del buffer E400 que se rellena
V9_SX			equ 0F2B8h	; linea del mapa de arriba del tercio
V9_DYT			equ 0F2B9h	; 8 * tercio + 1
V9_SYP			equ 0F2BAh	; fila (Y) de patrones del atlas: la del tercio...
V9_SYC			equ 0F2BBh	; ...y la de colores, segun donde este la celda
V9_ULTIMA		equ 0F2BCh	; (3) la ultima fila pintada: fila, pieza y fila de pieza
V9_ULT_CAMY		equ 0F2BFh	; camara Y de las tiras que hay en las tablas
V9_ULT_COL0		equ 0F2D4h	; columna de la ventana de esas tiras
V9_NUEVAS		equ 0F2D5h	; 1 si en este repintado se ha rellenado algo visible
V9_S			equ 0F2D6h	; la fila del mapa que se rellena
V9_PASADA		equ 0F2D7h	; 0: filas que se ven, 1: ocultas
V9_FALTAN		equ 0F2D8h	; las filas no llenas del byte que se recorre
V9_EN_VENTANA		equ 0F2D9h	; <> 0: se esta repintando (ahi el sonido no esta a medias)
V9_TICS			equ 0F2DAh	; interrupciones recuperadas que aun no estan en F0FC
V9_OBJ			equ 0F2DBh	; 0x80 + fila del mapa de un objeto sin sus patrones
V9_HECHO		equ 0F2DCh	; 1: repintado antes del sonido; 2: y en fino (falta el fondo)
V9_REGS_CELDA		equ 0F2DDh	; 1: los registros fijos de celda ya estan en el VDP
V9_TIR_PEND		equ 0F2DEh	; 1: faltan las tiras de los tercios 1 y 2
V9_TIR_HASTA		equ 0F2DFh	; el tercio en el que para V9_TIR_TERCIOS
V9_ANTICIPO		equ 0F2E0h	; 1: V9_ANTES ya ha hecho lo suyo (2: y sale gruesa)
V9_PEND			equ 0F2E1h	; interrupciones recuperadas que aun no han sonado
V9_EN_TIC		equ 0F2E2h	; 1: V9_TICS_PENDIENTES en marcha (no se reentra)
V9_COPIA		equ 0F2E3h	; el comando de las copias: HMMM, o LMMM si HMMM salta bytes
V9_BLK			equ 0F2C0h	; (15) registros R#32..R#46 para `otir`
V9_VALIDAS		equ 0F300h	; (128) 32 filas x 32 bits: celdas del mapa al dia

N_ENTRADA		equ 40		; celdas por repintado mientras se entra
N_ADELANTO		equ 20		; celdas por repintado para las filas ocultas

; Opcion: 16 sprites por linea en el V9968 (R#20 S16). Con 1 desaparece el
; parpadeo de sprites de mas de cuatro en una linea.
V9968_S16		equ 1

; Opcion: modo fino tambien con un V9958 (MSX2+, turboR). Funciona, pero sin
; los comandos rapidos del V9968 la carrera va a unos 12 pasos por segundo en
; vez de 20. Con 0, un V9958 se queda con el scroll de siempre. Se puede dar
; desde fuera (`tools/parchea_v9968.py --v9958`, que pasa --equ a pasmo).
	if defined V9958_FINO
	else
V9958_FINO		equ 0
	endif

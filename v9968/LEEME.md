# F-1 Spirit con scroll suave para el V9968

Un parche para F-1 Spirit (Konami, 1987) que usa el **V9968** (el VDP
compatible con el V9958 de HRA!) para que el fondo de la pista se mueva
**pixel a pixel** en vez de a saltos de 8 pixeles. La logica del juego no se
toca: en la demo, la carrera va paso a paso igual que el original.

![El fondo en 11 pasos seguidos: arriba el original, abajo con el V9968](comparacion.png)

## Construir y probar

Hace falta `f1spirit.rom` en la raiz (la original, sha256 `3b9afd12...96a7`),
`python3` y `pasmo`:

    make v9968        # -> f1spirit_v9968.rom (256 KB)
    python3 -m unittest tests.test_v9968 -v

La ROM parcheada mide **256 KB** (la original, 128): lleva una pagina nueva.
Sigue siendo un MegaROM con el mapper Konami SCC; en openMSX hay que decirlo
(`-romtype KonamiSCC`), porque la base de datos no la conoce.

Para verla en openMSX hace falta un emulador con el V9968: el fork de buppu3
(`https://github.com/buppu3/openMSX`, probado en `24d261cb`). En
`v9968/openmsx/` esta la maquina que se ha usado, un MSX2+ con C-BIOS y el
V9968 en lugar del V9958 (copiala a `share/machines/`):

    openmsx -machine CBIOS_MSX2P_V9968 -cart f1spirit_v9968.rom -romtype KonamiSCC

En cualquier otra maquina la ROM parcheada funciona como la original:
comprobado en MSX1, MSX2 (V9938) y MSX2+ (V9958) con la demo, paso a paso
(camara, coche del jugador y estado del juego iguales) y al mismo ritmo: los
ganchos cuestan algun ciclo y algun paso sale uno o unos pocos fotogramas
antes o despues, pero la carrera acaba a la vez.

**Vista previa sin el V9968.** Para ver el scroll en cualquier emulador de
MSX2+ (openMSX de siempre, por ejemplo):

    make v9968-v9958   # -> f1spirit_v9968_v9958.rom
    openmsx -machine C-BIOS_MSX2+ -cart f1spirit_v9968_v9958.rom -romtype KonamiSCC

Con un V9958 el modo fino funciona, pero la carrera va a unos 12 pasos por
segundo en vez de 20: sirve para verlo, no para jugar.

**En un MSX de verdad con el cartucho V9968.** El cartucho tiene un
conmutador de puertos: 88h (el normal) o 98h. Este parche solo usa el V9968
en 98h, y su manual avisa de que 98h **solo** se puede poner si el VDP del
propio MSX esta desactivado: con los dos en 98h el MSX se puede estropear.
Con el cartucho en 88h, la ROM funciona como la original con el VDP del MSX.

## Que se ve

- **Scroll vertical fino** en la ventana de la pista con un jugador. El
  horizontal sigue siendo por columnas, como en el original.
- **16 sprites por linea** (bit S16 del V9968): menos parpadeo cuando se
  juntan coches. Se quita con `V9968_S16 equ 0` en `comun.asm`.
- La imagen se actualiza sin cortes: las tiras de cada tercio estan en la
  VRAM antes de que el haz llegue a el (el de arriba, en mas del 90 % de los
  repintados; los otros dos, casi siempre).
- Todo lo demas (menus, boxes, repeticion, pantalla partida de dos jugadores)
  va como siempre.

## Como funciona

La ventana de la pista son 15 x 24 tiles que el juego copia de un buffer
circular de 32 x 32 (E400) a la tabla de nombres. La camara (E300) va pixel a
pixel, pero el fondo solo se puede mover de 8 en 8. El registro de scroll
vertical (R#23) no vale: moveria tambien el marcador, que esta al lado.

**Tiras.** En modo fino cada columna de la ventana, en cada tercio de la
pantalla, tiene ocho patrones propios y seguidos: 64 bytes que son 64 lineas
de pixeles de esa columna. Con R#25 CMD = 1 los comandos del VDP funcionan en
SCREEN 2 con coordenadas de SCREEN 8, y esos 64 bytes son un rectangulo de
64 x 1. Un **mapa de la pista** en la VRAM alta guarda cada columna del buffer
(256 lineas) en una fila de 256 bytes; hacer scroll es copiar con HMMM desde
la linea que diga la camara: 18 comandos por repintado (3 tercios x 3 grupos
de 5 columnas x patrones y colores). La tabla de nombres de la ventana queda
fija.

**Celdas.** El mapa se rellena tile a tile (dos HMMM de 8 x 1 por celda)
desde las tablas del juego, que no se tocan nunca y hacen de **atlas**. Solo
cuando hace falta: al entrar en la carrera (40 celdas por repintado, con el
scroll de siempre mientras tanto), cuando el juego pinta una fila nueva (se
rellena mientras esta oculta, antes de que entre) y cuando la ventana se
mueve una columna (cada fila lleva una columna de margen a cada lado, asi que
la que entra ya esta; solo falta la nueva de margen). Lo que el juego repinta
en una fila que aun se ve (la de abajo del todo) se aplaza hasta que deja de
verse.

**VRAM.**

| | |
|---|---|
| 0x00000-0x03FFF | las tablas del juego: el atlas (sin tocar) |
| 0x10000-0x117FF | colores propios (R#3 = 0x7F, R#10 = 0x04) |
| 0x12000-0x137FF | patrones propios (R#4 = 0x27) |
| 0x14000-0x15FFF | el mapa: patrones, una fila de 256 bytes por columna del buffer |
| 0x16000-0x17FFF | el mapa: colores |

Las filas de patrones que usa el marcador (0x00-0x1F y 0xC0-0xFF) se copian
del juego a las tablas propias al entrar en modo fino.

**El tiempo.** El juego da un paso de logica cada tres interrupciones (el
contador F0FC) y repinta dentro de la interrupcion; el original tarda poco y
el renderer bastante mas. Para que el ritmo sea el mismo:

- Con el V9968, el repintado (sprites, ventana y marcador) se hace al
  principio de la interrupcion, **antes del sonido** (0x4046), y las tiras del
  tercio de arriba incluso antes que los sprites (`V9_ANTES`). El sonido se
  retrasa unos milisegundos en esas interrupciones.
- Lo que no se ve (filas ocultas, columna de margen) va despues del sonido
  (0x405A).
- Una interrupcion que llega mientras se repinta no se pierde: el juego la
  despacharia sin sonido y sin contarla; en su salida (0x40B5) se cuenta en
  el reloj, con cuidado de que el `F0FC = 0` de cada paso no se la coma, y
  se hace su paso de sonido (`V9_ANIDADA`). Si ha cortado al reproductor de
  sonido a medias (que llama a WRTPSG, y esta rutina de la BIOS abre las
  interrupciones), su sonido se aplaza a la salida de la interrupcion de
  fuera: el reproductor nunca se ejecuta dos veces a la vez.

**Deteccion.** Al arrancar se mira la version de MSX (2 o mas), el ID del VDP
(S#1) y, con R#21 V58 = 0, si es un V9968 (ID 3). Solo entonces se pone el
modo fino, con los comandos rapidos (R#20 HS) y S16. Con un V9958 no da
tiempo: la carrera bajaria a unos 12 pasos por segundo en vez de 20, asi que
se queda con el scroll de siempre (`V9958_FINO equ 1` en `comun.asm` para
probarlo igualmente).

**Autotest.** Antes de dar por bueno el VDP se prueba una copia de verdad:
4 bytes de 0x1F000 a 0x1F100 en G2 con CMD = 1 (los registros de modo se
cambian un momento, con la pantalla apagada), y que 0x0F100 no cambie (128 KB
de VRAM). Hace falta porque el V9968 de HRA! (su RTL, al menos hasta
`cbe1528`, septiembre de 2026, y el MSXimus, que lo lleva) tiene un fallo: fuera
de los modos de mapa de bits, HMMM, HMMV, YMMM y HMMC avanzan **dos bytes por
paso** (`w_next` de `vdp_command.v` solo mira si el modo es G7), asi que copian
un byte si y otro no. LMMM va de byte en byte y ahi copia bien. El autotest
prueba HMMM y, si salta bytes, LMMM; el comando que vale queda en `V9_COPIA`
y es el que usan las celdas, las tiras y el HUD. Si no va ninguno, el VDP se
deja como estaba y el juego va con el scroll de siempre.

## Donde esta cada cosa

| | |
|---|---|
| `v9968/comun.asm` | direcciones del juego, ganchos, VRAM, RAM y opciones |
| `v9968/ram.asm` | lo que va en RAM (0xF100): los ganchos de la pagina 0 y el cambio de pagina |
| `v9968/parche.asm` | los ganchos sobre la pagina 0, la pagina 15 (arranque y recuperacion de interrupciones) y la pagina 16 nueva (el renderer) |
| `tools/parchea_v9968.py` | monta la ROM y comprueba que nada cambia fuera de las zonas declaradas |
| `tests/test_v9968.py` | cada direccion de `comun.asm` contra el listado, y la ROM montada |

La ROM: la pagina 0 lleva 16 ganchos de 3 a 5 bytes (cada uno tapa una
instruccion que se rehace fuera); el hueco a 0xFF de la pagina 15
(0xBC84-0xBF4F) lleva el arranque, la recuperacion de interrupciones y la
imagen de la RAM; la pagina 16 (nueva, se mapea en 0x6000 solo mientras se
usa) lleva el renderer. La RAM del parche va de 0xF100 a 0xF37F: el juego usa
hasta 0xF0FF y la BIOS empieza en 0xF380.

## Como se ha comprobado

Todo en el emulador (el fork de openMSX), con la demo del juego:

- **Logica**: la RAM del juego (0xE1C0-0xEFFF) en cada paso, contra la ROM
  original en la misma maquina: identica en todos (solo cambia el estado del
  reproductor de sonido, 0xE000-0xE1BF, y su cola de ordenes, porque el paso
  de sonido cae en otro momento). El marcador y la tabla de sprites en la
  VRAM, identicos tambien.
- **Imagen**: la ventana que muestra el VDP, pixel a pixel, contra la que
  sale del buffer E400 y la camara: 267.542 lineas de tile bien y ninguna
  mal en dos carreras de la demo (un 1,5 % tiene la variante de otro tercio,
  ver abajo).
- **Ritmo**: 20 pasos por segundo, como el original, con algun segundo de 18
  o 19 en las curvas mas cerradas. En la carrera de la demo (unos 30 s) llega
  a la meta unos 0,35 s despues que el original.
- **Estabilidad**: 200 s de demo seguidos sin cuelgues, con la pila en su
  sitio (nunca por debajo de 0xF086). La vista previa con V9958, 140 s.
- **Autotest**: con el fork tal cual elige HMMM; con el fallo de HRA emulado
  (`OPENMSX_HRA_G2_QUIRK=1`), LMMM, y la carrera sale igual: 111.765 lineas
  de tile bien y ninguna mal, y la logica identica paso a paso (1.483 pasos).
  Con un V9958 (vista previa) elige HMMM; en un MSX2 no llega a probar nada.
  Si no copia bien ningun comando (forzado desde el depurador), el VDP vuelve
  a como estaba (R#20, R#25 y R#14 a 0) y la demo va con el scroll de siempre.

## Limitaciones

- **Solo V9968 en el sitio del VDP** (puertos 0x98-0x9C). El V9968 en
  cartucho (0x88) no esta soportado.
- **Un jugador**: la pantalla partida de dos jugadores, las escenas fijas,
  los boxes y la repeticion van con el scroll de siempre.
- **Tiles con un dibujo por tercio.** En SCREEN 2 cada tercio de la pantalla
  tiene sus propios patrones, y el juego usa eso en algunos tiles (las
  lineas del borde de la pista, el cartel de RAYS): el mismo numero de tile
  se ve distinto arriba, en medio y abajo. Con scroll fino una fila pasa de un
  tercio a otro poco a poco, asi que se queda con el dibujo del tercio en el
  que se relleno (el de arriba, por donde entran las filas): son uno o dos
  pixeles distintos en la primera o la ultima linea de esos tiles.
- **Sonido**: en las interrupciones en las que se repinta (una de cada
  tres), el paso del reproductor llega hasta unos 7 ms mas tarde. No se ha
  comprobado de oido.
- **Probado en emulacion y en simulacion del RTL.** El fork emula un V9968
  que copia bien con HMMM; con la variable `OPENMSX_HRA_G2_QUIRK` (un parche
  de pruebas al fork) salta bytes como el RTL de HRA!, y el autotest elige
  LMMM. El motor de comandos del RTL (`vdp_command.v` y su cache) se ha
  simulado con iverilog: HMMM copia la mitad de los bytes y LMMM todos, en
  las celdas, las tiras (tambien las partidas, de ancho impar) y el HUD. En
  esa simulacion (con una VRAM de 7 ciclos de latencia) una tira de 64 x 5 son
  unos 5.000 ciclos del VDP con LMMM, unos 60 us a 85,9 MHz. Si el RTL se
  arregla (que `w_next` y `w_nx_max` vayan de byte en byte tambien fuera de
  G4-G6, no solo en G7), el autotest elige HMMM, que alli va como en G7: unos
  3.100 ciclos por tira. La velocidad de verdad depende de la VRAM de cada
  maquina. El candado del puerto 4 (bit 7), que el RTL pide para escribir
  R#20/R#21, se quita y se vuelve a poner como dice su documentacion, pero el
  fork no lo emula.
- **ROM de 256 KB**: hace falta un cartucho flash o un emulador que la
  acepte con el mapper Konami SCC.

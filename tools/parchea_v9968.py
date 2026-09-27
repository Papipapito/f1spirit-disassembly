#!/usr/bin/env python3
"""Construye F-1 Spirit con scroll suave para el V9968: f1spirit_v9968.rom.

El parche vive en v9968/ (ver v9968/LEEME.md). De las 16 paginas del juego
toca dos, y anade una:
  - la 0, con dieciseis ganchos (`call`/`jp`) sobre instrucciones que se
    rehacen fuera;
  - la 15, en su hueco libre de 716 bytes a 0xFF (0xBC84-0xBF4F), con el
    arranque, la recuperacion de interrupciones y la imagen de lo que se
    copia a la RAM (0xF100);
  - la 16, nueva, con el renderer. La ROM pasa de 128 a 256 KB (el mismo
    mapper Konami SCC; las paginas 17-31 van a 0xFF).

Pasos: corta las paginas 0 y 15 de la ROM original, ensambla v9968/ram.asm
(org 0xF100), filtra sus etiquetas V9R_ para parche.asm, ensambla
v9968/parche.asm (que hace `incbin` de las dos paginas y escribe encima, y
la pagina 16 en 0x6000) y monta la ROM. Despues comprueba que en las 16
paginas del juego NINGUN byte ha cambiado fuera de las zonas declaradas en
ZONAS: si el parche se sale, sale con 1.

Uso:
    parchea_v9968.py [rom_original] [salida]
        por defecto f1spirit.rom y f1spirit_v9968.rom
Hace falta pasmo en el PATH.
"""
import hashlib
import os
import re
import subprocess
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRABAJO = os.path.join("work", "v9968")
SHA_ORIGINAL = "3b9afd12b29680abb655f05d24e0970954c38e48c5ccb24227d6c710474396a7"
TAM_PAGINA = 0x2000
TAM_ROM = 16 * TAM_PAGINA
TAM_ROM_V9 = 32 * TAM_PAGINA  # la parcheada: las 16 del juego, la 16 nueva y relleno
PAGINA_V9 = 16

RAM_INICIO = 0xF100
RAM_FIN = 0xF280            # el codigo de la RAM no puede pisar las variables
P15_HUECO = (0xBC84, 0xBF50)

# Lo unico que el parche puede cambiar: (pagina, desde, hasta) en direcciones
# de ejecucion, con el final exclusivo. Cada gancho tapa exactamente la
# instruccion (o las dos) que se rehacen fuera; ver v9968/comun.asm.
ZONAS = [
    (0, 0x4046, 0x4049),    # call SONIDO_PASO -> V9R_SONIDO
    (0, 0x405A, 0x405D),    # call nc,REPINTA_PENDIENTE -> V9R_REPINTA_405A
    (0, 0x40B5, 0x40B8),    # call RDVDP (salida de la interrupcion) -> V9R_ANIDADA
    (0, 0x4117, 0x4121),    # el borrado de la RAM de INIT -> V9_ARRANQUE
    (0, 0x4138, 0x413B),    # call 0BF50h -> V9_INIT
    (0, 0x44C4, 0x44C8),    # push hl / ld hl,03800h
    (0, 0x44DF, 0x44E3),    # ld iy,0E380h
    (0, 0x44F3, 0x44F8),    # ld b,018h / ld hl,03802h
    (0, 0x4513, 0x4517),    # ld ix,0E2C0h
    (0, 0x4538, 0x453B),    # ld a,(00007h)
    (0, 0x465B, 0x4660),    # ld a,0E0h / ld hl,0EA80h
    (0, 0x491B, 0x491E),    # ld hl,03965h
    (0, 0x49C7, 0x49CA),    # ld hl,0E1C4h
    (0, 0x4CD1, 0x4CD4),    # push hl / pop ix (CARGA_LISTA_TILES_MODO)
    (0, 0x56D4, 0x56D7),    # jp MAPEA_1_2_3
    (0, 0x4701, 0x4705),    # ld (ix-003h),000h (TILES_OBJETO_PISTA)
    (15, P15_HUECO[0], P15_HUECO[1]),
]
ORG = {0: 0x4000, 15: 0xA000, PAGINA_V9: 0x6000}


def pasmo(fuente, binario, simbolos=None):
    orden = ["pasmo", "--bin", fuente, binario]
    if simbolos:
        orden.append(simbolos)
    r = subprocess.run(orden, cwd=RAIZ, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stdout + r.stderr)
        sys.exit("FALLO: pasmo no pudo ensamblar %s" % fuente)


def lee(ruta):
    with open(os.path.join(RAIZ, ruta), "rb") as f:
        return f.read()


def lee_simbolos(ruta):
    tabla = {}
    with open(os.path.join(RAIZ, ruta)) as f:
        for linea in f:
            m = re.match(r"^(\w+)\s+EQU\s+([0-9A-F]+)H", linea.strip(), re.I)
            if m:
                tabla[m.group(1)] = int(m.group(2), 16)
    return tabla


def construye(rom_original, salida):
    rom = lee(rom_original)
    if len(rom) != TAM_ROM:
        sys.exit("la ROM mide %d bytes y no %d" % (len(rom), TAM_ROM))
    sha = hashlib.sha256(rom).hexdigest()
    if sha != SHA_ORIGINAL:
        sys.exit("la ROM no es la original (sha256 %s)" % sha)
    os.makedirs(os.path.join(RAIZ, TRABAJO), exist_ok=True)

    # las dos paginas que se parchean, tal cual, para los `incbin`
    for p in (0, 15):
        with open(os.path.join(RAIZ, TRABAJO, "p%02d.bin" % p), "wb") as f:
            f.write(rom[p * TAM_PAGINA:(p + 1) * TAM_PAGINA])

    # 1. la parte de la RAM
    ram_bin = os.path.join(TRABAJO, "ram.bin")
    ram_sym = os.path.join(TRABAJO, "ram.sym")
    pasmo("v9968/ram.asm", ram_bin, ram_sym)
    largo_ram = os.path.getsize(os.path.join(RAIZ, ram_bin))
    if RAM_INICIO + largo_ram > RAM_FIN:
        sys.exit("FALLO: el codigo de la RAM mide %d bytes y no cabe en 0x%04X-0x%04X"
                 % (largo_ram, RAM_INICIO, RAM_FIN - 1))
    simbolos_ram = lee_simbolos(ram_sym)
    with open(os.path.join(RAIZ, TRABAJO, "ram_simbolos.asm"), "w") as f:
        f.write("; generado por tools/parchea_v9968.py desde ram.sym\n")
        for nombre, valor in sorted(simbolos_ram.items(), key=lambda kv: kv[1]):
            if nombre.startswith("V9R_"):
                f.write("%s\tequ 0%04Xh\n" % (nombre, valor))

    # 2. el parche sobre las paginas 0 y 15
    parche_bin = os.path.join(TRABAJO, "parche.bin")
    parche_sym = os.path.join(TRABAJO, "parche.sym")
    pasmo("v9968/parche.asm", parche_bin, parche_sym)
    simbolos = lee_simbolos(parche_sym)
    fin_p15 = simbolos["V9_FIN_P15"]
    if fin_p15 > P15_HUECO[1]:
        sys.exit("FALLO: el codigo de la pagina 15 acaba en 0x%04X y el hueco en 0x%04X"
                 % (fin_p15, P15_HUECO[1]))
    fin_p16 = simbolos["V9_FIN_P16"]
    if fin_p16 > ORG[PAGINA_V9] + TAM_PAGINA:
        sys.exit("FALLO: la pagina 16 se pasa: acaba en 0x%04X" % fin_p16)
    imagen = lee(parche_bin)
    if len(imagen) != 0xC000 - 0x4000:
        sys.exit("FALLO: parche.bin mide %d bytes y no 0x8000" % len(imagen))

    nueva = bytearray(rom) + bytearray(b"\xff" * (TAM_ROM_V9 - TAM_ROM))
    for p in (0, 15, PAGINA_V9):
        ini = ORG[p] - 0x4000
        nueva[p * TAM_PAGINA:(p + 1) * TAM_PAGINA] = imagen[ini:ini + TAM_PAGINA]
    # lo que no usa la pagina 16, a 0xFF como el resto del relleno
    usado = fin_p16 - ORG[PAGINA_V9]
    nueva[PAGINA_V9 * TAM_PAGINA + usado:(PAGINA_V9 + 1) * TAM_PAGINA] = \
        b"\xff" * (TAM_PAGINA - usado)

    # 3. en las paginas del juego, nada fuera de las zonas declaradas
    fuera = []
    for i in range(TAM_ROM):
        if nueva[i] == rom[i]:
            continue
        p, desp = divmod(i, TAM_PAGINA)
        direccion = (0x4000 if p == 0 else 0x6000 + ((p - 1) % 3) * TAM_PAGINA) + desp
        if not any(zp == p and a <= direccion < b for zp, a, b in ZONAS):
            fuera.append((p, direccion))
    if fuera:
        for p, d in fuera[:20]:
            print("  cambiado fuera de zona: p%02d 0x%04X" % (p, d))
        sys.exit("FALLO: %d bytes cambiados fuera de las zonas del parche" % len(fuera))

    with open(os.path.join(RAIZ, salida), "wb") as f:
        f.write(nueva)
    cambiados = sum(1 for a, b in zip(rom, nueva[:TAM_ROM]) if a != b)
    print("RAM: %d de %d bytes (0x%04X-0x%04X)" % (largo_ram, RAM_FIN - RAM_INICIO,
                                                    RAM_INICIO, RAM_INICIO + largo_ram - 1))
    print("pagina 15: %d de %d bytes (0x%04X-0x%04X)" % (fin_p15 - P15_HUECO[0],
                                                          P15_HUECO[1] - P15_HUECO[0],
                                                          P15_HUECO[0], fin_p15 - 1))
    print("pagina 16: %d de %d bytes (0x%04X-0x%04X)" % (usado, TAM_PAGINA, ORG[PAGINA_V9],
                                                          fin_p16 - 1))
    print("%d bytes distintos de la original en las 16 paginas del juego, todos"
          " dentro de las %d zonas" % (cambiados, len(ZONAS)))
    print("OK: %s  sha256 %s" % (salida, hashlib.sha256(nueva).hexdigest()))
    return nueva


def main(argv):
    rom = argv[1] if len(argv) > 1 else "f1spirit.rom"
    salida = argv[2] if len(argv) > 2 else "f1spirit_v9968.rom"
    construye(rom, salida)


if __name__ == "__main__":
    main(sys.argv)

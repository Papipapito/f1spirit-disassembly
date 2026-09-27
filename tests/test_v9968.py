#!/usr/bin/env python3
"""El parche de scroll suave para V9968 (v9968/, tools/parchea_v9968.py).

El parche engancha la pagina 0 en sitios concretos y llama a rutinas del
juego por su direccion. Si el listado cambia de sitio una etiqueta, o si
alguien toca comun.asm, el parche seguiria ensamblando y la ROM saldria rota
sin que nada avisara. Estos tests atan cada direccion de v9968/comun.asm a la
instruccion o la etiqueta que dice su comentario, en src/f1spirit_pNN.asm.

Los que necesitan el cartucho (y pasmo) construyen la ROM parcheada en un
directorio temporal y miran el binario: tamano, paginas intactas, hueco de la
pagina 15, tabla de saltos de la pagina 16 e imagen de la RAM.
"""
import hashlib
import os
import re
import shutil
import sys
import tempfile
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))
import parchea_v9968 as parche  # noqa: E402

ROM = os.path.join(RAIZ, "f1spirit.rom")
TAM_PAGINA = 0x2000

# Cada gancho: su simbolo en comun.asm, su direccion y lo que tiene que haber
# ahi en el listado de la pagina 0 (una instruccion por direccion; los ganchos
# que tapan dos instrucciones llevan las dos).
GANCHOS = {
    "G_SONIDO": (0x4046, ["call 06aa5h"]),
    "G_REPINTA": (0x405A, ["call nc,REPINTA_PENDIENTE"]),
    "G_SALIDA_INT": (0x40B5, ["call 0013eh"]),
    "G_BORRA_RAM": (0x4117, ["ld hl,0e000h", "ld de,0e001h", "ld bc,010ffh",
                             "ld (hl),000h"]),
    "G_BORRA_RAM_SIGUE": (0x4124, ["ld a,001h"]),
    "G_INIT": (0x4138, ["call 0bf50h"]),
    "G_VUELCA_768": (0x44C4, ["push hl", "ld hl,03800h"]),
    "G_VENTANA_J2": (0x44DF, ["ld iy,0e380h"]),
    "G_BORRA_VENTANA": (0x44F3, ["ld b,018h", "ld hl,03802h"]),
    "G_VENTANA_1J": (0x4513, ["ld ix,0e2c0h"]),
    "G_VENTANA_2J": (0x4538, ["ld a,(00007h)"]),
    "G_BORRA_SPRITES": (0x465B, ["ld a,0e0h", "ld hl,0ea80h"]),
    "G_OBJETO": (0x4701, ["ld (ix-003h),000h"]),
    "G_SPRITES": (0x4784, ["ld a,(0e1c3h)"]),
    "G_FILA_PISTA_INI": (0x564C, ["call MAPEA_7_8_9"]),
    "G_CASILLA_HUD": (0x491B, ["ld hl,03965h"]),
    "G_CORTINILLA": (0x49C7, ["ld hl,0e1c4h"]),
    "G_LISTA_TILES": (0x4CD1, ["push hl", "pop ix"]),
    "G_FILA_PISTA_FIN": (0x56D4, ["jp MAPEA_1_2_3"]),
}

# Las rutinas del juego a las que llama el parche: (simbolo, direccion,
# pagina, etiqueta del listado o None si basta con que haya instruccion ahi)
RUTINAS = [
    ("REPINTA_PENDIENTE", 0x40BB, 0, "REPINTA_PENDIENTE"),
    ("MAPEA_1_2_3", 0x43FE, 0, "MAPEA_1_2_3"),
    ("MAPEA_7_8_9", 0x4438, 0, "MAPEA_7_8_9"),
    ("VENTANA_1J_SIGUE", 0x4517, 0, None),
    ("G_VENTANA_J2_SIGUE", 0x44E3, 0, None),
    ("G_VUELCA_768_SIGUE", 0x44C8, 0, None),
    ("VACIA_COLA_SONIDO", 0x4140, 0, "VACIA_COLA_SONIDO"),
    ("CUENTA_ATRAS_F0F7", 0x4155, 0, "CUENTA_ATRAS_F0F7"),
    ("BUSCA_CONSOLA", 0xBF50, 15, None),
    ("SONIDO_PASO", 0x6AA5, 13, None),
    ("SONIDO_6422", 0x6422, 13, "SONIDO_6422"),
]

# Longitud de la instruccion (o instrucciones) que tapa cada gancho: la zona
# de tools/parchea_v9968.py tiene que medir eso (el borrado de la RAM, lo que
# ocupa lo que se escribe encima).
LARGO_ZONA = {
    "G_SONIDO": 3, "G_REPINTA": 3, "G_SALIDA_INT": 3, "G_BORRA_RAM": 10,
    "G_INIT": 3, "G_VUELCA_768": 4, "G_VENTANA_J2": 4, "G_BORRA_VENTANA": 5,
    "G_VENTANA_1J": 4, "G_VENTANA_2J": 3, "G_BORRA_SPRITES": 5, "G_OBJETO": 4,
    "G_CASILLA_HUD": 3, "G_CORTINILLA": 3, "G_LISTA_TILES": 3,
    "G_FILA_PISTA_FIN": 3, "G_SPRITES": 3, "G_FILA_PISTA_INI": 3,
}


def lee(ruta):
    with open(ruta, "rb") as f:
        return f.read()


def simbolos_comun():
    tabla = {}
    with open(os.path.join(RAIZ, "v9968", "comun.asm"), encoding="utf-8") as f:
        for ln in f:
            m = re.match(r"^(\w+)\s+equ\s+([0-9A-Fa-f]+)h\b", ln)
            if m:
                tabla[m.group(1)] = int(m.group(2), 16)
    return tabla


def listado(p):
    """{direccion: instruccion} y {etiqueta: direccion} del listado p."""
    instr, etiquetas, pendientes = {}, {}, []
    ruta = os.path.join(RAIZ, "src", "f1spirit_p%02d.asm" % p)
    with open(ruta, encoding="utf-8") as f:
        for ln in f:
            m = re.match(r"^(\w+):", ln)
            if m:
                pendientes.append(m.group(1))
                continue
            m = re.match(r"^\t([^;\t][^;]*?)\s*;([0-9a-f]{4})\b", ln)
            if m:
                d = int(m.group(2), 16)
                instr[d] = " ".join(m.group(1).split())
                for e in pendientes:
                    etiquetas[e] = d
                pendientes = []
    return instr, etiquetas


class TestV9968Direcciones(unittest.TestCase):
    """Sin cartucho: comun.asm contra el listado."""

    @classmethod
    def setUpClass(cls):
        cls.sim = simbolos_comun()
        cls.p00, cls.etq00 = listado(0)

    def test_cada_gancho_esta_en_comun_con_su_direccion(self):
        for nombre, (dir_, _) in GANCHOS.items():
            self.assertIn(nombre, self.sim, "falta %s en comun.asm" % nombre)
            self.assertEqual(self.sim[nombre], dir_, "%s: 0x%04X y no 0x%04X"
                             % (nombre, self.sim[nombre], dir_))

    def test_cada_gancho_tapa_la_instruccion_que_dice(self):
        for nombre, (dir_, esperadas) in GANCHOS.items():
            d = dir_
            for esperada in esperadas:
                self.assertIn(d, self.p00, "%s: no hay instruccion en 0x%04X" % (nombre, d))
                self.assertEqual(self.p00[d], esperada, "%s en 0x%04X" % (nombre, d))
                siguientes = sorted(x for x in self.p00 if x > d)
                d = siguientes[0]

    def test_rutinas_del_juego(self):
        cache = {0: (self.p00, self.etq00)}
        for nombre, dir_, pagina, etiqueta in RUTINAS:
            self.assertEqual(self.sim.get(nombre), dir_, "%s en comun.asm" % nombre)
            if pagina not in cache:
                cache[pagina] = listado(pagina)
            instr, etiquetas = cache[pagina]
            self.assertIn(dir_, instr, "%s: no hay instruccion en 0x%04X (p%02d)"
                          % (nombre, dir_, pagina))
            if etiqueta:
                self.assertEqual(etiquetas.get(etiqueta), dir_,
                                 "%s: la etiqueta %s no esta en 0x%04X" % (nombre, etiqueta, dir_))

    def test_las_zonas_del_parche_son_las_de_los_ganchos(self):
        zonas_p0 = sorted((a, b) for p, a, b in parche.ZONAS if p == 0)
        esperadas = sorted((self.sim[n], self.sim[n] + LARGO_ZONA[n]) for n in LARGO_ZONA)
        self.assertEqual(zonas_p0, esperadas)
        self.assertIn((15, parche.P15_HUECO[0], parche.P15_HUECO[1]), parche.ZONAS)

    def test_la_ram_del_parche_no_pisa_la_bios_ni_el_juego(self):
        # el juego usa 0xE000-0xF0FF (y su pila empieza en 0xF0F0); la BIOS,
        # de 0xF380 para arriba
        valores = [v for n, v in self.sim.items() if n.startswith("V9_") and v >= 0xF000]
        self.assertTrue(valores)
        self.assertGreaterEqual(min(valores), 0xF100)
        self.assertLess(max(valores), 0xF380)
        self.assertEqual(self.sim["V9_VALIDAS"] & 0xFF, 0, "V9_VALIDAS tiene que empezar pagina")
        self.assertLessEqual(self.sim["V9_VALIDAS"] + 128, 0xF380)
        self.assertEqual(parche.RAM_FIN, self.sim["V9_CAPS"],
                         "el codigo de la RAM acaba donde empiezan las variables")
        # V9_FILA_CAMBIOS recorre la foto con `inc e`: no puede cruzar pagina
        self.assertLessEqual((self.sim["V9_VIEJA"] & 0xFF) + 32, 0x100)

    def test_las_variables_no_se_pisan(self):
        # cada variable ocupa lo que dice su comentario, "(N)", o 1 byte
        ocupa = []
        with open(os.path.join(RAIZ, "v9968", "comun.asm"), encoding="utf-8") as f:
            for ln in f:
                m = re.match(r"^(V9_\w+)\s+equ\s+([0-9A-Fa-f]+)h\b\s*(?:;\s*(?:\((\d+)\))?)?", ln)
                if m and int(m.group(2), 16) >= parche.RAM_FIN:
                    ocupa.append((int(m.group(2), 16), int(m.group(3) or 1), m.group(1)))
        ocupa.sort()
        for (a, n, nombre), (b, _, sig) in zip(ocupa, ocupa[1:]):
            self.assertLessEqual(a + n, b, "%s (0x%04X, %d) pisa %s (0x%04X)" % (nombre, a, n, sig, b))
        a, n, nombre = ocupa[-1]
        self.assertLessEqual(a + n, 0xF380, nombre)


@unittest.skipUnless(os.path.exists(ROM), "falta f1spirit.rom")
@unittest.skipUnless(shutil.which("pasmo"), "falta pasmo")
class TestV9968Rom(unittest.TestCase):
    """Con el cartucho: la ROM parcheada."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.salida = os.path.join(cls.tmp, "f1spirit_v9968.rom")
        cls.orig = lee(ROM)
        cls.nueva = bytes(parche.construye(ROM, cls.salida))
        cls.sim = simbolos_comun()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_la_original_es_la_buena(self):
        self.assertEqual(hashlib.sha256(self.orig).hexdigest(), parche.SHA_ORIGINAL)

    def test_tamano_y_fichero(self):
        self.assertEqual(len(self.nueva), 32 * TAM_PAGINA)
        self.assertEqual(lee(self.salida), self.nueva)

    def test_paginas_sin_tocar(self):
        for p in list(range(1, 15)):
            ini = p * TAM_PAGINA
            self.assertEqual(self.nueva[ini:ini + TAM_PAGINA], self.orig[ini:ini + TAM_PAGINA],
                             "la pagina %d ha cambiado" % p)

    def test_el_hueco_de_la_pagina_15_estaba_vacio(self):
        a, b = parche.P15_HUECO
        ini = 15 * TAM_PAGINA + (a - 0xA000)
        fin = 15 * TAM_PAGINA + (b - 0xA000)
        self.assertEqual(set(self.orig[ini:fin]), {0xFF})

    def test_los_ganchos_salen_en_la_pagina_0(self):
        # cada gancho empieza por un `call` (0xCD / 0xD4 = call nc) o un `jp`
        # (0xC3), salvo el borrado de la RAM, que empieza por `ld a,0Fh`
        for nombre, (dir_, _) in GANCHOS.items():
            if nombre.endswith("_SIGUE"):
                continue
            op = self.nueva[dir_ - 0x4000]
            if nombre == "G_BORRA_RAM":
                self.assertEqual(self.nueva[dir_ - 0x4000:dir_ - 0x4000 + 2], b"\x3e\x0f")
            else:
                self.assertIn(op, (0xCD, 0xD4, 0xC3), "%s: 0x%02X" % (nombre, op))

    def test_tabla_de_saltos_de_la_pagina_16(self):
        p16 = self.nueva[16 * TAM_PAGINA:17 * TAM_PAGINA]
        entradas = sorted(v for n, v in self.sim.items() if n.startswith("P16_"))
        self.assertEqual(entradas, list(range(0x6000, 0x6000 + 3 * len(entradas), 3)))
        for e in entradas:
            o = e - 0x6000
            self.assertEqual(p16[o], 0xC3, "P16 0x%04X no es un jp" % e)
            destino = p16[o + 1] | (p16[o + 2] << 8)
            self.assertTrue(0x6000 + 3 * len(entradas) <= destino < 0x8000)
            self.assertNotEqual(p16[destino - 0x6000], 0xFF, "0x%04X esta vacio" % destino)

    def test_imagen_de_la_ram_en_la_pagina_15(self):
        ram = lee(os.path.join(RAIZ, "work", "v9968", "ram.bin"))
        p15 = self.nueva[15 * TAM_PAGINA:16 * TAM_PAGINA]
        self.assertIn(ram, p15)
        self.assertLessEqual(parche.RAM_INICIO + len(ram), parche.RAM_FIN)

    def test_las_copias_usan_el_comando_del_autotest(self):
        # en el V9968 de HRA! HMMM salta bytes en G2: cada comando de copia del
        # renderer sale de V9_COPIA (HMMM o LMMM, lo que diga el autotest), ni
        # uno con HMMM fijo (`ld a,0D0h / out (099h),a`)
        p16 = self.nueva[16 * TAM_PAGINA:17 * TAM_PAGINA]
        copia = self.sim["V9_COPIA"]
        self.assertNotIn(b"\x3e\xd0\xd3\x99", p16)
        self.assertGreaterEqual(p16.count(bytes([0x3A, copia & 0xFF, copia >> 8, 0xD3, 0x99])), 3)
        # y las plantillas de 15 registros (R#32..R#46) no traen comando: la
        # del autotest, 4 x 1 de (0, 496) a (0, 497)
        self.assertIn(bytes([0, 0, 0xF0, 1, 0, 0, 0xF1, 1, 4, 0, 1, 0, 0, 0, 0]), p16)
        self.assertEqual(self.sim["LMMM"], 0x90)

    def test_relleno(self):
        # las paginas 17-31 a 0xFF: el mapper las puede ver, pero nadie las usa
        self.assertEqual(set(self.nueva[17 * TAM_PAGINA:]), {0xFF})


if __name__ == "__main__":
    unittest.main()

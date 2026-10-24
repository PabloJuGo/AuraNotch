#!/usr/bin/env python3
"""Comprueba que cada Resources/<idioma>.lproj tenga las mismas claves que es.lproj (la fuente) y los mismos
especificadores de formato (%@, %lld, %%). Uso: Scripts/check-localizations.py"""
import json, re, subprocess, sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent / "Resources"
spec = re.compile(r"%(?:\d+\$)?(?:lld|@|%|\.\d+f|d)")

def load(p):
    return json.loads(subprocess.run(["plutil", "-convert", "json", "-o", "-", str(p)], check=True, capture_output=True, text=True).stdout)

def specs(s):
    return sorted(re.sub(r"\d+\$", "", m) for m in spec.findall(s))

ok = True
for table in ("Localizable", "InfoPlist"):
    source = load(root / "es.lproj" / f"{table}.strings")
    for lproj in sorted(root.glob("*.lproj")):
        if lproj.name == "es.lproj": continue
        f = lproj / f"{table}.strings"
        if not f.exists():
            print(f"FALTA {f}"); ok = False; continue
        got = load(f)
        for k in source.keys() - got.keys(): print(f"{lproj.name}/{table}: sin traducir: {k!r}"); ok = False
        for k in got.keys() - source.keys(): print(f"{lproj.name}/{table}: clave sobrante: {k!r}"); ok = False
        for k, v in got.items():
            if k in source and specs(k) != specs(v): print(f"{lproj.name}/{table}: formato distinto en {k!r} -> {v!r}"); ok = False
            if k in source and not v.strip(): print(f"{lproj.name}/{table}: vacío: {k!r}"); ok = False
print("OK" if ok else "CON ERRORES")
sys.exit(0 if ok else 1)

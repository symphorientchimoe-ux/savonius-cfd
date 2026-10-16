#!/usr/bin/env python3
"""Surfaces STL du demi-rotor Savonius CNDT pour snappyHexMesh (cas base3d).
Pales sans épaisseur (arcs de corde 0,68 m, rayon 0,50 m), arbre Ø 45 mm, plaque d'extrémité optionnelle,
cylindre de la zone tournante. Le plan z = 0 est le plan de symétrie à mi-hauteur du rotor.
Usage : python3 -I scripts/stl3d.py DOSSIER [--plaque DIAMETRE]"""
import argparse, math, pathlib
import numpy as np

c, Rb, rs = 0.68, 0.50, 0.0225
H2 = 0.50                  # demi-hauteur des pales [m]
RZ, HZ = 0.90, 0.80        # rayon et hauteur de la zone tournante [m]


def ecrire(path, nom, tris):
    with open(path, "w") as f:
        f.write(f"solid {nom}\n")
        for a, b, d in tris:
            n = np.cross(b - a, d - a); n = n / (np.linalg.norm(n) or 1)
            f.write(f" facet normal {n[0]:.6e} {n[1]:.6e} {n[2]:.6e}\n  outer loop\n")
            for p in (a, b, d):
                f.write(f"   vertex {p[0]:.6e} {p[1]:.6e} {p[2]:.6e}\n")
            f.write("  endloop\n endfacet\n")
        f.write(f"endsolid {nom}\n")


def arc(i, n=120):
    dd = math.sqrt(Rb**2 - (c / 2) ** 2)
    th = -math.pi / 2 + i * math.pi / 2
    ex, ey = math.cos(th), math.sin(th)
    cx, cy = c / 2 * ex + dd * ey, c / 2 * ey - dd * ex
    a0 = math.atan2(-cy, -cx); a1 = math.atan2(c * ey - cy, c * ex - cx)
    da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi
    a = a0 + np.linspace(0, 1, n) * da
    return cx + Rb * np.cos(a), cy + Rb * np.sin(a)


def bande(x, y, z0, z1, nz):
    """Surface réglée verticale le long de la courbe (x, y)."""
    z = np.linspace(z0, z1, nz + 1); t = []
    for k in range(len(x) - 1):
        for j in range(nz):
            p = [np.array([x[k + a], y[k + a], z[j + b]]) for a, b in ((0, 0), (1, 0), (1, 1), (0, 1))]
            t += [(p[0], p[1], p[2]), (p[0], p[2], p[3])]
    return t


def disque(r, z, n=96, haut=True):
    o = np.array([0, 0, z]); t = []
    for k in range(n):
        a, b = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        p, q = np.array([r * math.cos(a), r * math.sin(a), z]), np.array([r * math.cos(b), r * math.sin(b), z])
        t.append((o, p, q) if haut else (o, q, p))
    return t


def cylindre(r, z1, n=96, nz=8, z0=-0.1):
    """Cylindre fermé ; il descend sous le plan de symétrie pour que snappyHexMesh le voie fermé."""
    a = np.linspace(0, 2 * math.pi, n + 1)
    return bande(r * np.cos(a), r * np.sin(a), z0, z1, nz) + disque(r, z1, n) + disque(r, z0, n, haut=False)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("dossier"); ap.add_argument("--plaque", type=float, default=0.0)
    a = ap.parse_args(); d = pathlib.Path(a.dossier); d.mkdir(parents=True, exist_ok=True)
    pales = []
    for i in range(4):
        x, y = arc(i); pales += bande(x, y, -0.05, H2, 22)   # dépasse sous z = 0
    ecrire(d / "pales.stl", "pales", pales)
    ecrire(d / "arbre.stl", "arbre", cylindre(rs, H2 + 0.05, 32, 4))
    if a.plaque > 0:
        ecrire(d / "plaque.stl", "plaque", disque(a.plaque / 2, H2))
    ecrire(d / "zoneTournante.stl", "zoneTournante", cylindre(RZ, HZ))
    print("STL écrits dans", d)

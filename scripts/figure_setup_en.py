#!/usr/bin/env python3
"""Figure de l'article (en anglais) : (a) rotor, (b) domaine de référence et conditions aux limites,
(c) maillage à couches limites près du bout de pale (lu dans geom/savonius2D_v3bl.msh).

Usage : python3 -I scripts/figure_setup_en.py   ->   figures/article/fig_setup.png
"""
import math, pathlib
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Rectangle, FancyArrowPatch
from matplotlib.collections import PolyCollection

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "figures" / "article"
c, Rb, rs, Rr = 0.68, 0.50, 0.0225, 0.90          # corde, rayon de l'arc, arbre, zone tournante [m]
D = 2 * c
xmin, xmax, ymax = -14.0, 34.0, 14.0               # domaine de référence (dom2)
d = math.sqrt(Rb**2 - (c / 2) ** 2)
BLADE = "#1f4e9c"


def blade(i):
    th = -math.pi / 2 + i * math.pi / 2
    ex, ey = math.cos(th), math.sin(th)
    nx, ny = ey, -ex
    cx, cy = c / 2 * ex + d * nx, c / 2 * ey + d * ny
    a0, a1 = math.atan2(-cy, -cx), math.atan2(c * ey - cy, c * ex - cx)
    s = np.linspace(a0, a0 + (a1 - a0 + math.pi) % (2 * math.pi) - math.pi, 200)
    return np.c_[cx + Rb * np.cos(s), cy + Rb * np.sin(s)], (c * ex, c * ey)


def arrow(ax, p0, p1, style="-|>", ms=14, **kw):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle=style, mutation_scale=ms, **kw))


def dim(ax, p0, p1, txt, off=(0, 0), fs=9):
    arrow(ax, p0, p1, style="<|-|>", ms=9, color="0.25", lw=0.9)
    ax.text((p0[0] + p1[0]) / 2 + off[0], (p0[1] + p1[1]) / 2 + off[1], txt, ha="center", va="center",
            fontsize=fs, bbox=dict(fc="white", ec="none", alpha=0.85, pad=1))


def mesh_window(msh, x0, x1, y0, y1):
    """Polygones (faces z = 0) du maillage gmsh 2.2 dont le centre tombe dans la fenêtre."""
    f = open(msh).read().split("\n")
    i = f.index("$Nodes"); n = int(f[i + 1]); xy = {}
    for l in f[i + 2:i + 2 + n]:
        a = l.split(); xy[int(a[0])] = (float(a[1]), float(a[2]), float(a[3]))
    j = f.index("$Elements"); m = int(f[j + 1]); polys = []
    for l in f[j + 2:j + 2 + m]:
        a = list(map(int, l.split())); t, nt = a[1], a[2]
        if t in (6, 5):                       # prisme ou hexaèdre extrudé : on garde la face du bas
            v = a[3 + nt:]; p = [xy[k] for k in v[: len(v) // 2]]
            cx, cy = np.mean([q[0] for q in p]), np.mean([q[1] for q in p])
            if x0 - 0.01 < cx < x1 + 0.01 and y0 - 0.01 < cy < y1 + 0.01:
                polys.append(([(q[0], q[1]) for q in p], "#c0392b" if t == 5 else "#1f4e9c"))
    return polys


fig = plt.figure(figsize=(12, 7.6))
gs = fig.add_gridspec(2, 2, width_ratios=[1, 1.35], height_ratios=[1, 1])

# (a) rotor
ax = fig.add_subplot(gs[:, 0])
ax.add_patch(Circle((0, 0), c, fill=False, ls=":", color="0.5"))
ax.add_patch(Circle((0, 0), Rr, fill=False, ls="--", color="#e67e22"))
for i in range(4):
    pts, tip = blade(i); ax.plot(pts[:, 0], pts[:, 1], color=BLADE, lw=2.5, solid_capstyle="round")
ax.add_patch(Circle((0, 0), rs, color="0.3", zorder=5))
dim(ax, (-c, -1.02), (c, -1.02), "D = 1.354 m")
_, tip = blade(1); dim(ax, (0, 0), tip, "chord 0.68 m", off=(0.02, 0.07))
ax.annotate("shaft Ø 45 mm", (0, 0), (0.18, 0.42), arrowprops=dict(arrowstyle="->"), fontsize=9)
ax.annotate("rotating zone (AMI)\nr = 0.90 m", (0.64, -0.64), (0.35, -1.25), arrowprops=dict(arrowstyle="->"),
            fontsize=9, color="#e67e22")
ax.text(-1.38, -1.12, "blade: circular arc,\nradius 0.50 m, steel 1.5 mm\n(modelled 4 mm, rounded tip)\nH = 1.00 m, no end plates",
        fontsize=8.5, va="top")
for y in (-0.4, 0, 0.4):
    arrow(ax, (-1.35, y), (-1.0, y), color="green", lw=1.3)
ax.text(-1.33, 0.55, "U", color="green", fontsize=11)
arrow(ax, (0.25, 0.95), (-0.25, 0.95), style="-|>", connectionstyle="arc3,rad=0.35", color="k", lw=1.2)
ax.text(0, 1.1, "ω", ha="center", fontsize=12)
ax.set_xlim(-1.4, 1.2); ax.set_ylim(-1.62, 1.25); ax.set_aspect("equal"); ax.axis("off")
ax.set_title("(a) Rotor cross-section", fontsize=11)

# (b) domaine
ax = fig.add_subplot(gs[0, 1])
ax.add_patch(Rectangle((xmin, -ymax), xmax - xmin, 2 * ymax, fc="#dbe9f6", ec="k"))
ax.add_patch(Circle((0, 0), 1.6, color="#e67e22"))           # rotor agrandi pour être visible
ax.plot([xmin, xmin], [-ymax, ymax], color="green", lw=4); ax.plot([xmax, xmax], [-ymax, ymax], color="purple", lw=4)
ax.text(xmin + 0.8, ymax - 1.5, "inlet: U = 4 m/s\n(1 s ramp), I = 1 %", fontsize=8.5, va="top", color="green")
ax.text(xmax - 0.8, ymax - 1.5, "outlet:\np = 0", fontsize=8.5, va="top", ha="right", color="purple")
ax.text(10, ymax + 1.3, "symmetry", fontsize=8.5, ha="center", color="0.3")
ax.text(10, -ymax - 2.6, "symmetry", fontsize=8.5, ha="center", color="0.3")
dim(ax, (xmin, -9), (0, -9), "10.3 D")
dim(ax, (0, -9), (xmax, -9), "25 D")
dim(ax, (27, -ymax), (27, ymax), "20.7 D", off=(0, 0))
ax.text(1.5, 2.2, "rotor (not to scale)", fontsize=8)
ax.set_xlim(xmin - 1, xmax + 1); ax.set_ylim(-ymax - 3.5, ymax + 3); ax.set_aspect("equal"); ax.axis("off")
ax.set_title("(b) Reference domain and boundary conditions (blockage 4.8 %)", fontsize=11)

# (c) maillage près du bout de pale 0 (bout en (0, -0.68))
ax = fig.add_subplot(gs[1, 1])
x0, x1, y0, y1 = -0.035, 0.035, -0.705, -0.665
pol = mesh_window(ROOT / "geom" / "savonius2D_v3bl.msh", x0, x1, y0, y1)
ax.add_collection(PolyCollection([p for p, _ in pol], facecolors="none", edgecolors=[k for _, k in pol], linewidths=0.35))
ax.set_xlim(x0, x1); ax.set_ylim(y0, y1); ax.set_aspect("equal")
ax.set_xlabel("x (m)"); ax.set_ylabel("y (m)"); ax.tick_params(labelsize=8)
ax.set_title("(c) Mesh near a blade tip: prism layers (red), first cell 0.1 mm", fontsize=11)

fig.tight_layout(); fig.savefig(OUT / "fig_setup.png", dpi=200); plt.close(fig)
print(OUT / "fig_setup.png")

#!/usr/bin/env python3
"""Figures de l'article (légendes en anglais) à partir de resultats/*.csv (t, Mz, Cm) et *.info (caseInfo).

Usage : python3 -I scripts/figures_article.py
Sorties : figures/article/*.png et un résumé chiffré sur la sortie standard.
"""
import math, pathlib
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = pathlib.Path(__file__).resolve().parents[1]
RES, OUT = ROOT / "resultats", ROOT / "figures" / "article"
OUT.mkdir(parents=True, exist_ok=True)
NTOURS = 10          # tours moyennés (ou tous les tours après les 4 premiers s'il y en a moins)
plt.rcParams.update({"font.size": 11, "axes.grid": True, "grid.alpha": 0.3})


def premiere(*prefixes, motif="tsr"):
    """Premier préfixe de série qui a des résultats (la méthode de référence d'abord, les anciennes ensuite)."""
    return next((p for p in prefixes if any(RES.glob(f"{p}_{motif}*.csv"))), prefixes[-1])


V = {}                                                  # valeurs reprises dans l'article (article/valeurs.tex)


def num(x, n=3):
    return f"{x:.{n}f}"


REF = premiere("bldom2_U4", "bl_U4")                    # couches limites (+ grand domaine dès qu'il est fini)
BW = premiere("bwbldom2_U7", "blackwell_U7")            # validation avec la même méthode
STAT = premiere("bldom2stat_U4", "blstatique_U4", "statique_U4", motif="ang")
BWSTAT = premiere("bwbldom2stat_U7", "bwstat_U4", motif="ang")


def info(nom):
    return {k: v.strip() for k, _, v in (l.partition(" ") for l in (RES / f"{nom}.info").read_text().splitlines())}


def tours(nom):
    """Cm moyen de chaque tour complet après la rampe, et nombre de tours visés."""
    a, i = np.loadtxt(RES / f"{nom}.csv", delimiter=",", skiprows=1), info(nom)
    t, cm = a[:, 0], a[:, 2]
    tr, T = float(i["tramp"]), float(i["period"])
    if np.any(np.diff(t) > 3 * np.median(np.diff(t))):
        print(f"  attention : trou dans l'historique de {nom}")
    n = int((t[-1] - tr) / T + 0.01)        # tolère un dernier pas un peu avant la fin du tour
    return np.array([cm[(t > tr + k * T) & (t <= tr + (k + 1) * T)].mean() for k in range(n)]), float(i["revs"])


def moyenne(nom):
    """(Cp, erreur type, nombre de tours, fini) sur les NTOURS derniers tours."""
    c, revs = tours(nom)
    lam = float(info(nom)["tsr"])
    v = c[-NTOURS:] if len(c) >= NTOURS + 4 else c[4:]
    return lam * v.mean(), lam * v.std(ddof=1) / math.sqrt(len(v)), len(c), len(c) >= revs - 1e-6


def serie(prefixe):
    pts = []
    for f in sorted(RES.glob(f"{prefixe}_tsr*.csv")):
        lam = float(f.stem.split("tsr")[1]); pts.append((lam, *moyenne(f.stem)))
    return sorted(pts)


def fig_cp():
    p, q = np.array(serie(REF)), np.array(serie("rot_U4"))
    fig, ax = plt.subplots(1, 2, figsize=(11, 4.2))
    ax[0].plot(q[:, 0], q[:, 1], "x--", color="0.6", label="without prism layers, 10D wide domain")
    ax[0].errorbar(p[:, 0], p[:, 1], yerr=p[:, 2], fmt="o-", capsize=3, color="#1f4e9c",
                   label="prism layers, " + ("20D wide domain" if REF.startswith("bldom2") else "10D wide domain"))
    ax[0].legend(fontsize=8, loc="lower center")
    ax[0].set_xlabel("Tip speed ratio λ"); ax[0].set_ylabel("Power coefficient $C_p$")
    ax[0].set_xlim(0, 1.4); ax[0].set_ylim(0, 0.18); ax[0].set_title("(a) CNDT rotor, 2D URANS, U = 4 m/s")
    ax[1].errorbar(p[:, 0], p[:, 1] / p[:, 0], yerr=p[:, 2] / p[:, 0], fmt="s-", capsize=3, color="#c0392b")
    _, ms, _ = statique(STAT)
    ax[1].plot(0, ms[:-1].mean(), "D", mfc="white", color="#2e8b3a", label="static, mean over θ")
    ax[1].legend(fontsize=8, loc="lower left")
    ax[1].set_xlabel("Tip speed ratio λ"); ax[1].set_ylabel("Torque coefficient $C_m$")
    ax[1].set_xlim(-0.05, 1.4); ax[1].set_ylim(0, 0.3); ax[1].set_title("(b) Mean torque coefficient")
    fig.tight_layout(); fig.savefig(OUT / "fig_cp_lambda.png", dpi=200); plt.close(fig)
    print(f"Cp(λ) rotor CNDT, U = 4 m/s (série {REF}) :")
    for l, cp, e, n, ok in p:
        print(f"  λ = {l:.1f} : Cp = {cp:.4f} ± {e:.4f} ({int(n)} tours{'' if ok else ', en cours'})")
        V[f"Cp{l:.1f}"] = num(cp); V[f"Cm{l:.1f}"] = num(cp / l)
    k = p[:, 1].argmax(); V["CpMax"] = num(p[k, 1]); V["LamMax"] = f"{p[k, 0]:.1f}"
    V["RefFini"] = "1" if p[:, 4].all() else "0"


def fig_blackwell():
    exp = np.loadtxt(ROOT / "validation" / "blackwell1977_run21_cp.csv", delimiter=",", comments="#", skiprows=4)
    p = np.array(serie(BW))
    fig, ax = plt.subplots(figsize=(6.2, 4.4))
    ax.plot(exp[:, 0], exp[:, 1], "ko", mfc="white", label="Experiment, Blackwell et al. (1977), run 21")
    fini = p[:, 4] > 0
    ax.errorbar(p[:, 0], p[:, 1], yerr=p[:, 2], fmt="-", color="#1f4e9c", capsize=3)
    ax.plot(p[fini, 0], p[fini, 1], "s", color="#1f4e9c", label="Present 2D URANS (k-ω SST)")
    if (~fini).any():
        ax.plot(p[~fini, 0], p[~fini, 1], "s", mfc="white", color="#1f4e9c", label="Present 2D URANS, not yet converged")
    ax.set_xlabel("Tip speed ratio λ"); ax.set_ylabel("Power coefficient $C_p$"); ax.set_xlim(0, 2); ax.set_ylim(-0.05, 0.35)
    ax.set_title("Validation: two-bucket rotor, s/c = 0.15, U = 7 m/s", fontsize=10); ax.legend(fontsize=8, loc="lower center")
    fig.tight_layout(); fig.savefig(OUT / "fig_validation_blackwell.png", dpi=200); plt.close(fig)
    print(f"Validation Blackwell (U = 7 m/s, série {BW}) :")
    for l, cp, e, n, ok in p:
        ce = np.interp(l, exp[:, 0], exp[:, 1])
        print(f"  λ = {l:.1f} : CFD {cp:.3f}, essai {ce:.3f}, écart {100 * (cp / ce - 1):+.0f} % ({int(n)} tours{'' if ok else ', en cours'})")
        V[f"BwCfd{l:.1f}"] = num(cp); V[f"BwExp{l:.1f}"] = num(ce); V[f"BwDev{l:.1f}"] = f"{100 * (cp / ce - 1):+.0f}"
    V["BwSerie"] = BW.replace("_", r"\_")


def statique(prefixe):
    ang, m, e = [], [], []
    for f in sorted(RES.glob(f"{prefixe}_ang*.csv"), key=lambda f: float(f.stem.split("ang")[1])):
        a = np.loadtxt(f, delimiter=",", skiprows=1); t, cm = a[:, 0], a[:, 2]
        sec = [cm[(t > s) & (t <= s + 1)].mean() for s in range(5, int(t[-1]))]   # moyennes par seconde, t > 5 s
        ang.append(float(f.stem.split("ang")[1])); m.append(cm[t > 5].mean()); e.append(np.std(sec, ddof=1) / math.sqrt(len(sec)))
    return np.array(ang), np.array(m), np.array(e)


def fig_statique():
    ang, m, e = statique(STAT)
    fig, ax = plt.subplots(1, 2, figsize=(11, 4.2))
    ax[0].errorbar(ang, m, yerr=e, fmt="o-", capsize=3, color="#2e8b3a", label="U = 4 m/s")
    ax[0].plot(ang + 90, m, "o--", mfc="white", color="#2e8b3a", label="U = 4 m/s, repeated (90° period)")
    if any(RES.glob("bldom2statU25_U2.5_ang*.csv")):
        a2, m2, e2 = statique("bldom2statU25_U2.5")
        ax[0].errorbar(a2, m2, yerr=e2, fmt="^", capsize=3, color="#e08a1e", label="U = 2.5 m/s")
        V["StatLowMin"] = num(m2.min(), 2); V["StatLowMinAng"] = f"{a2[m2.argmin()]:.0f}"
        V["StatLowZero"] = num(m2[a2 == 0][0], 2); V["StatLowNinety"] = num(m2[a2 == 90][0], 2)
        print("Couple statique à 2,5 m/s : " + ", ".join(f"{a:.0f}° {v:.3f}±{s:.3f}" for a, v, s in zip(a2, m2, e2)))
    ax[0].axhline(0, color="k", lw=0.8)
    ax[0].set_xlabel("Rotor angular position θ (°)"); ax[0].set_ylabel("Static torque coefficient $C_{ms}$")
    ax[0].set_xticks(range(0, 181, 30)); ax[0].set_xlim(-5, 185); ax[0].set_ylim(-0.1, 0.4)
    ax[0].set_title("(a) CNDT rotor, locked (2D)", fontsize=10); ax[0].legend(fontsize=8)
    V["StatMin"] = num(m.min(), 3); V["StatMinErr"] = num(e[m.argmin()], 3); V["StatMinAng"] = f"{ang[m.argmin()]:.0f}"
    V["StatMax"] = num(m.max(), 2); V["StatMaxAng"] = f"{ang[m.argmax()]:.0f}"; V["StatMean"] = num(m[:-1].mean(), 2)
    V["StatSeventyFive"] = num(m[ang == 75][0], 3); V["StatSeventy"] = num(m[ang == 70][0], 3)
    V["StatErrMax"] = num(e.max(), 2)
    print(f"Couple statique ({STAT}) : " + ", ".join(f"{a:.0f}° {v:.3f}±{s:.3f}" for a, v, s in zip(ang, m, e)))
    # rotor de Blackwell : calcul à 7 m/s (même méthode) et mesure du run 19 (fig. 9 du rapport)
    b, mb, eb = statique(BWSTAT)
    ex = np.loadtxt(ROOT / "validation" / "blackwell1977_run19_couple_statique.csv", delimiter=",", comments="#", skiprows=8)
    A, M = np.r_[b, 180], np.r_[mb, mb[0]]
    def ecart(dec):                                    # θ_Blackwell = φ + dec (mod 180)
        c = np.interp((ex[:, 0] - dec) % 180, A, M); return np.sqrt(((c - ex[:, 1]) ** 2).mean()), np.corrcoef(c, ex[:, 1])[0, 1]
    dec = max(range(0, 180, 5), key=lambda d: ecart(d)[1])
    phi = (ex[:, 0] - dec) % 180
    ax[1].errorbar(b, mb, yerr=eb, fmt="s-", capsize=3, color="#7f3f98", label="Present 2D URANS, U = 7 m/s")
    ax[1].plot(phi, ex[:, 1], "ko", mfc="white", label=f"Experiment, run 19 (angle shifted by {dec}°)")
    ax[1].axhline(0, color="k", lw=0.8)
    ax[1].set_xlabel("Rotor angular position (°)"); ax[1].set_ylabel("Static torque coefficient $C_{ms}$")
    ax[1].set_xticks(range(0, 181, 30)); ax[1].set_xlim(-5, 185); ax[1].set_ylim(-0.1, 1.0)
    ax[1].set_title("(b) Two-bucket rotor of Blackwell et al.", fontsize=10); ax[1].legend(fontsize=8, loc="upper right")
    fig.tight_layout(); fig.savefig(OUT / "fig_couple_statique.png", dpi=200); plt.close(fig)
    me = ex[:-1, 1].mean()                             # le dernier point (115°) répète le premier (−65°)
    V["BwStatMin"] = num(mb.min(), 2); V["BwStatMinAng"] = f"{b[mb.argmin()]:.0f}"; V["BwStatMax"] = num(mb.max(), 2)
    V["BwStatMean"] = num(mb.mean(), 2); V["BwStatExpMean"] = num(me, 2); V["BwStatExpMin"] = num(ex[:, 1].min(), 2)
    V["BwStatExpMax"] = num(ex[:, 1].max(), 2); V["BwStatOver"] = f"{100 * (mb.mean() / me - 1):.0f}"
    V["BwStatShift"] = f"{dec}"; V["BwStatCorr"] = num(ecart(dec)[1], 2)
    print(f"Couple statique Blackwell ({BWSTAT}) : " + ", ".join(f"{a:.0f}° {v:.3f}" for a, v in zip(b, mb)))
    print(f"  mesure : moyenne {me:.3f}, min {ex[:, 1].min():.3f} ; calcul : moyenne {mb.mean():.3f} "
          f"(+{100 * (mb.mean() / me - 1):.0f} %), min {mb.min():.3f} ; décalage d'angle {dec}°, corrélation {ecart(dec)[1]:.2f}")


def fig_demarrage():
    """Vent de démarrage U = sqrt(T / (C_ms ½ ρ D H R)) en fonction du couple résistant de la pompe."""
    ang, m, _ = statique(STAT)
    k = 0.5 * 1.225 * 1.354 * 1.0 * 0.68                  # ½ ρ D H R [kg/m]
    T = np.linspace(0.05, 3, 200)
    fig, ax = plt.subplots(figsize=(6.4, 4.2))
    cas = [(m[:-1].mean(), "mean over positions", "-"), (np.sort(m)[1], f"2nd lowest position", "--"), (m.min(), "weakest position", ":")]
    for cm, lab, st in cas:
        ax.plot(T, np.sqrt(T / (cm * k)), st, color="#1f4e9c", label=f"{lab}, $C_{{ms}}$ = {cm:.3f}")
    ax.set_xlabel("Resisting torque of the pump at start (N·m)"); ax.set_ylabel("Starting wind speed (m/s)")
    ax.set_xlim(0, 3); ax.set_ylim(0, 15); ax.legend(fontsize=8, loc="upper left")
    ax.set_title("CNDT rotor, H = 1 m, 2D static torque", fontsize=10)
    fig.tight_layout(); fig.savefig(OUT / "fig_demarrage.png", dpi=200); plt.close(fig)
    V["DemK"] = num(k, 3)
    for t in (0.5, 1.0):
        nom = "Half" if t == 0.5 else "One"
        V[f"Dem{nom}Mean"] = f"{np.sqrt(t / (m[:-1].mean() * k)):.1f}"; V[f"Dem{nom}Min"] = f"{np.sqrt(t / (m.min() * k)):.1f}"
        V[f"Dem{nom}Seventy"] = f"{np.sqrt(t / (m[ang == 70][0] * k)):.1f}"


def fig_domaine():
    """Effets séparés de la largeur et de la position d'entrée (λ = 0,8 et 1,2) et du vent (λ = 0,8)."""
    print("Domaine et vent :")
    for nom in ["bl_U4_tsr0.8", "bl_U4_tsr1.2", "bldomlarge_U4_tsr0.8", "bldomlarge_U4_tsr1.2",
                "bldomamont_U4_tsr0.8", "bldomamont_U4_tsr1.2", f"{REF}_tsr0.8", f"{REF}_tsr1.2",
                "of12_U4_tsr0.8", "bldom2U25_U2.5_tsr0.8", "bldom2U6_U6_tsr0.8"]:
        if (RES / f"{nom}.csv").exists():
            cp, e, nt, ok = moyenne(nom)
            V["Dom" + nom.split("_")[0] + nom.split("tsr")[1]] = num(cp)
            V["Dom" + nom.split("_")[0] + nom.split("tsr")[1] + "Fini"] = "1" if ok else "0"
            print(f"  {nom} : Cp = {cp:.4f} ± {e:.4f} ({nt} tours{'' if ok else ', en cours'})")
            if nom.startswith(("bl_", "bldomlarge", "bldomamont", REF)):   # même fenêtre (tours 6 à 15) : bl n'a que 15 tours
                c, _ = tours(nom); lam = float(info(nom)["tsr"])
                V["Win" + nom.split("_")[0] + nom.split("tsr")[1]] = num(lam * c[5:15].mean())
    # vent : comparaison sur les mêmes tours (9 à 18), tant que les cas à 2,5 et 6 m/s ne sont pas finis
    for nom in [f"{REF}_tsr0.8", "bldom2U25_U2.5_tsr0.8", "bldom2U6_U6_tsr0.8"]:
        if (RES / f"{nom}.csv").exists():
            c, _ = tours(nom)
            if len(c) >= 18:
                V["Re" + nom.split("_")[0]] = num(0.8 * c[8:18].mean())


def fig_sensibilite():
    lignes = [("v3c_U4_tsr0.8", 54035, "coarse", "o"), ("rot_U4_tsr0.8", 104785, "medium", "o"),
              ("v3f_U4_tsr0.8", 204137, "fine", "o"), ("bl_U4_tsr0.8", 122925, "prism layers", "s")]
    fig, ax = plt.subplots(1, 2, figsize=(11, 4.2))
    print("Sensibilité à λ = 0,8 :")
    for nom, n, lab, mk in lignes:
        if (RES / f"{nom}.csv").exists():
            cp, e, nt, ok = moyenne(nom)
            ax[0].errorbar(n, cp, yerr=e, fmt=mk, mfc=None if ok else "white",
                           color="#c0392b" if mk == "s" else "#1f4e9c", capsize=3)
            ax[0].annotate(lab + ("" if ok else " (running)"), (n, cp), (6, 6), textcoords="offset points", fontsize=9)
            print(f"  maillage {lab} ({n} cellules) : Cp = {cp:.4f} ± {e:.4f} ({nt} tours{'' if ok else ', en cours'})")
            V["Sens" + nom.split("_")[0]] = num(cp)
    ax[0].set_xscale("log"); ax[0].set_xlabel("Number of cells"); ax[0].set_ylabel("$C_p$ at λ = 0.8")
    ax[0].set_ylim(0.10, 0.17); ax[0].set_title("(a) Mesh sensitivity")
    for nom, lab, st in [("bl_U4_tsr0.8", "Δθ = 0.5°", "o-"), ("bldt025_U4_tsr0.8", "Δθ = 0.25°", "s--")]:
        c, _ = tours(nom); ax[1].plot(np.arange(1, len(c) + 1), 0.8 * c, st, label=lab, ms=4)
        cp, e, nt, ok = moyenne(nom); print(f"  pas {lab} (couches limites) : Cp = {cp:.4f} ± {e:.4f}")
        V["Sens" + nom.split("_")[0]] = num(cp)
    ax[1].set_xlabel("Revolution"); ax[1].set_ylabel("$C_p$ (revolution average)"); ax[1].legend()
    ax[1].set_title("(b) Time step, prism-layer mesh")
    fig.tight_layout(); fig.savefig(OUT / "fig_sensibilite.png", dpi=200); plt.close(fig)
    for nom, lab in [("v3fdt025_U4_tsr0.8", "maillage fin, pas 0,25°"), ("dom2_U4_tsr0.8", "domaine 20D"),
                     ("rke_U4_tsr0.8", "k-epsilon realizable"), ("v2tole15_U4_tsr0.8", "tôle 1,5 mm"),
                     ("U25_U2.5_tsr0.8", "U = 2,5 m/s")]:
        if (RES / f"{nom}.csv").exists():
            cp, e, nt, ok = moyenne(nom); print(f"  {lab} : Cp = {cp:.4f} ± {e:.4f}")
            V["Sens" + nom.split("_")[0]] = num(cp)


def fig_azimut():
    """Cm instantané en fonction de l'azimut, moyenné en phase sur les 5 derniers tours (λ = 0,8)."""
    nom = f"{REF}_tsr0.8"
    a, i = np.loadtxt(RES / f"{nom}.csv", delimiter=",", skiprows=1), info(nom)
    t, cm = a[:, 0], a[:, 2]
    tr, T, om = float(i["tramp"]), float(i["period"]), float(i["omega"])
    th = np.degrees(om * 0.5 * tr + om * (t - tr)) % 360          # rampe linéaire de ω sur tr
    n = int((t[-1] - tr) / T); sel = t > tr + (n - 5) * T
    b = np.arange(0, 361, 2); idx = np.digitize(th[sel], b) - 1
    moy = np.array([cm[sel][idx == k].mean() for k in range(len(b) - 1)])
    fig, ax = plt.subplots(figsize=(7, 3.8))
    ax.plot(th[sel], cm[sel], ".", ms=1, color="#9cc3e6", label="5 last revolutions")
    ax.plot(b[:-1] + 1, moy, "-", color="#1f4e9c", lw=2, label="phase average")
    ax.axhline(cm[sel].mean(), color="#c0392b", ls="--", label=f"mean = {cm[sel].mean():.3f}")
    ax.set_xlabel("Azimuthal angle θ (°)"); ax.set_ylabel("$C_m$"); ax.set_xlim(0, 360); ax.set_xticks(range(0, 361, 45))
    ax.legend(fontsize=8, loc="upper right"); ax.set_title("Instantaneous torque coefficient, λ = 0.8", fontsize=10)
    fig.tight_layout(); fig.savefig(OUT / "fig_cm_azimut.png", dpi=200); plt.close(fig)


if __name__ == "__main__":
    fig_cp(); fig_blackwell(); fig_statique(); fig_demarrage(); fig_domaine(); fig_sensibilite(); fig_azimut()
    V["RefSerie"] = REF.replace("_", r"\_"); V["StatSerie"] = STAT.replace("_", r"\_")
    lettres = dict(zip("0123456789.", ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "p"]))
    nom_macro = lambda k: "v" + "".join(lettres.get(c, c) if not c.isalpha() else c for c in k)
    (ROOT / "article").mkdir(exist_ok=True)
    (ROOT / "article" / "valeurs.tex").write_text("% Écrit par scripts/figures_article.py : ne pas modifier à la main.\n" +
        "".join(f"\\newcommand{{\\{nom_macro(k)}}}{{{v}}}  % {k}\n" for k, v in sorted(V.items())))
    print("figures :", ", ".join(sorted(f.name for f in OUT.glob("*.png"))))

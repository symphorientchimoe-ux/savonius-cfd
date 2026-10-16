#!/usr/bin/env python3
"""Cm et Cp d'un calcul Savonius à partir de postProcessing/forces.

Concatène les fichiers forces.dat de toutes les reprises, calcule le couple total
(pression + viscosité, axe z), puis Cm = M / (½ ρ U² D dz R) et Cp = Cm λ.
La moyenne est prise sur les N derniers tours complets, après la rampe.

Usage : bilan_couple.py DOSSIER_CAS [--tours 5] [--dz 0.1] [--csv sortie.csv]
"""
import argparse, math, pathlib, re, sys

RHO = 1.225
NUM = r"[-+0-9.eE]+"


def lire_info(case):
    info = {}
    for ligne in (case / "caseInfo.txt").read_text().splitlines():
        k, _, v = ligne.partition(" ")
        info[k] = v.strip()
    return info


def lire_moments(case):
    """Renvoie [(t, Mz)] trié, les reprises écrasant les pas déjà calculés."""
    data = {}
    dossiers = sorted((case / "postProcessing/forces").iterdir(), key=lambda d: float(d.name))
    # forces.dat, plus forces_<t>.dat quand une reprise repart d'un temps déjà utilisé
    fichiers = [f for d in dossiers for f in sorted(d.glob("forces*.dat"), key=lambda f: f.stat().st_mtime)]
    for f in fichiers:
        for ligne in f.read_text().splitlines():
            if ligne.startswith("#") or not ligne.strip():
                continue
            nums = re.findall(NUM, ligne)
            if len(nums) < 19:
                continue
            t = float(nums[0])
            # nums : t, 9 forces (pression, visqueux, poreux), 9 moments
            mz = float(nums[12]) + float(nums[15])
            data[t] = mz
    return sorted(data.items())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("case", nargs="?", default=".")
    ap.add_argument("--tours", type=int, default=5, help="nombre de derniers tours moyennés")
    ap.add_argument("--dz", type=float, default=0.1, help="épaisseur du domaine 2D [m]")
    ap.add_argument("--csv", help="écrit t, Mz, Cm dans ce fichier")
    a = ap.parse_args()

    case = pathlib.Path(a.case).resolve()
    info = lire_info(case)
    U, R, tsr = float(info["U"]), float(info["R"]), float(info["tsr"])
    tramp, T = float(info["tramp"]), float(info["period"])
    D = 2 * R
    qref = 0.5 * RHO * U**2 * D * a.dz * R

    serie = lire_moments(case)
    if not serie:
        sys.exit("aucune donnée de couple")
    t_fin = serie[-1][0]
    if "static" in info:
        bilan_statique(case, info, serie, qref, a)
        return
    tours_faits = max(0.0, (t_fin - tramp) / T)
    print(f"cas {case.name} : lambda={tsr} U={U} m/s, {len(serie)} pas, t={t_fin:.4g} s, "
          f"{tours_faits:.2f} tours après la rampe")

    if a.csv:
        with open(a.csv, "w") as f:
            f.write("t,Mz,Cm\n")
            for t, m in serie:
                f.write(f"{t:.8g},{m:.6g},{m/qref:.6g}\n")

    n = min(a.tours, int(tours_faits))
    if n < 1:
        print("moins d'un tour complet après la rampe : pas encore de moyenne")
        return
    # moyenne par tour, pour juger de la périodicité
    cm_tours = []
    for i in range(int(tours_faits)):
        t0, t1 = tramp + i * T, tramp + (i + 1) * T
        vals = [m for t, m in serie if t0 < t <= t1]
        if vals:
            cm_tours.append(sum(vals) / len(vals) / qref)
    print("Cm moyen par tour : " + " ".join(f"{c:.4f}" for c in cm_tours))
    cm = sum(cm_tours[-n:]) / n
    print(f"Cm moyen sur les {n} derniers tours = {cm:.4f}")
    print(f"Cp = Cm * lambda = {cm * tsr:.4f}")
    if n >= 2:
        ecart = abs(cm_tours[-1] - cm_tours[-2]) / max(abs(cm), 1e-9)
        print(f"écart entre les deux derniers tours : {100 * ecart:.1f} %")


def bilan_statique(case, info, serie, qref, a):
    """Rotor bloqué : Cm moyen sur les dernières secondes (écoulement instationnaire, lâcher tourbillonnaire)."""
    tramp, t_fin = float(info["tramp"]), serie[-1][0]
    print(f"cas {case.name} : statique, angle {info['static']} deg, U={info['U']} m/s, {len(serie)} pas, "
          f"t={t_fin:.4g} s ({t_fin - tramp:.2f} s après la rampe)")
    if a.csv:
        with open(a.csv, "w") as f:
            f.write("t,Mz,Cm\n")
            for t, m in serie:
                f.write(f"{t:.8g},{m:.6g},{m/qref:.6g}\n")
    secs = [sum(v) / len(v) / qref for v in
            ([m for t, m in serie if tramp + i < t <= tramp + i + 1] for i in range(int(t_fin - tramp))) if v]
    print("Cm moyen par seconde : " + " ".join(f"{c:.4f}" for c in secs))
    t0 = max(tramp + 4.0, t_fin - 6.0)
    vals = [m / qref for t, m in serie if t > t0]
    if t_fin - t0 < 2 or not vals:
        print("moins de 2 s exploitables : pas encore de moyenne")
        return
    print(f"Cm statique moyen sur t > {t0:.2f} s = {sum(vals) / len(vals):.4f} (min {min(vals):.4f}, max {max(vals):.4f})")


if __name__ == "__main__":
    main()

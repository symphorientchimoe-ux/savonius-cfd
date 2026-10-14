#!/usr/bin/env python3
"""Prépare un calcul URANS 2D du rotor Savonius CNDT pour une vitesse spécifique donnée.

Exemple :
    python3 mkcase.py --tsr 0.8 --U 4 --deg 0.5 --revs 15 --np 3 runs/tsr0.80
"""
import argparse, math, os, shutil, subprocess, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
# FOAM_BASHRC permet de pointer vers une autre installation (conteneur Docker : /opt/openfoam8/etc/bashrc)
OF_BASHRC = pathlib.Path(os.environ.get("FOAM_BASHRC", pathlib.Path.home() / "OpenFOAM/OpenFOAM-8/etc/bashrc"))

R = 0.68          # rayon en bout de pale [m]
NU = 1.5e-5       # viscosité cinématique de l'air [m2/s]


def of(cmd, case):
    """Lance une commande OpenFOAM dans le cas, journal dans log.<outil>."""
    tool = cmd.split()[0]
    full = f"source {OF_BASHRC} && cd {case} && {cmd} > log.{tool} 2>&1"
    subprocess.run(["bash", "-c", full], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("case")
    ap.add_argument("--tsr", type=float, required=True, help="vitesse spécifique lambda = omega R / U")
    ap.add_argument("--U", type=float, default=4.0, help="vitesse du vent [m/s]")
    ap.add_argument("--deg", type=float, default=0.5, help="rotation par pas de temps [deg]")
    ap.add_argument("--revs", type=float, default=15, help="nombre de tours simulés")
    ap.add_argument("--np", type=int, default=3, help="nombre de processus MPI")
    ap.add_argument("--Ti", type=float, default=0.01, help="intensité de turbulence en entrée")
    ap.add_argument("--tramp", type=float, default=1.0, help="durée de la rampe vent + rotation [s]")
    ap.add_argument("--msh", default=str(ROOT / "geom/savonius2D.msh"))
    a = ap.parse_args()

    case = pathlib.Path(a.case).resolve()
    if case.exists():
        raise SystemExit(f"{case} existe déjà")
    shutil.copytree(ROOT / "base", case)

    omega = a.tsr * a.U / R
    dt = math.radians(a.deg) / omega
    period = 2 * math.pi / omega
    end = a.tramp + a.revs * period
    steps_per_rev = round(360 / a.deg)
    k = 1.5 * (a.Ti * a.U) ** 2
    om = k / (10 * NU)

    subs = {
        "constant/dynamicMeshDict": {"OMEGA": f"{omega:.6g}", "TRAMP": f"{a.tramp:g}"},
        "0/U": {"UINF": f"{a.U:g}", "TRAMP": f"{a.tramp:g}"},
        "0/k": {"KINF": f"{k:.6g}"},
        "0/omega": {"OMINF": f"{om:.6g}"},
        "system/controlDict": {"ENDTIME": f"{end:.6g}", "DELTAT": f"{dt:.8g}",
                               "WRITESTEPS": str(steps_per_rev // 4)},
        "system/decomposeParDict": {"NPROCS": str(a.np)},
    }
    for f, d in subs.items():
        p = case / f
        s = p.read_text()
        for key, val in d.items():
            s = s.replace(key, val)
        p.write_text(s)

    of(f"gmshToFoam {a.msh}", case)
    bnd = "constant/polyMesh/boundary"
    for cmd in [
        f"foamDictionary {bnd} -entry entry0/frontAndBack/type -set empty",
        f"foamDictionary {bnd} -entry entry0/sides/type -set symmetry",
        f"foamDictionary {bnd} -entry entry0/blades/type -set wall",
        f"foamDictionary {bnd} -entry entry0/AMI1/type -set cyclicAMI",
        f"foamDictionary {bnd} -entry entry0/AMI1/neighbourPatch -add AMI2",
        f"foamDictionary {bnd} -entry entry0/AMI2/type -set cyclicAMI",
        f"foamDictionary {bnd} -entry entry0/AMI2/neighbourPatch -add AMI1",
    ]:
        of(cmd, case)
    of("checkMesh", case)
    if a.np > 1:
        of("decomposePar", case)

    (case / "caseInfo.txt").write_text(
        f"tsr {a.tsr}\nU {a.U}\nomega {omega:.6g}\nR {R}\ndeg_per_step {a.deg}\n"
        f"dt {dt:.8g}\nperiod {period:.6g}\nrevs {a.revs}\nendTime {end:.6g}\n"
        f"tramp {a.tramp}\nnp {a.np}\nTi {a.Ti}\nmsh {a.msh}\n")
    print(f"{case.name}: omega={omega:.4g} rad/s dt={dt:.4g} s T={period:.4g} s end={end:.4g} s")


if __name__ == "__main__":
    main()

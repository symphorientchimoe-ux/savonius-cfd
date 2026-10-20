#!/usr/bin/env python3
"""Prépare un calcul URANS 2D du rotor Savonius CNDT pour une vitesse spécifique donnée.

Exemple :
    python3 mkcase.py --tsr 0.8 --U 4 --deg 0.5 --revs 15 --np 3 runs/tsr0.80
"""
import argparse, math, os, re, shutil, subprocess, pathlib

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


def types_patchs(bnd):
    """Types des patchs écrits par gmshToFoam, modifiés directement dans le fichier boundary (OpenFOAM 10 et plus).
    AMI1 et AMI2 restent de type patch : createNonConformalCouples les couple ensuite (cyclicAMI n'existe plus)."""
    s = bnd.read_text()
    voulu = {"frontAndBack": "empty", "sides": "symmetry", "blades": "wall"}
    for nom, typ in voulu.items():
        m = re.search(rf"(\b{nom}\s*\{{)([^}}]*)\}}", s)
        assert m, f"patch {nom} absent de {bnd}"
        corps = re.sub(r"\btype\s+\w+;", f"type            {typ};", m.group(2))
        corps = re.sub(r"\s*inGroups[^;]*;", "", corps)          # groupe « patch » de gmshToFoam
        s = s[:m.start()] + m.group(1) + corps + "}" + s[m.end():]
    bnd.write_text(s)


def ami_en_patch(bnd):
    """Maillage OpenFOAM fabriqué en version 8 (ex. maillage 3D extrudé) : AMI1 et AMI2 y sont des cyclicAMI.
    En version 10 et plus, ils redeviennent des patchs, que createNonConformalCouples couple ensuite."""
    s = bnd.read_text()
    for nom in ("AMI1", "AMI2"):
        m = re.search(rf"(\b{nom}\s*\{{)([^}}]*)\}}", s)
        assert m, f"patch {nom} absent de {bnd}"
        corps = re.sub(r"\btype\s+\w+;", "type            patch;", m.group(2))
        corps = re.sub(r"\s*neighbourPatch[^;]*;", "", corps)
        s = s[:m.start()] + m.group(1) + corps + "}" + s[m.end():]
    bnd.write_text(s)


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
    ap.add_argument("--base", default="base", help="cas modèle à copier (dossier sous la racine du projet)")
    ap.add_argument("--static", type=float, default=None,
                    help="couple statique : rotor bloqué à cet angle [deg] (tsr ignoré)")
    ap.add_argument("--tstat", type=float, default=10.0, help="durée simulée après la rampe en statique [s]")
    ap.add_argument("--dt", type=float, default=0.00185441, help="pas de temps en statique [s] (celui de lambda = 0,8)")
    ap.add_argument("--msh", default=None,
                    help="maillage gmsh ; défaut : celui nommé dans <base>/MAILLAGE, sinon geom/savonius2D.msh")
    a = ap.parse_args()
    global R
    rayon = ROOT / a.base / "RAYON"          # rayon en bout de pale propre au cas modèle (rotor de validation)
    if rayon.exists():
        R = float(rayon.read_text().split()[0])
    if a.msh is None:
        choix = ROOT / a.base / "MAILLAGE"
        nom = choix.read_text().strip() if choix.exists() else "savonius2D.msh"
        a.msh = str(ROOT / "geom" / nom)

    case = pathlib.Path(a.case).resolve()
    if case.exists():
        raise SystemExit(f"{case} existe déjà")
    shutil.copytree(ROOT / a.base, case)

    if a.static is None:
        omega = a.tsr * a.U / R
        dt = math.radians(a.deg) / omega
        period = 2 * math.pi / omega
        end = a.tramp + a.revs * period
        steps_per_rev = round(360 / a.deg)
    else:
        # rotor bloqué : le maillage tourne de l'angle voulu pendant les 0,1 premières secondes
        # (vent encore presque nul), puis reste immobile
        a.tsr, omega, dt = 0.0, 0.0, a.dt
        period, end = a.tstat, a.tramp + a.tstat
        a.revs = 0
        steps_per_rev = 4 * round(1.0 / dt)       # une écriture par seconde simulée
    k = 1.5 * (a.Ti * a.U) ** 2
    om = k / (10 * NU)

    subs = {
        "constant/dynamicMeshDict": {"OMEGA": f"{omega:.6g}", "TRAMP": f"{a.tramp:g}"},
        "0/U": {"UINF": f"{a.U:g}", "TRAMP": f"{a.tramp:g}"},
        "0/k": {"KINF": f"{k:.6g}"},
        "0/omega": {"OMINF": f"{om:.6g}"},
        "0/epsilon": {"EPSINF": f"{0.09 * k * om:.6g}"},   # cas modèles en k-epsilon
        "system/controlDict": {"ENDTIME": f"{end:.6g}", "DELTAT": f"{dt:.8g}",
                               "WRITESTEPS": str(steps_per_rev // 4)},
        "system/decomposeParDict": {"NPROCS": str(a.np)},
    }
    for f, d in subs.items():
        p = case / f
        if not p.exists():          # omega ou epsilon selon le modèle de turbulence
            continue
        s = p.read_text()
        for key, val in d.items():
            s = s.replace(key, val)
        p.write_text(s)
    if a.static is not None:
        tp, gap = 0.1, 1e-4
        w = math.radians(a.static) / (tp + gap / 2)
        p = case / "constant/dynamicMeshDict"
        txt, n = re.subn(r"omega\s+table\s*\(.*?\);", f"omega table ((0 {w:.8g}) ({tp} {w:.8g}) ({tp + gap:g} 0) (1e6 0));",
                         p.read_text())
        assert n == 1, "ligne omega introuvable dans dynamicMeshDict"
        p.write_text(txt)

    if (case / "constant/polyMesh/boundary").exists():
        cmds = []                   # maillage OpenFOAM déjà prêt dans le cas modèle (ex. tranche du maillage 3D)
        if (case / "constant/physicalProperties").exists():
            ami_en_patch(case / "constant/polyMesh/boundary")
            cmds = ["createNonConformalCouples -overwrite AMI1 AMI2"]
    else:
        of(f"gmshToFoam {a.msh}", case)
        cmds = None
    bnd = "constant/polyMesh/boundary"
    if cmds is None and (case / "constant/physicalProperties").exists():
        types_patchs(case / bnd)    # OpenFOAM 10 et plus : pas de syntaxe entry0 dans foamDictionary
        cmds = ["createNonConformalCouples -overwrite AMI1 AMI2"]
    for cmd in cmds if cmds is not None else [
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
        f"tramp {a.tramp}\nnp {a.np}\nTi {a.Ti}\nmsh {a.msh}\nbase {a.base}\n"
        + (f"static {a.static}\n" if a.static is not None else ""))
    print(f"{case.name}: omega={omega:.4g} rad/s dt={dt:.4g} s T={period:.4g} s end={end:.4g} s")


if __name__ == "__main__":
    main()

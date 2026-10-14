#!/usr/bin/env python3
"""Fabrique le notebook de calcul Savonius pour Kaggle ou Colab.

OpenFOAM 8 n'existe pas en paquet pour ces machines (Ubuntu 22.04 et plus) : le notebook
fait tourner l'image Docker officielle openfoam/openfoam8-paraview56 avec udocker,
qui n'a besoin ni de démon Docker ni de droits particuliers.

Le calcul avance par tranches (BUDGET_TRANCHE secondes). Après chaque tranche, le cas est
archivé : sur Kaggle dans /kaggle/working (sortie du notebook), sur Colab dans Google Drive.
Une coupure ne fait donc perdre qu'une tranche au plus.

Usage :
    fabrique_notebook.py kaggle --tsr 0.8 -o savonius.ipynb
    fabrique_notebook.py colab  --tsr 0.8 -o savonius_colab.ipynb
"""
import argparse, json

PARAMS = '''# Paramètres du calcul (modifier ici)
TSR = "{tsr}"            # vitesse spécifique lambda
U = "{U}"                # vent [m/s]
REVS = "{revs}"          # tours simulés après la rampe
DEG = "{deg}"            # rotation par pas de temps [deg]
BUDGET_TRANCHE = {tranche}   # durée d'une tranche [s] ; le cas est archivé après chaque tranche
BUDGET_TOTAL = {total}      # durée totale à ne pas dépasser dans cette session [s]
MPI_TCP = False          # True si MPI plante dans le conteneur (communication par TCP, plus lente)
'''

KAGGLE_CHEMINS = '''import os, glob, shutil, subprocess, pathlib, time
NP = os.cpu_count()
TRAVAIL = pathlib.Path("/tmp/sv")              # disque local, non sauvegardé
SORTIE = pathlib.Path("/kaggle/working")       # sauvegardé comme sortie du notebook
ENTREES = ["/kaggle/input"]
CAS = f"tsr{TSR}_U{U}"
print("coeurs :", NP, "| cas :", CAS)
'''

COLAB_CHEMINS = '''import os, glob, shutil, subprocess, pathlib, time
from google.colab import drive
drive.mount("/content/drive")
NP = os.cpu_count()
TRAVAIL = pathlib.Path("/content/sv")
SORTIE = pathlib.Path("/content/drive/MyDrive/savonius")   # paquet et archives de reprise
SORTIE.mkdir(parents=True, exist_ok=True)
ENTREES = [str(SORTIE)]
CAS = f"tsr{TSR}_U{U}"
print("coeurs :", NP, "| cas :", CAS)
'''

INSTALL = '''# udocker : exécute l'image Docker d'OpenFOAM 8 sans démon Docker (5 à 10 min la première fois)
def sh(cmd):
    print("$", cmd)
    r = subprocess.run(cmd, shell=True, text=True, capture_output=True)
    print(r.stdout[-3000:], r.stderr[-3000:])
    return r.returncode

UD = "udocker --allow-root"
sh("pip -q install udocker")
sh(f"{UD} install")
sh(f"{UD} pull openfoam/openfoam8-paraview56")
sh(f"{UD} create --name=of8 openfoam/openfoam8-paraview56")

def dans_of8(cmd, volumes):
    v = " ".join(f"-v {a}:{b}" for a, b in volumes)
    env = ("-e HOME=/root -e PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "
           "-e OMPI_ALLOW_RUN_AS_ROOT=1 -e OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1")
    if MPI_TCP:
        env += " -e OMPI_MCA_btl=self,tcp"
    return sh(f"{UD} run --nometa {env} {v} of8 /bin/bash -c '{cmd}'")

# essai : si le mode par défaut (PRoot) échoue, on passe en mode Fakechroot
if dans_of8("source /opt/openfoam8/etc/bashrc && pimpleFoam -help | head -3", []) != 0:
    sh(f"{UD} setup --execmode=F3 of8")
    assert dans_of8("source /opt/openfoam8/etc/bashrc && pimpleFoam -help | head -3", []) == 0
'''

DONNEES = '''# Paquet du projet et éventuelle archive de reprise
def trouver(motif):
    for e in ENTREES:
        r = sorted(glob.glob(f"{e}/**/{motif}", recursive=True))
        if r:
            return r[-1]
    return None

shutil.rmtree(TRAVAIL, ignore_errors=True)
TRAVAIL.mkdir(parents=True)
paquet = trouver("savonius_paquet.tar.gz")
if paquet:
    sh(f"tar xzf {paquet} -C {TRAVAIL}")
else:                       # Kaggle a pu décompresser l'archive à l'import
    mk = trouver("scripts/mkcase.py")
    assert mk, "paquet savonius introuvable dans les données d'entrée"
    shutil.copytree(pathlib.Path(mk).parents[1], TRAVAIL / "savonius")
PROJ = TRAVAIL / "savonius"
(PROJ / "runs").mkdir(exist_ok=True)

reprise = trouver(f"cas_{CAS}.tar.gz")
if reprise:
    sh(f"tar xzf {reprise} -C {PROJ / 'runs'}")
    print("reprise depuis", reprise)
else:
    d = trouver(f"{CAS}/caseInfo.txt")
    if d:
        shutil.copytree(pathlib.Path(d).parent, PROJ / "runs" / CAS)
        print("reprise depuis", d)
    else:
        print("nouveau calcul")
'''

CALCUL = '''# Calcul par tranches, archive après chaque tranche
t_debut = time.time()
etat = "a_reprendre"
while etat == "a_reprendre":
    reste = BUDGET_TOTAL - (time.time() - t_debut)
    if reste < 900:
        print("budget de la session épuisé")
        break
    budget = int(min(BUDGET_TRANCHE, reste - 600))
    cmd = (f"bash calcul_distant/commun/lancer_cas.sh runs/{CAS} --tsr {TSR} --U {U} --np {NP} "
           f"--budget {budget} --revs {REVS} --deg {DEG} --archive /out/cas_{CAS}.tar.gz")
    dans_of8(f"cd /w && {cmd}", [(PROJ, "/w"), (SORTIE, "/out")])
    etat = (PROJ / "runs" / CAS / "ETAT").read_text().strip()
    for f in ["bilan.txt", "ETAT", "caseInfo.txt"]:
        shutil.copy(PROJ / "runs" / CAS / f, SORTIE / f"{CAS}_{f}")
    print("état :", etat)
print(open(SORTIE / f"{CAS}_bilan.txt").read())
'''

RESULTATS = '''# Série temporelle du couple et contrôle visuel
dans_of8(f"cd /w && python3 calcul_distant/commun/bilan_couple.py runs/{CAS} --csv /out/{CAS}_couple.csv",
         [(PROJ, "/w"), (SORTIE, "/out")])
import pandas as pd, matplotlib.pyplot as plt
df = pd.read_csv(SORTIE / f"{CAS}_couple.csv")
df.plot(x="t", y="Cm", figsize=(10, 3), legend=False, title=f"Cm(t), lambda = {TSR}")
plt.savefig(SORTIE / f"{CAS}_Cm.png", dpi=120)
'''


def cellule(src, code=True):
    lignes = src.strip("\n").split("\n")
    c = {"cell_type": "code" if code else "markdown", "metadata": {},
         "source": [l + "\n" for l in lignes[:-1]] + [lignes[-1]]}
    if code:
        c.update(execution_count=None, outputs=[])
    return c


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("plateforme", choices=["kaggle", "colab"])
    ap.add_argument("--tsr", default="0.8")
    ap.add_argument("--U", default="4")
    ap.add_argument("--revs", default="15")
    ap.add_argument("--deg", default="0.5")
    ap.add_argument("-o", "--sortie", required=True)
    a = ap.parse_args()

    if a.plateforme == "kaggle":
        # session de 12 h : tranches de 4 h, arrêt avant 11 h 20
        tranche, total, chemins = 14400, 40800, KAGGLE_CHEMINS
        titre = ("# Savonius CNDT, CFD 2D OpenFOAM 8 sur Kaggle\n"
                 "Lancer avec *Save Version > Save & Run All (Commit)* : le calcul tourne sans navigateur ouvert. "
                 "Internet doit être activé (compte vérifié par téléphone). Données d'entrée : le jeu `savonius-paquet` "
                 "et, pour une reprise, le jeu contenant l'archive `cas_tsr..._U....tar.gz`.")
    else:
        # Colab gratuit coupe sans prévenir : tranches courtes, archive sur Drive
        tranche, total, chemins = 5400, 41400, COLAB_CHEMINS
        titre = ("# Savonius CNDT, CFD 2D OpenFOAM 8 sur Colab\n"
                 "Déposer `savonius_paquet.tar.gz` dans `Mon Drive/savonius/` puis *Exécuter tout*. "
                 "Les archives de reprise sont écrites dans le même dossier toutes les 1 h 30. "
                 "Après une coupure, relancer le notebook : il repart de la dernière archive.")

    nb = {"cells": [cellule(titre, code=False),
                    cellule(PARAMS.format(tsr=a.tsr, U=a.U, revs=a.revs, deg=a.deg,
                                          tranche=tranche, total=total)),
                    cellule(chemins), cellule(INSTALL), cellule(DONNEES),
                    cellule(CALCUL), cellule(RESULTATS)],
          "metadata": {"kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
                       "language_info": {"name": "python"}},
          "nbformat": 4, "nbformat_minor": 5}
    with open(a.sortie, "w") as f:
        json.dump(nb, f, ensure_ascii=False, indent=1)
    print(a.sortie)


if __name__ == "__main__":
    main()

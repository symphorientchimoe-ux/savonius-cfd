# Rotor Savonius 4 pales : CFD 2D OpenFOAM 8

Cas URANS 2D (pimpleFoam, k-ω SST, interface AMI) du prototype Savonius du CNDT.
Le workflow `.github/workflows/savonius.yml` lance un job par valeur de λ
(onglet Actions > savonius-cfd > Run workflow).

- `base/` : cas modèle OpenFOAM 8
- `geom/` : géométrie gmsh et maillage
- `scripts/mkcase.py` : création d'un cas pour un λ donné
- `calcul_distant/commun/lancer_cas.sh` : lancement avec arrêt avant la limite de temps et reprise
- `calcul_distant/commun/bilan_couple.py` : Cm et Cp moyens

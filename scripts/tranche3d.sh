#!/bin/bash
# Fabrique une tranche 2D tirée du maillage 3D (snappyHexMesh) pour des niveaux de raffinement donnés.
# Usage : bash scripts/tranche3d.sh NPALE NZONE DOSSIER_CAS [NCOUCHES]
#   NPALE : niveau des pales et de l'arbre (fond de 0,25 m : 5 -> 7,8 mm, 6 -> 3,9 mm, 7 -> 2 mm)
#   NZONE : niveau de la zone tournante (3 -> 3,1 cm, 4 -> 1,6 cm, 5 -> 7,8 mm)
#   DOSSIER_CAS : cas modèle à créer (copie de base_tranche3d avec le nouveau polyMesh)
#   NCOUCHES : couches prismatiques de snappyHexMesh sur pales et arbre (0 par défaut ; première couche 0,1 mm, raison 1,2)
# Seul le plan de symétrie z = 0 sert : le maillage 3D est fait sur une seule maille de fond en hauteur
# (0,25 m au lieu de 3 m), ce qui donne le même plan pour bien moins de cellules.
set -euo pipefail
NPALE=$1; NZONE=$2; DEST=$(realpath -m "$3"); NCOUCHES=${4:-0}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d -p "${TMPDIR:-/tmp}")/maillage3d
set +eu; source "${FOAM_BASHRC:-$HOME/OpenFOAM/OpenFOAM-8/etc/bashrc}"; set -eu

cp -r "$ROOT/base3d" "$W"; cd "$W"
sed -i -e 's/ENDTIME/1/' -e 's/DELTAT/0.001/' -e 's/WRITESTEPS/100/' system/controlDict
sed -i 's/NPROCS/1/' system/decomposeParDict
sed -i -e 's/NX NY NZ/108 56 1/' -e 's/(-7 -7 3) (20 -7 3) (20 7 3) (-7 7 3)/(-7 -7 0.25) (20 -7 0.25) (20 7 0.25) (-7 7 0.25)/' system/blockMeshDict
grep -q "0.25) (20 7 0.25)" system/blockMeshDict || { echo "sommets du blockMeshDict introuvables"; exit 1; }
sed -i -e "s/NPALE/$NPALE/g" -e "s/locationInMesh (-5 -5 2);/locationInMesh (-5 -5 0.13);/" system/snappyHexMeshDict
python3 - "$NZONE" "$NCOUCHES" <<'PY'
import re, sys, pathlib
p = pathlib.Path("system/snappyHexMeshDict"); s = p.read_text(); n, nc = sys.argv[1], int(sys.argv[2])
s, k1 = re.subn(r"(zoneTournante\s*\{\s*level\s*)\(3 3\)", rf"\g<1>({n} {n})", s)
s, k2 = re.subn(r"(zoneTournante \{ mode inside; levels \(\(1E15 )3\)\)", rf"\g<1>{n}))", s)
assert k1 == 1 and k2 == 1, (k1, k2)
if nc:
    s, k3 = re.subn(r"addLayers\s+false;", "addLayers       true;", s)
    couches = " ".join(f"{q} {{ nSurfaceLayers {nc}; }}" for q in ("pales", "pales_slave", "arbre"))
    s, k4 = re.subn(r"relativeSizes true; layers \{\}; expansionRatio 1.2; finalLayerThickness 0.5; minThickness 0.1;",
                    f"relativeSizes false; layers {{ {couches} }}; expansionRatio 1.2; firstLayerThickness 1e-4; minThickness 1e-5;", s)
    assert k3 == 1 and k4 == 1, (k3, k4)
p.write_text(s)
PY
blockMesh > log.blockMesh 2>&1
snappyHexMesh -overwrite > log.snappyHexMesh 2>&1
createBaffles -overwrite > log.createBaffles 2>&1
mergeOrSplitBaffles -split -overwrite > log.mergeOrSplitBaffles 2>&1
echo "maillage 3D bas : $(grep -m1 'cells:' <(checkMesh 2>&1) )"

rm -rf "$DEST"; cp -r "$ROOT/base_tranche3d" "$DEST"; rm -rf "$DEST/constant/polyMesh"
cd "$DEST"
foamDictionary system/extrudeMeshDict -entry sourceCase -set "\"$W\"" > /dev/null
cp system/controlDict system/controlDict.modele      # jokers remplis par mkcase.py au lancement
sed -i -e 's/ENDTIME/1/' -e 's/DELTAT/0.001/' -e 's/WRITESTEPS/100/' system/controlDict
extrudeMesh > log.extrudeMesh 2>&1
topoSet > log.topoSet 2>&1
python3 - <<'PY'
import re, pathlib
p = pathlib.Path("constant/polyMesh/boundary"); s = p.read_text()
for nom in ("sym", "top"):
    m = re.search(rf"(\n\s*{nom}\s*\{{)([^}}]*)\}}", s)
    corps = re.sub(r"\btype\s+\w+;", "type            empty;", m.group(2))
    corps = re.sub(r"\s*inGroups[^;]*;", "", corps)
    s = s[:m.start()] + m.group(1) + corps + "}" + s[m.end():]
p.write_text(s)
PY
checkMesh > log.checkMesh 2>&1 || true
grep -E "cells:|Mesh OK|Failed|\*\*\*" log.checkMesh
mv -f system/controlDict.modele system/controlDict
rm -f log.extrudeMesh log.topoSet log.checkMesh
cat > LISEZMOI.txt <<EOF
Tranche 2D tirée d'un maillage 3D snappyHexMesh : pales et arbre au niveau $NPALE, zone tournante au niveau $NZONE
(fond de 0,25 m), $NCOUCHES couches prismatiques. Fabriquée par scripts/tranche3d.sh $NPALE $NZONE $NCOUCHES (maillage 3D d'une maille de haut, plan z = 0
extrudé sur 0,1 m). Mêmes réglages que base_tranche3d (niveaux 5 et 3).
EOF
cp "$W/log.snappyHexMesh" "$DEST/"          # bilan des couches ajoutées, à garder
rm -rf "$(dirname "$W")"

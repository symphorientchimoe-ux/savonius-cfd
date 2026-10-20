#!/bin/bash
# Maillage 3D du demi-rotor par extrusion du plan 2D à couches limites (geom/savonius3D_plan.geo), avec OpenFOAM 8.
#   étage 1 : z de 0 à H2 (hauteur des pales), plan sans l'intérieur des pales  -> parois des pales
#   étage 2 : z de H2 à HZ (haut de la zone tournante), plan plein               -> dessus des pales = paroi
#   étage 3 : z de HZ à ZTOP, anneau fixe + couvercle fixe                        -> interface glissante au-dessus du rotor
# z = 0 est le plan de symétrie à mi-hauteur du rotor (patch sym), ZTOP le haut du domaine (patch top).
# Usage : bash scripts/maillage3d_extrusion.sh PLAN.msh DOSSIER_SORTIE [NZ1 NZ2 NZ3 [R1 R2 R3]]
#   R1 R2 R3 : rapport entre couches voisines de chaque étage, en partant du haut (défaut 1.07 0.83 0.77).
#   Maillage resserré au sommet des pales (~1 mm de part et d'autre, 2,9 M cellules) : 30 15 10 1.15 0.75 0.77
# Le dossier de sortie reçoit constant/polyMesh (patches inlet outlet sides sym top blades AMI1 AMI2, zone rotor).
set -euo pipefail
MSH=$(realpath "$1"); OUT=$(realpath -m "$2")
NZ1=${3:-20}; NZ2=${4:-8}; NZ3=${5:-10}
H2=0.5; HZ=0.8; ZTOP=3.0
R1=${6:-1.07}; R2=${7:-0.83}; R3=${8:-0.77}   # rapport entre couches voisines, en partant du haut de chaque étage (extrusion vers le bas)
set --; set +eu; source "${FOAM_BASHRC:-$HOME/OpenFOAM/OpenFOAM-8/etc/bashrc}"; set -eu   # sans arguments : le bashrc les interprète
W=$(mktemp -d -p "${TMPDIR:-/tmp}")
log() { echo ">> $*"; }

entete() {  # $1 classe, $2 objet
cat <<EOF
FoamFile { version 2.0; format ascii; class $1; object $2; }
EOF
}

squelette() {  # cas OpenFOAM minimal
    mkdir -p "$1/system" "$1/constant"
    { entete dictionary controlDict; echo "application none; startFrom latestTime; startTime 0; stopAt endTime; endTime 1; deltaT 1; writeControl timeStep; writeInterval 1; writeFormat ${FORMAT_OF:-binary}; writePrecision 12; timePrecision 6;"; } > "$1/system/controlDict"
    { entete dictionary fvSchemes; echo "ddtSchemes {} gradSchemes {} divSchemes {} laplacianSchemes {} interpolationSchemes {} snGradSchemes {}"; } > "$1/system/fvSchemes"
    { entete dictionary fvSolution; echo ""; } > "$1/system/fvSolution"
}

topo() {  # $1 cas, $2 actions topoSet
    { entete dictionary topoSetDict; echo "actions ( $2 );"; } > "$1/system/topoSetDict"
    topoSet -case "$1" > "$1/log.topoSet.$(date +%s%N)" 2>&1
}

patch_depuis_set() {  # $1 cas, puis paires "nom:faceSet:type"
    local cas=$1; shift; local liste=""
    for p in "$@"; do IFS=: read -r nom set typ <<< "$p"
        liste+="{ name $nom; patchInfo { type $typ; } constructFrom set; set $set; } "; done
    { entete dictionary createPatchDict; echo "pointSync false; patches ( $liste );"; } > "$cas/system/createPatchDict"
    createPatch -case "$cas" -overwrite > "$cas/log.createPatch.$(date +%s%N)" 2>&1
}

renommer() {  # $1 cas, puis paires "ancien:nouveau" (fusion de patches existants en un nouveau)
    local cas=$1; shift; local liste=""
    for p in "$@"; do IFS=: read -r a b <<< "$p"
        liste+="{ name $b; patchInfo { type patch; } constructFrom patches; patches ( $a ); } "; done
    { entete dictionary createPatchDict; echo "pointSync false; patches ( $liste );"; } > "$cas/system/createPatchDict"
    createPatch -case "$cas" -overwrite > "$cas/log.createPatch.$(date +%s%N)" 2>&1
}

extruder() {  # $1 cas source, $2 cas cible, $3 patches source, $4 épaisseur, $5 couches, $6 rapport
    squelette "$2"
    { entete dictionary extrudeMeshDict
      echo "constructFrom patch; sourceCase \"$1\"; sourcePatches ( $3 ); exposedPatchName haut; flipNormals false;"
      echo "extrudeModel linearNormal; nLayers $5; expansionRatio $6; linearNormalCoeffs { thickness $4; }"
      echo "mergeFaces false; mergeTol 0;"; } > "$2/system/extrudeMeshDict"
    extrudeMesh -case "$2" > "$2/log.extrudeMesh" 2>&1
}

# ---------- plan ----------
P=$W/plan; squelette "$P"
gmshToFoam -case "$P" "$MSH" > "$P/log.gmshToFoam" 2>&1
log "plan : $(checkMesh -case "$P" 2>&1 | grep -m1 'cells:')"

sous_plan() {  # $1 nom, $2 zones gardées
    local C=$W/$1; cp -r "$P" "$C"
    local act=""; for z in $2; do act+="{ name garde; type cellSet; action $( [ -z "$act" ] && echo new || echo add ); source zoneToCell; sourceInfo { name $z; } } "; done
    topo "$C" "$act"
    subsetMesh -case "$C" garde -overwrite > "$C/log.subsetMesh" 2>&1
}
sous_plan A1 "fluide anneau"
sous_plan A2 "fluide pale anneau"
sous_plan B  "anneau couvercle"

# A1 : faces exposées = parois des pales (côté fluide) et bord intérieur de l'anneau (interface fixe)
topo "$W/A1" "{ name exp; type faceSet; action new; source patchToFace; sourceInfo { name oldInternalFaces; } }
  { name cf; type cellSet; action new; source zoneToCell; sourceInfo { name fluide; } }
  { name murs; type faceSet; action new; source cellToFace; sourceInfo { set cf; option all; } }
  { name murs; type faceSet; action subset; source faceToFace; sourceInfo { set exp; } }
  { name ca; type cellSet; action new; source zoneToCell; sourceInfo { name anneau; } }
  { name ami2; type faceSet; action new; source cellToFace; sourceInfo { set ca; option all; } }
  { name ami2; type faceSet; action subset; source faceToFace; sourceInfo { set exp; } }"
patch_depuis_set "$W/A1" "blades:murs:wall" "AMI2:ami2:patch"
# A2 : faces exposées = bord intérieur de l'anneau ; faces du bas sous les pales -> dessus des pales
topo "$W/A2" "{ name cp; type cellSet; action new; source zoneToCell; sourceInfo { name pale; } }
  { name toit; type faceSet; action new; source cellToFace; sourceInfo { set cp; option all; } }
  { name bas; type faceSet; action new; source patchToFace; sourceInfo { name bas; } }
  { name toit; type faceSet; action subset; source faceToFace; sourceInfo { set bas; } }"
patch_depuis_set "$W/A2" "blades:toit:wall"
renommer "$W/A2" "oldInternalFaces:AMI2"
# B : le bas du couvercle est le côté fixe de l'interface au-dessus du rotor
topo "$W/B" "{ name cc; type cellSet; action new; source zoneToCell; sourceInfo { name couvercle; } }
  { name couv; type faceSet; action new; source cellToFace; sourceInfo { set cc; option all; } }
  { name bas; type faceSet; action new; source patchToFace; sourceInfo { name bas; } }
  { name couv; type faceSet; action subset; source faceToFace; sourceInfo { set bas; } }"
patch_depuis_set "$W/B" "AMI2:couv:patch"

# ---------- extrusions ----------
extruder "$W/A1" "$W/S1" "bas" $H2 $NZ1 $R1
extruder "$W/A2" "$W/S2" "bas blades" $(python3 -c "print($HZ-$H2)") $NZ2 $R2
extruder "$W/B"  "$W/S3" "bas AMI2" $(python3 -c "print($ZTOP-$HZ)") $NZ3 $R3
for s in S1 S2 S3; do log "$s : $(checkMesh -case "$W/$s" 2>&1 | grep -m1 'cells:') ; $(grep -c . "$W/$s/log.extrudeMesh") lignes de journal"; done
# extrudeMesh descend selon la normale du plan (vers -z) : les faces d'origine (bas, blades...) finissent en bas,
# les nouvelles faces (haut) en z = 0 ; on remonte chaque étage à sa place
transformPoints -case "$W/S1" -translate "(0 0 $H2)" > /dev/null 2>&1
transformPoints -case "$W/S2" -translate "(0 0 $HZ)" > /dev/null 2>&1
transformPoints -case "$W/S3" -translate "(0 0 $ZTOP)" > /dev/null 2>&1

# ---------- assemblage ----------
# dessus de l'étage 2 : partie tournante (r < Rr) -> côté tournant de l'interface ; reste -> collé à l'étage 3
topo "$W/S2" "{ name ct; type cellSet; action new; source cylinderToCell; sourceInfo { p1 (0 0 -10); p2 (0 0 10); radius 0.9; } }
  { name dessus; type faceSet; action new; source cellToFace; sourceInfo { set ct; option all; } }
  { name h; type faceSet; action new; source patchToFace; sourceInfo { name haut; } }
  { name dessus; type faceSet; action subset; source faceToFace; sourceInfo { set h; } }"
patch_depuis_set "$W/S2" "AMI1top:dessus:patch"
renommer "$W/S1" "bas:sym" "haut:int12a"
renommer "$W/S2" "bas:int12b" "haut:int23a" "AMI1 AMI1top:AMI1"
renommer "$W/S3" "bas:int23b" "haut:top"
mergeMeshes "$W/S1" "$W/S2" -overwrite > "$W/log.merge12" 2>&1
stitchMesh -case "$W/S1" -perfect int12a int12b -overwrite > "$W/log.stitch12" 2>&1
ranger() { if [ -d "$W/S1/0/polyMesh" ]; then rm -rf "$W/S1/constant/polyMesh"; mv "$W/S1/0/polyMesh" "$W/S1/constant/"; fi; rm -rf "$W/S1/0"; }   # stitchMesh écrit dans 0/
ranger
mergeMeshes "$W/S1" "$W/S3" -overwrite > "$W/log.merge13" 2>&1
stitchMesh -case "$W/S1" -perfect int23a int23b -overwrite > "$W/log.stitch23" 2>&1
ranger

# ménage : patches vides des collages, zones héritées du plan
{ entete dictionary createPatchDict; echo "pointSync false; patches ( );"; } > "$W/S1/system/createPatchDict"
createPatch -case "$W/S1" -overwrite > "$W/log.createPatch.vides" 2>&1
topo "$W/S1" "{ name fluide; type cellZoneSet; action remove; } { name pale; type cellZoneSet; action remove; }
  { name anneau; type cellZoneSet; action remove; } { name couvercle; type cellZoneSet; action remove; }"

# types des patches, zone tournante
python3 - "$W/S1/constant/polyMesh/boundary" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
types = {"inlet": "patch", "outlet": "patch", "sides": "symmetry", "top": "symmetry", "sym": "symmetryPlane",
         "blades": "wall", "AMI1": "patch", "AMI2": "patch"}
noms = re.findall(r"\n\s{4}(\w+)\n\s{4}\{", s)
for nom in noms:
    m = re.search(rf"(\n\s{{4}}{nom}\n\s{{4}}\{{)([^}}]*)\}}", s)
    corps = re.sub(r"\btype\s+\w+;", f"type            {types.get(nom, 'patch')};", m.group(2))
    corps = re.sub(r"\s*inGroups[^;]*;", "", corps)
    s = s[:m.start()] + m.group(1) + corps + "}" + s[m.end():]
p.write_text(s)
print("patches :", " ".join(noms))
PY
topo "$W/S1" "{ name rotor; type cellSet; action new; source cylinderToCell; sourceInfo { p1 (0 0 -1); p2 (0 0 $HZ); radius 0.9; } }
  { name rotor; type cellZoneSet; action new; source setToCellZone; sourceInfo { set rotor; } }"
checkMesh -case "$W/S1" > "$W/log.checkMesh" 2>&1 || true
grep -E "cells:|bounding box|Mesh OK|Failed|\*\*\*" "$W/log.checkMesh"
mkdir -p "$OUT/constant"; rm -rf "$OUT/constant/polyMesh"; cp -r "$W/S1/constant/polyMesh" "$OUT/constant/"
cp "$W/log.checkMesh" "$OUT/log.checkMesh.maillage3d"
rm -rf "$W"

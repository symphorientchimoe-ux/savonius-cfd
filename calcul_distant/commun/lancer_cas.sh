#!/bin/bash
# Lance (ou reprend) un calcul Savonius pour un lambda donné, sur n'importe quelle machine
# où OpenFOAM 8 ou 12 est installé (poste local, conteneur Docker, Kaggle, Colab, Oracle...).
#
# Le calcul s'arrête proprement (écriture des champs) au bout de BUDGET secondes,
# pour tenir dans les limites des plateformes gratuites (6 h GitHub, 12 h Kaggle/Colab).
# En relançant la même commande sur le même dossier, il repart du dernier temps écrit.
#
# Usage :
#   lancer_cas.sh DOSSIER_CAS --tsr 0.8 [--U 4] [--np 4] [--budget 20000] [--revs 15] [--deg 0.5]
#                 [--archive sortie.tar.gz]
#
# Variables d'environnement :
#   FOAM_BASHRC  chemin du bashrc OpenFOAM 8 (défaut : /opt/openfoam8/etc/bashrc s'il existe,
#                sinon ~/OpenFOAM/OpenFOAM-8/etc/bashrc)
#   SAVONIUS_ROOT  racine du projet (dossier contenant base/, scripts/, geom/) ; défaut : ../..
#
# À la fin, le fichier DOSSIER_CAS/ETAT contient « termine » ou « a_reprendre »,
# (ou « erreur » si le solveur a planté), et DOSSIER_CAS/bilan.txt le Cm et le Cp moyens.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SAVONIUS_ROOT:-$(cd "$HERE/../.." && pwd)}"

if [ -z "${FOAM_BASHRC:-}" ]; then
    # conteneur Docker : /opt/openfoam8 ou /opt/openfoam12 selon l'image (voir IMAGE_DOCKER du cas modèle)
    FOAM_BASHRC=$(ls -1 /opt/openfoam*/etc/bashrc 2>/dev/null | head -1)
    [ -n "$FOAM_BASHRC" ] || FOAM_BASHRC="$HOME/OpenFOAM/OpenFOAM-8/etc/bashrc"
fi
export FOAM_BASHRC

CASE="$1"; shift
TSR=""; U=4; NP=4; BUDGET=20000; ARCHIVE=""; EXTRA=()
while [ $# -gt 0 ]; do
    case "$1" in
        --tsr) TSR="$2"; shift 2 ;;
        --U) U="$2"; shift 2 ;;
        --np) NP="$2"; shift 2 ;;
        --budget) BUDGET="$2"; shift 2 ;;
        --archive) ARCHIVE="$2"; shift 2 ;;
        *) EXTRA+=("$1" "$2"); shift 2 ;;
    esac
done
[ -n "$TSR" ] || { echo "--tsr obligatoire"; exit 2; }
CASE="$(realpath -m "$CASE")"
[ -n "$ARCHIVE" ] && ARCHIVE="$(realpath -m "$ARCHIVE")"

# OpenFOAM refuse mpirun en root sans ces variables (conteneurs, Colab, Kaggle)
export OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
# évite que MPI cherche des interfaces réseau exotiques dans les conteneurs
export OMPI_MCA_btl_vader_single_copy_mechanism=none

set +u; source "$FOAM_BASHRC"; set -u

if [ ! -d "$CASE" ]; then
    echo ">> Création du cas $CASE (lambda=$TSR, U=$U, np=$NP)"
    # maillage : celui nommé dans <base>/MAILLAGE, sinon geom/savonius2D.msh (voir mkcase.py)
    python3 "$ROOT/scripts/mkcase.py" "$CASE" --tsr "$TSR" --U "$U" --np "$NP" \
        "${EXTRA[@]}" || exit 1
else
    echo ">> Reprise du cas $CASE depuis le dernier temps écrit"
    # --revs à la reprise : prolonge (ou raccourcit) le calcul en recalculant endTime
    for ((i=0; i<${#EXTRA[@]}; i+=2)); do
        if [ "${EXTRA[$i]}" = "--revs" ]; then
            python3 - "$CASE" "${EXTRA[$((i+1))]}" <<'PY'
import pathlib, re, subprocess, sys
case, revs = pathlib.Path(sys.argv[1]), float(sys.argv[2])
info = dict(l.split(" ", 1) for l in (case / "caseInfo.txt").read_text().splitlines() if " " in l)
# en statique, la durée est fixée par mkcase (period) : --revs ne s'applique pas
if "static" not in info and float(info["revs"]) != revs:
    end = float(info["tramp"]) + revs * float(info["period"])
    subprocess.run(["foamDictionary", str(case / "system/controlDict"), "-entry", "endTime", "-set", f"{end:.6g}"],
                   check=True, stdout=subprocess.DEVNULL)
    info["revs"], info["endTime"] = f"{revs:g}", f"{end:.6g}"
    (case / "caseInfo.txt").write_text("".join(f"{k} {v.strip()}\n" for k, v in info.items()))
    print(f">> nombre de tours porté à {revs:g} : endTime = {end:.6g} s")
PY
        fi
    done
fi

cd "$CASE" || exit 1

# noms de dossiers de temps : assez de chiffres pour que la reprise retrouve le dernier temps écrit
# (avec 8 chiffres, OpenFOAM écrit 6.400776487 mais cherche 6.4007765 à la reprise)
foamDictionary system/controlDict -entry timePrecision -set 12 > /dev/null

# arrêt propre au bout de BUDGET s (temps d'horloge depuis le lancement de ce run)
foamDictionary system/controlDict -entry functions/stopAtClock -remove > /dev/null 2>&1
foamDictionary system/controlDict -entry functions/stopAtClock -add \
    "{ type stopAtClockTime; libs (\"libutilityFunctionObjects.so\"); stopTime $BUDGET; action writeNow; }" > /dev/null

# pimpleFoam (OpenFOAM 8) ou foamRun (OpenFOAM 11 et plus), d'après le controlDict ;
# le journal garde le nom log.pimpleFoam.N dans les deux cas (lu par le workflow et les scripts de suivi)
APP=$(foamDictionary system/controlDict -entry application -value)
# kOmegaSSTLM (OpenFOAM 8) divise par la vorticité, nulle dans l'écoulement uniforme : le cas modèle qui
# contient SANS_SIGFPE tourne sans piège à exceptions (le terme concerné tend alors vers 0, sans NaN)
[ -f SANS_SIGFPE ] && { unset FOAM_SIGFPE; echo ">> piège FPE désactivé (SANS_SIGFPE)"; }
n=1; while [ -e "log.pimpleFoam.$n" ]; do n=$((n+1)); done
LOG="log.pimpleFoam.$n"
echo ">> $APP sur $NP processus, budget ${BUDGET} s, journal $LOG"
t0=$(date +%s)
if [ "$NP" -gt 1 ]; then
    # --oversubscribe : les runners cloud annoncent des vCPU (hyperthreads) que MPI ne compte pas comme cœurs
    mpirun --oversubscribe -np "$NP" "$APP" -parallel > "$LOG" 2>&1
else
    "$APP" > "$LOG" 2>&1
fi
rc=$?
echo ">> $APP terminé (code $rc) en $(( $(date +%s) - t0 )) s"
tail -5 "$LOG"

# dernier temps écrit et état
if [ "$NP" -gt 1 ]; then TDIR=processor0; else TDIR=.; fi
LAST=$(ls -1 "$TDIR" | grep -E '^[0-9.eE+-]+$' | sort -g | tail -1)
# OpenFOAM 12 colle l'unité aux temps (« Time = 34.38s ») : on ne garde que le nombre
END=$(foamDictionary system/controlDict -entry endTime -value | sed 's/[^0-9.eE+-]*$//')
if [ "$rc" -ne 0 ]; then
    echo erreur > ETAT        # divergence ou plantage : ne pas relancer à l'aveugle
# fin atteinte : dernier temps écrit, ou dernier pas calculé (endTime n'est pas toujours un temps d'écriture)
elif LASTRUN=$(grep -E '^Time = ' "$LOG" | tail -1 | awk '{print $3}' | sed 's/[^0-9.eE+-]*$//'); \
     python3 -c "import sys; sys.exit(0 if max(float('$LAST'), float('${LASTRUN:-0}')) >= 0.9999*float('$END') else 1)"; then
    echo termine > ETAT
else
    echo a_reprendre > ETAT
fi
echo ">> dernier temps écrit : $LAST / $END -> $(cat ETAT)"

python3 "$HERE/bilan_couple.py" . > bilan.txt 2>&1 || true
cat bilan.txt

# archive légère pour la reprise : seul le dernier temps est gardé
if [ -n "$ARCHIVE" ]; then
    shopt -s nullglob
    for d in processor*/ .; do
        for t in $(ls -1 "$d" | grep -E '^[0-9.eE+-]+$' | sort -g | head -n -1); do
            [ "$t" = "0" ] && [ "$d" = "." ] && continue   # garde 0/ à la racine
            rm -rf "${d%/}/$t"
        done
    done
    cd ..
    # écriture dans un fichier temporaire : une coupure pendant tar ne détruit pas l'archive précédente
    tar czf "$ARCHIVE.tmp" "$(basename "$CASE")" && mv -f "$ARCHIVE.tmp" "$ARCHIVE"
    echo ">> archive : $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"
fi
exit 0

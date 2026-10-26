#!/bin/bash
# Série de calculs 2D Savonius sur FIR, en OpenFOAM 8 (image Docker officielle via Apptainer, comme sur GitHub) :
# un élément de tableau Slurm par lambda (rotation) ou par angle (statique), reprise automatique de chaque élément.
# Même lancer_cas.sh, mêmes cas modèles et mêmes maillages que le workflow GitHub : résultats directement comparables.
# Image (une fois) : module load apptainer ; apptainer pull $SCRATCH/images/of8.sif docker://openfoam/openfoam8-paraview56
# Usage, depuis la racine du dépôt sur FIR (VALEURS séparées par des espaces, --array=0-(n-1)) :
#   sbatch --array=0-2 --export=ALL,SERIE=bwlm,BASE=base_blackwell_bldom2_lm,U=7,REVS=20,VALEURS="0.8 1.0 1.2" \
#       calcul_distant/08_fir/serie_2d_fir.slurm
#   sbatch --array=0-11 --export=ALL,SERIE=bwlmstat,BASE=base_blackwell_bldom2_lm,U=7,MODE=statique,DT=0.00105966,\
#VALEURS="0 15 30 45 60 75 90 105 120 135 150 165" calcul_distant/08_fir/serie_2d_fir.slurm
# Cas dans $SCRATCH/savonius/2d/SERIE/tsrV_UU ; bilan.txt, couple.csv et ETAT dans chaque cas.
#SBATCH --account=def-mparasch
#SBATCH --job-name=sav2d
#SBATCH --time=24:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=2G
#SBATCH --output=%x-%A_%a.out

set -o pipefail
: "${SERIE:?SERIE manquant}"; : "${BASE:?BASE manquant}"; : "${VALEURS:?VALEURS manquant}"
U=${U:-4}; MODE=${MODE:-rotation}; REVS=${REVS:-15}; DEG=${DEG:-0.5}
PASSE=${PASSE:-1}; PASSES_MAX=${PASSES_MAX:-6}; BUDGET=${BUDGET:-84000}
IMAGE=${IMAGE:-$SCRATCH/images/of8.sif}
read -r -a LISTE <<< "$VALEURS"
V=${LISTE[$SLURM_ARRAY_TASK_ID]:?indice $SLURM_ARRAY_TASK_ID hors de VALEURS}

if [ "$MODE" = statique ]; then
    OPTS="--tsr 0 --static $V"
    [ -n "${DT:-}" ] && OPTS="$OPTS --dt $DT"
    [ -n "${TSTAT:-}" ] && OPTS="$OPTS --tstat $TSTAT"
else
    OPTS="--tsr $V"
fi

cd "$SLURM_SUBMIT_DIR" || exit 1
CASE=$SCRATCH/savonius/2d/$SERIE/tsr${V}_U${U}
mkdir -p "$(dirname "$CASE")"
echo ">> $SERIE $V, passage $PASSE/$PASSES_MAX, $SLURM_CPUS_PER_TASK cœurs, $(date)"
module load apptainer
# --cleanenv : sans les variables SLURM_*, le mpirun du conteneur lance les processus en local au lieu d'appeler srun
apptainer exec --cleanenv "$IMAGE" bash calcul_distant/commun/lancer_cas.sh "$CASE" $OPTS \
    --U "$U" --np "$SLURM_CPUS_PER_TASK" --budget "$BUDGET" --revs "$REVS" --deg "$DEG" --base "$BASE"
apptainer exec --cleanenv "$IMAGE" python3 calcul_distant/commun/bilan_couple.py "$CASE" \
    --csv "$CASE/couple.csv" > "$CASE/bilan.txt" 2>&1
ETAT=$(cat "$CASE/ETAT" 2>/dev/null || echo erreur)
echo ">> état : $ETAT"
cat "$CASE/bilan.txt"
if [ "$ETAT" = a_reprendre ] && [ "$PASSE" -lt "$PASSES_MAX" ]; then
    sbatch --array="$SLURM_ARRAY_TASK_ID" --job-name="$SLURM_JOB_NAME" \
        --export=ALL,PASSE=$((PASSE + 1)) calcul_distant/08_fir/serie_2d_fir.slurm
fi

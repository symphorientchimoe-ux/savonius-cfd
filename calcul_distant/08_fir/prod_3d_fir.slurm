#!/bin/bash
# Calcul 3D de production sur FIR (cas base3d_extr_of12, maillage nc), avec reprise automatique :
# chaque travail calcule BUDGET secondes, écrit, puis se relance tant que le cas n'est pas fini (PASSES_MAX au plus).
# Le cas est créé et repris par calcul_distant/commun/lancer_cas.sh, comme sur GitHub.
# Usage, depuis la racine du dépôt sur FIR :
#   sbatch --export=ALL,NOM=stat65,ARGS="--tsr 0 --static 65 --tpos 0.5" calcul_distant/08_fir/prod_3d_fir.slurm
#   sbatch --export=ALL,NOM=tsr0.6,ARGS="--tsr 0.6 --deg 0.375 --revs 20" calcul_distant/08_fir/prod_3d_fir.slurm
# Compte def-mparasch (rrg-mparasch-ad : allocation prioritaire du groupe, à réserver après accord du Pr Paraschivoiu).
#SBATCH --account=def-mparasch
#SBATCH --job-name=sav3d
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=64
#SBATCH --mem-per-cpu=2G
#SBATCH --output=%x-%j.out

set -o pipefail
: "${NOM:?NOM manquant}"; : "${ARGS:?ARGS manquant}"
PASSE=${PASSE:-1}; PASSES_MAX=${PASSES_MAX:-8}; BUDGET=${BUDGET:-84000}; U=${U:-4}
module load StdEnv/2023 gcc/12.3 openmpi/4.1.5 openfoam/12
export FOAM_BASHRC=/dev/null              # le module définit déjà l'environnement OpenFOAM
export FOAM_FILEHANDLER=collated          # conseil d'Ulrich : un dossier processorsN au lieu de N dossiers

cd "$SLURM_SUBMIT_DIR" || exit 1
CASE=$SCRATCH/savonius/prod/$NOM
mkdir -p "$(dirname "$CASE")"
echo ">> $NOM, passage $PASSE/$PASSES_MAX, $SLURM_NTASKS processus, $(date)"
# ARGS non cité : plusieurs options
bash calcul_distant/commun/lancer_cas.sh "$CASE" $ARGS --U "$U" --np "$SLURM_NTASKS" --budget "$BUDGET" \
    --base "${BASE:-base3d_extr_of12}"
ETAT=$(cat "$CASE/ETAT" 2>/dev/null || echo erreur)
echo ">> état : $ETAT"
grep "^Courant" "$CASE"/log.pimpleFoam.* | tail -1
if [ "$ETAT" = a_reprendre ] && [ "$PASSE" -lt "$PASSES_MAX" ]; then
    sbatch --export=ALL,NOM="$NOM",ARGS="$ARGS",PASSE=$((PASSE + 1)),PASSES_MAX="$PASSES_MAX",BUDGET="$BUDGET",U="$U" \
        --ntasks="$SLURM_NTASKS" calcul_distant/08_fir/prod_3d_fir.slurm
fi

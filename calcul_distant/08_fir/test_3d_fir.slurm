#!/bin/bash
# Mesure du coût du cas 3D (base3d_extr_of12, ~2 M cellules) sur la grappe FIR de l'Alliance.
# Fait NPAS pas de temps à lambda = 0,8 et écrit le temps par pas et l'estimation en cœur·heures pour 25 tours.
# Compte def-mparasch (allocation par défaut du groupe du Pr Paraschivoiu ; rrg-mparasch-ad = allocation prioritaire,
# à garder pour les vrais calculs). Nœuds FIR : 192 cœurs, 768 Go. Copier d'abord le maillage (voir LISEZMOI.txt).
# Usage, depuis la racine du dépôt sur FIR :  sbatch --ntasks=64 calcul_distant/08_fir/test_3d_fir.slurm
#SBATCH --account=def-mparasch
#SBATCH --job-name=sav3d_test
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=64
#SBATCH --mem-per-cpu=2G
#SBATCH --output=%x-%j.out

set -eo pipefail          # pas de -u : les scripts de module et le bashrc OpenFOAM utilisent des variables non définies
NPAS=${NPAS:-60}
module load StdEnv/2023 gcc/12.3 openmpi/4.1.5 openfoam/12
export FOAM_BASHRC=$WM_PROJECT_DIR/etc/bashrc     # lu par scripts/mkcase.py

RACINE=$(pwd)
CASE=$SCRATCH/savonius/test3d_np${SLURM_NTASKS}_${SLURM_JOB_ID}
mkdir -p "$(dirname "$CASE")"
python3 scripts/mkcase.py "$CASE" --tsr 0.8 --U 4 --deg 0.5 --revs 25 \
    --np "$SLURM_NTASKS" --base base3d_extr_of12

cd "$CASE"
DT=$(foamDictionary system/controlDict -entry deltaT -value)
foamDictionary system/controlDict -entry endTime -set "$(python3 -c "print($DT*$NPAS)")" > /dev/null
foamDictionary system/controlDict -entry writeControl -set timeStep > /dev/null
foamDictionary system/controlDict -entry writeInterval -set 100000 > /dev/null

srun foamRun -parallel > log.foamRun 2>&1

# temps par pas sur la seconde moitié (la première contient l'initialisation des couplages)
python3 - "$SLURM_NTASKS" "$DT" <<'EOF'
import re, sys
n, dt = int(sys.argv[1]), float(sys.argv[2])
t = [float(x) for x in re.findall(r"^ExecutionTime = ([\d.eE+-]+) s", open("log.foamRun").read(), re.M)]
if len(t) < 10:
    sys.exit(f"seulement {len(t)} pas dans log.foamRun : voir le journal")
h = len(t) // 2
par_pas = (t[-1] - t[h]) / (len(t) - 1 - h)
pas_25_tours = 25 * 720 + round(1.0 / dt)       # 25 tours à 0,5° par pas, plus la rampe de 1 s
print(f"{n} processus : {par_pas:.2f} s par pas sur {len(t) - 1 - h} pas")
print(f"25 tours ({pas_25_tours} pas) : {par_pas * pas_25_tours / 3600:.1f} h de calcul, "
      f"{par_pas * pas_25_tours * n / 3600:.0f} cœur·h")
EOF
grep -m1 -A4 "FOAM FATAL" log.foamRun || true

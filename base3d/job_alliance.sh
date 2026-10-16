#!/bin/bash
# Lancement du cas 3D sur une grappe de l'Alliance (Slurm). À adapter avec Ulrich :
#   - compte de facturation (--account) : celui du groupe du parrain, de la forme def-xxxx
#   - version d'OpenFOAM : vérifier avec  module spider openfoam  (sinon conteneur Apptainer openfoam8)
# Usage : sbatch job_alliance.sh
#SBATCH --account=def-PARRAIN
#SBATCH --job-name=savonius3d
#SBATCH --nodes=1
#SBATCH --ntasks=32
#SBATCH --mem-per-cpu=2G
#SBATCH --time=0-12:00
#SBATCH --output=log.slurm.%j

module load StdEnv/2020 gcc openmpi openfoam/8     # à confirmer par module spider
source $EBROOTOPENFOAM/OpenFOAM-8/etc/bashrc 2>/dev/null || true

NP=$SLURM_NTASKS
[ -d constant/polyMesh ] || ./Allmesh 5 $NP
foamDictionary system/decomposeParDict -entry numberOfSubdomains -set $NP > /dev/null
[ -d processor0 ] || decomposePar -force > log.decomposePar 2>&1
srun pimpleFoam -parallel > log.pimpleFoam.$SLURM_JOB_ID 2>&1

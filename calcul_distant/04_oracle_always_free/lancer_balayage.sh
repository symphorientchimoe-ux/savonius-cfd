#!/bin/bash
# Balayage en lambda sur une VM sans limite de durée (Oracle Always Free ou tout serveur).
# Les lambdas passent l'un après l'autre sur tous les coeurs ; on peut fermer la session SSH.
# Usage : tmux new -s cfd 'bash lancer_balayage.sh ~/savonius "0.2 0.4 0.6 0.8 1.0 1.2" 4'
#   (détacher : Ctrl-b puis d ; revenir : tmux attach -t cfd)
set -uo pipefail
PROJ="$(realpath "${1:-$HOME/savonius}")"   # dossier issu de savonius_paquet.tar.gz
LAMBDAS="${2:-0.2 0.4 0.6 0.8 1.0 1.2}"
U="${3:-4}"
NP="${NP:-$(nproc)}"
cd "$PROJ"; mkdir -p runs
for l in $LAMBDAS; do
    cas="runs/tsr${l}_U${U}"
    if [ "$(cat "$cas/ETAT" 2>/dev/null)" = "termine" ]; then echo "$cas déjà terminé"; continue; fi
    # budget très long : pas de limite de session ici
    bash calcul_distant/commun/lancer_cas.sh "$cas" --tsr "$l" --U "$U" --np "$NP" --budget 10000000
done
echo "Bilans :"; cat runs/*/bilan.txt

#!/bin/bash
# Suivi des calculs 3D sur FIR, depuis la station : une ligne par calcul (état Slurm, temps simulé, Courant, couple).
# Usage : bash cfd_savonius/calcul_distant/08_fir/suivi_fir.sh
# Il faut une connexion ouverte : « ssh -MN -o ServerAliveInterval=30 fir » dans un terminal laissé ouvert (Duo).
if ! ssh -O check fir 2> /dev/null; then
    echo "Pas de connexion à FIR : lancer « ssh -MN -o ServerAliveInterval=30 fir » dans un autre terminal (validation Duo)."
    exit 1
fi
ssh fir 'bash -s' 2> /dev/null <<'DISTANT'
cd /scratch/tchimoe/savonius-cfd || exit 1
echo "== Travaux Slurm"
squeue -u tchimoe -o "%.10i %.12j %.3t %.11M %.11L %R"
echo
echo "== Calculs (dossier \$SCRATCH/savonius/prod)"
printf "%-14s %-12s %-24s %-9s %s\n" calcul état "temps simulé / visé" "Courant" "couple (bilan_couple, demi-hauteur)"
for c in $SCRATCH/savonius/prod/*/; do
    c=${c%/}; n=$(basename "$c")
    log=$(ls -1 "$c"/log.pimpleFoam.* 2> /dev/null | sort -V | tail -1)
    fin=$(awk '$1=="endTime"{print $2}' "$c/caseInfo.txt" 2> /dev/null)
    t=$(grep -a '^Time = ' "$log" 2> /dev/null | tail -1 | awk '{print $3}' | sed 's/[^0-9.eE+-]*$//')
    co=$(grep -a '^Courant' "$log" 2> /dev/null | tail -1 | awk '{print $NF}')
    etat=$(cat "$c/ETAT" 2> /dev/null || echo "-")
    # journal écrit depuis moins de 3 min (un pas dure ~12 s) : calcul en cours
    [ -n "$log" ] && [ -z "$(find "$log" -mmin +3)" ] && etat="en_calcul"
    bil=$(python3 calcul_distant/commun/bilan_couple.py "$c" --dz 0.5 2> /dev/null | grep -E "Cm|Cp" | tail -2 | tr '\n' ' ' | cut -c1-110)
    printf "%-14s %-12s %-24s %-9s %s\n" "$n" "$etat" "${t:--} / ${fin:--} s" "${co:--}" "${bil:--}"
done
DISTANT

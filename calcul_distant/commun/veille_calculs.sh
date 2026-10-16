#!/bin/bash
# Veille des calculs GitHub : s'arrête (et prévient) dès qu'un run échoue ou est annulé,
# dès qu'un bilan passe à « erreur », ou quand plus rien ne tourne. Durée max : MAX_H heures.
# Usage : bash veille_calculs.sh [MAX_H=10] [PERIODE_S=900]
MAX_H=${1:-10}; P=${2:-900}
S=$HOME/savonius_balayage; cd ~/savonius-cfd || exit 1
connus=$(gh run list --workflow savonius.yml -L 200 --json databaseId,conclusion -q '.[] | select(.conclusion=="failure" or .conclusion=="cancelled") | .databaseId' | sort)
err0=$(grep -l erreur $S/*/bilan-*/ETAT 2>/dev/null | sort)
fin=$(( $(date +%s) + MAX_H*3600 ))
while [ "$(date +%s)" -lt "$fin" ]; do
    sleep "$P"
    bash "$(dirname "$0")/suivi_balayage.sh" > /dev/null 2>&1      # télécharge les nouveaux bilans
    nouveaux=$(comm -13 <(echo "$connus") <(gh run list --workflow savonius.yml -L 200 --json databaseId,conclusion -q '.[] | select(.conclusion=="failure" or .conclusion=="cancelled") | .databaseId' | sort))
    err=$(comm -13 <(echo "$err0") <(grep -l erreur $S/*/bilan-*/ETAT 2>/dev/null | sort))
    actifs=$(gh run list --workflow savonius.yml -L 50 --json status -q '[.[] | select(.status=="in_progress" or .status=="queued")] | length')
    if [ -n "$nouveaux" ] || [ -n "$err" ]; then
        echo "ALERTE $(date -u +%FT%TZ)"; echo "runs échoués ou annulés : $nouveaux"; echo "bilans en erreur : $err"; exit 3
    fi
    if [ "$actifs" = 0 ]; then echo "FIN $(date -u +%FT%TZ) : plus aucun calcul en cours"; exit 0; fi
done
echo "DÉLAI $(date -u +%FT%TZ) : veille de ${MAX_H} h écoulée, $actifs calcul(s) encore actif(s)"

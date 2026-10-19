#!/bin/bash
# Copie dans resultats/ l'historique de couple (couple.csv) et caseInfo.txt du dernier passage de chaque lambda d'une série.
# Usage : bash scripts/rapatrier_serie.sh ETIQUETTE [PREFIXE]   ex. : bash scripts/rapatrier_serie.sh bl bl
# Fichiers créés : resultats/<PREFIXE>_U<U>_tsr<lambda>.csv et .info (PREFIXE = ETIQUETTE par défaut) ;
# pour une série statique (étiquette contenant « stat ») : <PREFIXE>_U<U>_ang<angle>.
set -e
E=$1; P=${2:-$1}; R=symphorientchimoe-ux/savonius-cfd
D=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d)
gh api "repos/$R/actions/artifacts?per_page=100" --paginate \
   --jq ".artifacts[]|select(.expired==false)|select(.name|test(\"^bilan-tsr[0-9.]+-U[0-9.]+-$E-passe[0-9]+\$\"))|[.name,.workflow_run.id]|@tsv" |
 sort -V | awk -F'\t' '{split($1,a,"-passe"); dern[a[1]]=$0} END{for (k in dern) print dern[k]}' |
 while IFS=$'\t' read -r nom run; do
   gh run download "$run" -R $R -n "$nom" -D "$T/$nom" >/dev/null
   lam=$(echo "$nom" | sed -E 's/^bilan-tsr([0-9.]+)-U.*/\1/'); U=$(echo "$nom" | sed -E 's/.*-U([0-9.]+)-.*/\1/')
   case "$E" in *stat*) f=${P}_U${U}_ang${lam} ;; *) f=${P}_U${U}_tsr${lam} ;; esac   # en statique, « tsr » porte l'angle
   cp "$T/$nom/couple.csv" "$D/resultats/$f.csv"; cp "$T/$nom/caseInfo.txt" "$D/resultats/$f.info"
   echo "$nom -> $f ($(($(wc -l < "$T/$nom/couple.csv")-1)) pas)"
 done
rm -rf "$T"

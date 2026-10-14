cd ~/savonius-cfd
S=$HOME/savonius_essais; mkdir -p $S
declare -A NOM=([38617910763]="C2 0.25deg robuste reprise" [38627371862]="D v3b 0.5deg" [38627378491]="E v3b 0.25deg")
for r in 38617910763 38627371862 38627378491; do gh run watch $r --interval 120 > /dev/null 2>&1; done
for r in 38617910763 38627371862 38627378491; do
  D=$S/v_$r; rm -rf $D; mkdir -p $D/x
  echo "=================== ${NOM[$r]} (run $r)"
  gh run download $r -D $D > /dev/null 2>&1
  cat $D/bilan-*/ETAT $D/bilan-*/bilan.txt 2>/dev/null
  tar xzf $D/cas-*/*.tar.gz -C $D/x 2>/dev/null && python3 -I /home/cndt/Documents/fwdarteolienleapre/cfd_savonius/calcul_distant/commun/analyse_log.py $D/x/*/log.pimpleFoam.1
done

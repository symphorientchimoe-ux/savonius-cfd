#!/bin/bash
# Bilan du balayage en lambda lancé le 2026-10-14 à 21 h 28 (heure de GitHub : 21:28Z) sur base_v3b.
# Pour chaque lambda, prend le bilan du dernier passage terminé et affiche état, nombre de tours et Cp.
# Usage : bash suivi_balayage.sh [date_debut_ISO]   (défaut : 2026-10-14T21:28:00Z)
DEBUT="${1:-2026-10-14T21:28:00Z}"
S=$HOME/savonius_balayage; mkdir -p "$S"
cd ~/savonius-cfd || exit 1
echo "Runs du balayage (depuis $DEBUT) :"
gh run list --workflow savonius.yml -L 60 --json databaseId,status,conclusion,createdAt \
  -q ".[] | select(.createdAt >= \"$DEBUT\") | \"\(.databaseId) \(.status) \(.conclusion) \(.createdAt)\"" | tee "$S/runs.txt"
while read id st concl date; do
  [ "$st" = completed ] || continue
  [ -d "$S/$id" ] || gh run download "$id" -D "$S/$id" -p 'bilan-*' > /dev/null 2>&1
done < "$S/runs.txt"
echo; echo "Dernier bilan par lambda :"
python3 -I - "$S" <<'PY'
import pathlib, re, sys
best = {}
for d in pathlib.Path(sys.argv[1]).glob("*/bilan-*"):
    m = re.match(r"bilan-tsr([^-]+)-U.*-passe(\d+)", d.name)
    if m and (m[1] not in best or int(m[2]) > best[m[1]][0]): best[m[1]] = (int(m[2]), d)
for tsr in sorted(best, key=float):
    p, d = best[tsr]; etat = (d / "ETAT").read_text().strip() if (d / "ETAT").exists() else "?"
    b = (d / "bilan.txt").read_text() if (d / "bilan.txt").exists() else ""
    tours = re.search(r"([\d.]+) tours après", b); cp = re.search(r"Cp = .*= ([-\d.]+)", b); ec = re.search(r"écart.*: ([\d.]+ %)", b)
    print(f"lambda {tsr:>4}  passe {p}  {etat:12s} tours {tours[1] if tours else '-':>5}  Cp {cp[1] if cp else '-':>7}  écart {ec[1] if ec else '-'}")
PY

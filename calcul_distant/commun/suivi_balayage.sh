#!/bin/bash
# Bilan du balayage en lambda lancé le 2026-10-14 à 21 h 28 (heure de GitHub : 21:28Z) sur base_v3b.
# Pour chaque série (étiquette), vitesse et lambda (ou angle en statique), prend le bilan du dernier
# passage terminé et affiche état, nombre de tours et Cp (ou Cm statique).
# Usage : bash suivi_balayage.sh [date_debut_ISO]   (défaut : 2026-10-14T21:28:00Z)
DEBUT="${1:-2026-10-14T21:28:00Z}"
S=$HOME/savonius_balayage; mkdir -p "$S"
cd ~/savonius-cfd || exit 1
echo "Runs du balayage (depuis $DEBUT) :"
gh run list --workflow savonius.yml -L 200 --json databaseId,status,conclusion,createdAt \
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
    m = re.match(r"bilan-tsr([^-]+)-U([^-]+)(?:-(.+))?-passe(\d+)$", d.name)
    if not m: continue
    cle = (m[3] or "balayage", m[2], m[1])
    if cle not in best or int(m[4]) > best[cle][0]: best[cle] = (int(m[4]), d)
for (etiq, U, tsr) in sorted(best, key=lambda k: (k[0] != "balayage", k[0], float(k[1]), float(k[2]))):
    p, d = best[(etiq, U, tsr)]
    etat = (d / "ETAT").read_text().strip() if (d / "ETAT").exists() else "?"
    b = (d / "bilan.txt").read_text() if (d / "bilan.txt").exists() else ""
    tete = f"{etiq:9s} U={U:<4} {'angle' if etiq == 'statique' else 'lambda'} {tsr:>4}  passe {p:2d}  {etat:12s}"
    if "stat" in etiq:
        av = re.search(r"\(([\d.]+) s après la rampe\)", b); cm = re.search(r"Cm statique moyen.*= ([-\d.]+)", b)
        print(f"{tete} {av[1] if av else '-':>5} s   Cm statique {cm[1] if cm else '-'}")
    else:
        tours = re.search(r"([\d.]+) tours après", b); cp = re.search(r"Cp = .*= ([-\d.]+)", b); ec = re.search(r"écart.*: ([\d.]+ %)", b)
        print(f"{tete} tours {tours[1] if tours else '-':>5}  Cp {cp[1] if cp else '-':>7}  écart {ec[1] if ec else '-'}")
PY

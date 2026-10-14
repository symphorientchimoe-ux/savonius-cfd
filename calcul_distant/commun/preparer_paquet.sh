#!/bin/bash
# Fabrique savonius_paquet.tar.gz : tout ce qu'il faut pour lancer un cas ailleurs
# (cas modèle, mkcase.py, maillage, lanceur, bilan). Sert à Kaggle, Colab, Oracle, etc.
# Usage : preparer_paquet.sh [DOSSIER_SORTIE]   (défaut : dossier courant)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$HERE/../.." && pwd)"
OUT="$(realpath -m "${1:-.}")"
mkdir -p "$OUT"
cd "$PROJ"
tar czf "$OUT/savonius_paquet.tar.gz" --transform 's|^|savonius/|' \
    base scripts/mkcase.py geom/savonius2D.geo geom/savonius2D.msh \
    calcul_distant/commun/lancer_cas.sh calcul_distant/commun/bilan_couple.py
echo "$OUT/savonius_paquet.tar.gz ($(du -h "$OUT/savonius_paquet.tar.gz" | cut -f1))"

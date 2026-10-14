#!/bin/bash
# Compile OpenFOAM 8 depuis les sources sur une VM Ubuntu (ARM Ampere ou x86).
# Testé pour Ubuntu 22.04 : on force gcc 9, le compilateur avec lequel OpenFOAM 8 a été publié.
# Durée : 2 à 4 h sur 2 coeurs. À lancer dans tmux pour survivre à une déconnexion SSH :
#   tmux new -s install 'bash installer_openfoam8.sh 2>&1 | tee install.log'
set -euo pipefail

sudo apt-get update
sudo apt-get install -y build-essential gcc-9 g++-9 cmake git ca-certificates flex libfl-dev bison \
    zlib1g-dev libboost-system-dev libboost-thread-dev libopenmpi-dev openmpi-bin \
    libreadline-dev libncurses-dev libxt-dev libscotch-dev libptscotch-dev \
    python3 python3-matplotlib gmsh tmux htop

# gcc 9 par défaut (OpenFOAM 8 ne compile pas proprement avec gcc 11 et plus)
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-9 90 --slave /usr/bin/g++ g++ /usr/bin/g++-9
sudo update-alternatives --set gcc /usr/bin/gcc-9

mkdir -p "$HOME/OpenFOAM" && cd "$HOME/OpenFOAM"
[ -d OpenFOAM-8 ] || git clone --depth 1 https://github.com/OpenFOAM/OpenFOAM-8.git
[ -d ThirdParty-8 ] || git clone --depth 1 https://github.com/OpenFOAM/ThirdParty-8.git

# scotch : sans les sources dans ThirdParty-8, OpenFOAM 8 prend celui du système
# (en-têtes /usr/include/scotch, paquets libscotch-dev et libptscotch-dev). Pas de ParaView :
# le post-traitement se fait sur le poste local.

set +u; source OpenFOAM-8/etc/bashrc; set -u
cd "$WM_PROJECT_DIR"
./Allwmake -j "$(nproc)" -q
grep -q "OpenFOAM-8/etc/bashrc" "$HOME/.bashrc" || echo "source \$HOME/OpenFOAM/OpenFOAM-8/etc/bashrc" >> "$HOME/.bashrc"

echo "Vérification :"
pimpleFoam -help | head -3 && echo "OpenFOAM 8 opérationnel"

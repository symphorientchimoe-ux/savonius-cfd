# Oracle Cloud Always Free : une machine permanente

Oracle donne à vie une machine virtuelle ARM (processeurs Ampere A1), sans limite de durée de calcul. C'est la seule option de la liste qui tourne jour et nuit sans reprise à gérer.

Le quota a changé en 2026. Oracle a ramené l'offre de 4 OCPU et 24 Go à 2 OCPU et 12 Go à partir du 15 juin 2026, sans annonce officielle ([InfoQ, juillet 2026](https://infoq.com/news/2026/07/oracle-cloud-free-tier-limits/)). Certaines sources disent que l'ancien quota reste toléré sur les comptes existants, ce qui n'aide pas pour un nouveau compte. Sur Ampere, 1 OCPU vaut 1 cœur physique : 2 OCPU font donc à peu près la vitesse de la station locale, mais sans la partager avec la gazéification. Avant de créer la machine, vérifier le quota sur la [page officielle](https://docs.oracle.com/en-us/iaas/Content/FreeTier/resourceref.htm).

L'inscription demande une carte bancaire pour vérifier l'identité. Les ressources « Always Free » ne sont pas facturées tant que le compte reste en offre gratuite. Il ne faut pas passer le compte en paiement à l'usage : selon les mêmes sources, une machine au-dessus du nouveau quota serait alors facturée.

## Contenu

- `installer_openfoam8.sh` : compile OpenFOAM 8 depuis les sources sur Ubuntu 22.04 (ARM ou x86), avec gcc 9. Comptez 2 à 4 h. Il n'existe pas d'image Docker d'OpenFOAM 8 pour ARM, d'où la compilation.
- `lancer_balayage.sh` : enchaîne les λ sur tous les cœurs, sans budget de temps, et saute ceux qui sont déjà finis.

## Marche à suivre

1. S'inscrire sur oracle.com/cloud/free et choisir une région d'origine proche (elle ne pourra plus être changée). Les machines A1 manquent souvent dans les régions chargées. Si la création échoue faute de capacité, réessayer plus tard.
2. Compute > Instances > Create : image Canonical Ubuntu 22.04 (aarch64), forme VM.Standard.A1.Flex avec 2 OCPU et 12 Go, disque de démarrage de 100 Go. Télécharger la clé SSH proposée.
3. Se connecter : `ssh -i cle.key ubuntu@ADRESSE_IP`.
4. Depuis ce dossier, sur la station, copier les scripts et le paquet (fabriqué par `../commun/preparer_paquet.sh .`), puis installer :
   ```bash
   scp -i cle.key installer_openfoam8.sh lancer_balayage.sh savonius_paquet.tar.gz ubuntu@ADRESSE_IP:
   ssh -i cle.key ubuntu@ADRESSE_IP
   tmux new -s install 'bash installer_openfoam8.sh 2>&1 | tee install.log'
   ```
5. Une fois OpenFOAM installé :
   ```bash
   tar xzf savonius_paquet.tar.gz        # crée ~/savonius
   tmux new -s cfd 'bash lancer_balayage.sh ~/savonius "0.2 0.4 0.6 0.8 1.0 1.2" 4'
   ```
   Détacher avec Ctrl-b puis d. On peut fermer la session SSH.
6. Rapatrier les résultats : `scp -r -i cle.key ubuntu@ADRESSE_IP:savonius/runs .`

Avant de créer le compte, on peut lancer le workflow `test_oracle_arm.yml` du dépôt GitHub. Il exécute `installer_openfoam8.sh` sur une machine ARM Ubuntu 22.04 et fait 60 s de calcul, ce qui vérifie le script sans rien risquer.

La même machine peut servir à la gazéification : le solveur `porousGasificationFoam` est écrit pour OpenFOAM 8 et se recompilerait de la même façon.

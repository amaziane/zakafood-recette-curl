#!/usr/bin/env bash
# Lance la recette complète de zakafood.com en ligne de commande.
#   ./run.sh              tout, puis nettoyage
#   ./run.sh --keep       tout, sans supprimer commandes ni compte (pour les inspecter)
#   ./run.sh 03 04        seulement ces étapes (réutilise l'état du dernier run)
#   ./run.sh cleanup      supprime ce que le dernier run a laissé
cd "$(dirname "$0")"
. ./lib.sh

for v in TEST_EMAIL WP_ADMIN_USER WP_APP_PASSWORD; do
  eval "[ -n \"\$$v\" ]" || { echo "Renseigne $v dans .env" >&2; exit 1; }
done

KEEP=0; STEPS=()
for a in "$@"; do case "$a" in --keep) KEEP=1;; cleanup) STEPS=(07);; *) STEPS+=("$a");; esac; done

if [ ${#STEPS[@]} -eq 0 ]; then
  [ -n "$CLIENT_ID$ORDER_BACS$ORDER_COD" ] && bash tests/07_nettoyage.sh   # restes d'un run précédent
  : > "$WORK/state.env"; : > "$RESULTS"
  STEPS=(01 02 03 04 05 06); [ "$KEEP" = "0" ] && STEPS+=(07)
  . ./lib.sh
  state_set RUN_ID "$(date +%m%d%H%M)"
  mail_baseline; state_set RUN_MAIL_BASE "$MAIL_BASE"
  echo "Run $RUN_ID sur $BASE_URL — e-mails de test vers $(make_email '…')"
else
  [ -z "$RUN_ID" ] && { state_set RUN_ID "$(date +%m%d%H%M)"; mail_baseline; state_set RUN_MAIL_BASE "$MAIL_BASE"; }
fi

for s in "${STEPS[@]}"; do
  f=$(ls tests/${s}_*.sh 2>/dev/null | head -1)
  [ -z "$f" ] && { echo "Étape inconnue : $s"; continue; }
  bash "$f" || echo "${R}  → étape $s interrompue${N}"
done
bash tests/99_rapport.sh

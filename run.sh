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

# Vérification préalable de l'accès admin à l'API (mot de passe d'application)
echo "Python : $PYBIN"
rest GET "/wp/v2/users/me?context=edit"
if [ "$REST_CODE" != "200" ]; then
  echo "${R}Accès API admin refusé (HTTP $REST_CODE).${N}" >&2
  echo "  - WP_ADMIN_USER = identifiant de connexion (pas l'e-mail ni le nom affiché) : '$WP_ADMIN_USER'" >&2
  echo "  - WP_APP_PASSWORD = mot de passe d'application (24 caractères, espaces acceptés) — ${#WP_APP_PASSWORD} caractères lus" >&2
  echo "  - Si les deux sont bons, l'hébergeur retire l'en-tête Authorization : ajoute en haut du .htaccess :" >&2
  echo "      SetEnvIf Authorization \"(.*)\" HTTP_AUTHORIZATION=\$1" >&2
  head -c 300 "$WORK/rest.json" >&2; echo >&2
  exit 1
fi
echo "API admin OK : $(rj 'd["name"]') ($(rj '",".join(d.get("roles",[]))'))"

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

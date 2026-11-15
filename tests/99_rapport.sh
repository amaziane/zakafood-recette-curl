#!/usr/bin/env bash
# Récapitulatif : résultats des tests + tous les e-mails partis pendant le run (journal SureMails).
. "$(dirname "$0")/../lib.sh"

echo; echo "${B}== Récapitulatif du run $RUN_ID ==${N}"
for s in PASS FAIL WARN; do printf '  %-5s %s\n' "$s" "$(grep -c "^$s	" "$RESULTS")"; done
if grep -q '^FAIL' "$RESULTS"; then
  echo; echo "${R}Échecs :${N}"; grep '^FAIL' "$RESULTS" | awk -F'\t' '{printf "  - [%s] %s : %s\n", $2, $3, $4}'
fi
if grep -q '^WARN' "$RESULTS"; then
  echo; echo "${Y}Points à regarder :${N}"; grep '^WARN' "$RESULTS" | awk -F'\t' '{printf "  - [%s] %s : %s\n", $2, $3, $4}'
fi

echo; echo "${B}E-mails envoyés pendant le run (à vérifier dans les boîtes) :${N}"
mail_fetch
if [ "$REST_CODE" = "200" ] && [ "${RUN_MAIL_BASE:--1}" != "-1" ]; then
  $PY mails "$WORK/maillogs.json" "$RUN_MAIL_BASE" "." "." | sort -n > "$WORK/emails-run.tsv"
  awk -F'\t' '{printf "  %s  %-7s  %-40s  %s\n", $2, $3, $4, $5}' "$WORK/emails-run.tsv"
  echo "  ($(wc -l < "$WORK/emails-run.tsv" | tr -d ' ') e-mails — liste dans .work/emails-run.tsv)"
else
  echo "  Journal SureMails inaccessible (HTTP $REST_CODE) : vérifie directement les boîtes."
fi
echo; echo "Adresses utilisées : contact=$CONTACT_EMAIL | newsletter=$NEWS_EMAIL | client=$CLIENT_EMAIL"
grep -q '^FAIL' "$RESULTS" && exit 1 || exit 0

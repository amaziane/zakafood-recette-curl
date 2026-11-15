#!/usr/bin/env bash
# Supprime ce que la suite a créé : commandes et compte client de test.
. "$(dirname "$0")/../lib.sh"
section "07 · Nettoyage"

for o in $ORDER_BACS $ORDER_COD; do
  rest DELETE "/wc/v3/orders/$o?force=true"
  [ "$REST_CODE" = "200" ] && pass "Commande #$o supprimée" || warn "Commande #$o supprimée" "HTTP $REST_CODE"
done
state_set ORDER_BACS ""; state_set ORDER_COD ""

if [ -n "$CLIENT_ID" ]; then
  rest GET /wp/v2/users/me; ME=$(rj 'd["id"]')
  rest DELETE "/wp/v2/users/$CLIENT_ID?force=true&reassign=$ME"
  [ "$REST_CODE" = "200" ] && pass "Compte client #$CLIENT_ID supprimé" || warn "Compte client #$CLIENT_ID supprimé" "HTTP $REST_CODE"
  state_set CLIENT_ID ""
fi

info "À supprimer à la main si besoin" "entrées SureForms (contact $CONTACT_EMAIL, newsletter $NEWS_EMAIL) et l'abonné newsletter éventuel"

#!/usr/bin/env bash
# Panier (vente au carton) + commande classique : virement bancaire puis paiement à la livraison,
# puis cycle de vie des commandes côté back-office (statuts, note client).
. "$(dirname "$0")/../lib.sh"
section "06 · Panier et commandes"
mail_baseline

[ -z "$CLIENT_EMAIL" ] && die "Pré-requis" "aucun client de test : lance 03 à 05"
J="$WORK/client.jar"; P="$WORK/page.html"; O="$WORK/checkout.json"
ESC=$(re_escape "$CLIENT_EMAIL")
logged_in "$J" || die "Session client" "pas de session : relance 05_connexion.sh"

PID=${PRODUCT_ID:-$PID}
[ -z "$PID" ] && die "Produit" "renseigne PRODUCT_ID dans .env (ou lance 01_smoke.sh)"
rest GET "/wc/v3/products/$PID"
PNAME=$(rj 'd["name"]'); PACK=$(rj 'next((m["value"] for m in d["meta_data"] if m["key"]=="zk_colisage"), "")')
info "Produit commandé" "#$PID $PNAME ${PACK:+(colisage $PACK)}"

add_to_cart() {
  req "$J" POST "/?wc-ajax=add_to_cart" "$WORK/atc.json" --data "product_id=$PID&quantity=1"
  if grep -q 'cart_hash' "$WORK/atc.json" && ! grep -q '"error":true' "$WORK/atc.json"; then
    pass "Ajout au panier" "produit #$PID, quantité demandée 1"
  else
    die "Ajout au panier" "HTTP $HTTP_CODE — $(head -c 200 "$WORK/atc.json")"
  fi
}

# checkout MOYEN -> ORDER_ID
checkout() {
  local pm=$1
  req "$J" GET "$(cb /commander/)" "$P"
  local nonce ship
  nonce=$($PY field "$P" woocommerce-checkout woocommerce-process-checkout-nonce)
  [ -z "$nonce" ] && die "Page commande ($pm)" "formulaire absent (HTTP $HTTP_CODE ${HTTP_REDIRECT:+→ $HTTP_REDIRECT})"
  ship=$($PY radio "$P" woocommerce-checkout 'shipping_method[0]')
  [ -z "$ship" ] && ship=$(grep -o 'name="shipping_method\[0\]"[^>]*value="[^"]*"' "$P" | head -1 | sed 's/.*value="\([^"]*\)"/\1/')
  grep -q "id=\"payment_method_$pm\"" "$P" && pass "Moyen de paiement proposé : $pm" || fail "Moyen de paiement proposé : $pm" "absent de la page commande"

  # Champs pré-remplis par le compte, complétés par nos valeurs par défaut si vides
  local args=() line n v
  while IFS="$(printf '\t')" read -r n v; do
    [ -z "$v" ] && case "$n" in
      billing_first_name) v="Test";; billing_last_name) v="Recette auto";; billing_company) v="$TEST_COMPANY";;
      billing_country) v="$TEST_COUNTRY";; billing_address_1) v="$TEST_ADDRESS";; billing_postcode) v="$TEST_POSTCODE";;
      billing_city) v="$TEST_CITY";; billing_phone) v="$TEST_PHONE";; billing_email) v="$CLIENT_EMAIL";;
    esac
    args+=(--data-urlencode "$n=$v")
  done < <($PY fields "$P" woocommerce-checkout '^(billing_|shipping_|order_comments$|account_)')
  for n in billing_first_name billing_last_name billing_country billing_address_1 billing_postcode billing_city billing_phone billing_email; do
    printf '%s\n' "${args[@]}" | grep -q "^$n=" || case "$n" in
      billing_first_name) args+=(--data-urlencode "$n=Test");; billing_last_name) args+=(--data-urlencode "$n=Recette auto");;
      billing_country) args+=(--data-urlencode "$n=$TEST_COUNTRY");; billing_address_1) args+=(--data-urlencode "$n=$TEST_ADDRESS");;
      billing_postcode) args+=(--data-urlencode "$n=$TEST_POSTCODE");; billing_city) args+=(--data-urlencode "$n=$TEST_CITY");;
      billing_phone) args+=(--data-urlencode "$n=$TEST_PHONE");; billing_email) args+=(--data-urlencode "$n=$CLIENT_EMAIL");;
    esac
  done
  args+=(--data-urlencode "order_comments=Commande de TEST automatique (run $RUN_ID) — ne pas livrer.")
  args+=(--data-urlencode "ship_to_different_address=0" --data-urlencode "payment_method=$pm")
  [ -n "$ship" ] && args+=(--data-urlencode "shipping_method[0]=$ship")
  grep -q 'name="terms"' "$P" && args+=(--data-urlencode "terms=on" --data-urlencode "terms-field=1")
  args+=(--data-urlencode "woocommerce-process-checkout-nonce=$nonce" --data-urlencode "_wp_http_referer=/?wc-ajax=update_order_review")

  req "$J" POST "/?wc-ajax=checkout" "$O" -H "Referer: $BASE_URL/commander/" "${args[@]}"
  if [ "$($PY jget "$O" 'd.get("result")')" = "success" ]; then
    ORDER_ID=$($PY jget "$O" 'd.get("order_id") or re.search(r"order-received/(\d+)", d["redirect"]).group(1)')
    pass "Commande passée ($pm)" "commande #$ORDER_ID, livraison '$ship'"
    req "$J" GET "$($PY jget "$O" 'd["redirect"]')" "$P"
    [ "$HTTP_CODE" = "200" ] && grep -q 'woocommerce-order' "$P" && pass "Page de confirmation ($pm)" || warn "Page de confirmation ($pm)" "HTTP $HTTP_CODE"
    [ "$pm" = "bacs" ] && { grep -qi 'IBAN\|BIC\|virement' "$P" && pass "Coordonnées bancaires sur la confirmation" || warn "Coordonnées bancaires sur la confirmation" "IBAN/BIC non trouvés"; }
  else
    ORDER_ID=""
    fail "Commande passée ($pm)" "$($PY jget "$O" 're.sub(r"<[^>]+>"," ",d.get("messages","")).strip()[:300]' 2>/dev/null || head -c 300 "$O")"
  fi
}

# ---------- Commande 1 : virement ----------
add_to_cart
req "$J" GET /panier/ "$P"
if [ -n "$PACK" ] && [ "$PACK" -gt 1 ] 2>/dev/null; then
  Q=$(grep -o 'name="cart\[[^]]*\]\[qty\]"[^>]*value="[0-9]*"' "$P" | head -1 | sed 's/.*value="\([0-9]*\)"/\1/')
  [ "$Q" = "$PACK" ] && pass "Arrondi au carton" "1 demandé → $Q au panier" || warn "Arrondi au carton" "quantité panier='$Q', colisage=$PACK"
fi
grep -q 'woocommerce-Price-amount' "$P" && pass "Panier : montants affichés" || warn "Panier : montants affichés" "aucun montant"
checkout bacs; ORDER_BACS=$ORDER_ID; state_set ORDER_BACS "$ORDER_BACS"

# ---------- Commande 2 : paiement à la livraison ----------
add_to_cart
checkout cod; ORDER_COD=$ORDER_ID; state_set ORDER_COD "$ORDER_COD"

# ---------- Vérifications back-office ----------
check_status() { rest GET "/wc/v3/orders/$1"; local s; s=$(rj 'd["status"]')
  [ "$s" = "$2" ] && pass "Commande #$1 au statut $2" "total $(rj 'd["total"]') $(rj 'd["currency"]')" || fail "Commande #$1 au statut $2" "statut réel : $s"; }
[ -n "$ORDER_BACS" ] && check_status "$ORDER_BACS" on-hold
[ -n "$ORDER_COD" ]  && check_status "$ORDER_COD" processing

[ -n "$ORDER_BACS" ] && expect_mail "confirmation commande virement (client, avec RIB)" "$ESC" "$ORDER_BACS|commande|reçu|attente"
[ -n "$ORDER_COD" ]  && expect_mail "confirmation commande livraison (client)" "$ESC" "$ORDER_COD"
[ -n "$ORDER_BACS" ] && expect_mail "nouvelle commande virement (admin)" "^((?!$ESC).)*$" "$ORDER_BACS"
[ -n "$ORDER_COD" ]  && expect_mail "nouvelle commande livraison (admin)" "^((?!$ESC).)*$" "$ORDER_COD"

# Cycle de vie : virement reçu → en cours → terminée ; note au client
if [ -n "$ORDER_BACS" ]; then
  mail_baseline
  rest PUT "/wc/v3/orders/$ORDER_BACS" '{"status":"processing"}'
  [ "$REST_CODE" = "200" ] && pass "Virement reçu : #$ORDER_BACS → en cours" || fail "Passage en cours" "HTTP $REST_CODE"
  expect_mail "commande en cours de traitement (client)" "$ESC" "$ORDER_BACS"
  mail_baseline
  rest POST "/wc/v3/orders/$ORDER_BACS/notes" '{"note":"Note de test : votre commande est prête (recette automatique).","customer_note":true}'
  [ "$REST_CODE" = "201" ] && pass "Note client ajoutée" || fail "Note client ajoutée" "HTTP $REST_CODE"
  expect_mail "note ajoutée à la commande (client)" "$ESC" "note|$ORDER_BACS"
  mail_baseline
  rest PUT "/wc/v3/orders/$ORDER_BACS" '{"status":"completed"}'
  [ "$REST_CODE" = "200" ] && pass "Commande #$ORDER_BACS → terminée" || fail "Passage terminée" "HTTP $REST_CODE"
  expect_mail "commande terminée (client)" "$ESC" "$ORDER_BACS|terminée|livrée|complét"
fi
if [ -n "$ORDER_COD" ]; then
  mail_baseline
  rest PUT "/wc/v3/orders/$ORDER_COD" '{"status":"cancelled"}'
  [ "$REST_CODE" = "200" ] && pass "Commande #$ORDER_COD → annulée" || fail "Annulation" "HTTP $REST_CODE"
  expect_mail "commande annulée (admin)" "." "$ORDER_COD|annul"
fi

req "$J" GET /mon-compte/orders/ "$P"
[ -n "$ORDER_BACS" ] && { grep -q "$ORDER_BACS" "$P" && pass "Commande visible dans Mon compte" || warn "Commande visible dans Mon compte" "#$ORDER_BACS absente de /mon-compte/orders/"; }

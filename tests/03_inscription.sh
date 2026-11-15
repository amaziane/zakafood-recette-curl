#!/usr/bin/env bash
# Formulaire « Devenir client » (WooCommerce + B2BKing + snippet Zaka Food n°6).
. "$(dirname "$0")/../lib.sh"
section "03 · Devenir client (inscription B2B)"
mail_baseline

J="$WORK/reg.jar"; P="$WORK/page.html"; O="$WORK/reg-result.html"
EMAIL=$(make_email client); state_set CLIENT_EMAIL "$EMAIL"

# register EMAIL TVA CGV(on|"")  -> poste le formulaire avec un nonce frais
register() {
  rm -f "$J"
  req "$J" GET "$(cb /devenir-client/)" "$P"
  local nonce role
  nonce=$($PY field "$P" zk-reg-form woocommerce-register-nonce)
  role=$($PY field "$P" zk-reg-form b2bking_registration_roles_dropdown)
  [ -z "$nonce" ] && die "Devenir client : formulaire" "nonce introuvable sur /devenir-client/"
  local args=(--data-urlencode "zk_first_name=Test" --data-urlencode "zk_last_name=Recette auto"
    --data-urlencode "zk_company=$TEST_COMPANY" --data-urlencode "zk_vat=$2"
    --data-urlencode "zk_activity=$TEST_ACTIVITY" --data-urlencode "zk_phone=$TEST_PHONE"
    --data-urlencode "email=$1" --data-urlencode "b2bking_registration_roles_dropdown=$role"
    --data-urlencode "zk_devenir_client=1" --data-urlencode "woocommerce-register-nonce=$nonce"
    --data-urlencode "_wp_http_referer=/devenir-client/" --data-urlencode "register=Créer mon compte pro")
  [ -n "$3" ] && args+=(--data-urlencode "zk_cgv=$3")
  req "$J" POST /devenir-client/ "$O" -H "Referer: $BASE_URL/devenir-client/" "${args[@]}"
}
has_error() { grep -q 'woocommerce-error' "$O"; }

# ---- Cas négatifs (aucun compte créé) ----
register "$EMAIL" "" "on"
has_error && grep -qi 'TVA' "$O" && pass "Refus sans n° de TVA" || fail "Refus sans n° de TVA" "HTTP $HTTP_CODE ${HTTP_REDIRECT}"
register "$EMAIL" "$TEST_VAT" ""
has_error && grep -qi 'conditions' "$O" && pass "Refus sans CGV cochées" || fail "Refus sans CGV cochées" "HTTP $HTTP_CODE ${HTTP_REDIRECT}"
register "pas-un-email" "$TEST_VAT" "on"
has_error && pass "Refus e-mail invalide" || fail "Refus e-mail invalide" "HTTP $HTTP_CODE"

# ---- Inscription réelle ----
rest GET "/wc/v3/customers?email=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$EMAIL")&role=all"
if [ "$REST_CODE" != "200" ]; then die "Accès API admin" "HTTP $REST_CODE : vérifie WP_ADMIN_USER / WP_APP_PASSWORD"; fi
[ "$(rj 'len(d)')" != "0" ] && die "Compte de test" "$EMAIL existe déjà (lance ./run.sh cleanup ou change TEST_EMAIL)"

register "$EMAIL" "$TEST_VAT" "on"
if has_error; then
  fail "Inscription" "$(grep -o '<li[^>]*>[^<]*' "$O" | sed 's/<[^>]*>//' | head -3 | tr '\n' ' ')"
  exit 1
fi
pass "Inscription envoyée" "HTTP $HTTP_CODE ${HTTP_REDIRECT:+→ $HTTP_REDIRECT}"
logged_in "$J" && warn "Session après inscription" "le compte en attente est connecté automatiquement" \
               || pass "Session après inscription" "pas de connexion tant que le compte n'est pas validé"

sleep 2
rest GET "/wc/v3/customers?email=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$EMAIL")&role=all"
UID_=$(rj 'd[0]["id"]')
if [ -z "$UID_" ]; then die "Compte créé" "aucun client $EMAIL côté WooCommerce"; fi
state_set CLIENT_ID "$UID_"
pass "Compte créé" "user #$UID_"
APPROVED=$(rj 'next((m["value"] for m in d[0]["meta_data"] if m["key"]=="b2bking_account_approved"), "absent")')
[ "$APPROVED" = "no" ] && pass "Compte en attente de validation" "b2bking_account_approved=no" \
                       || warn "Compte en attente de validation" "b2bking_account_approved=$APPROVED"
CO=$(rj 'd[0]["billing"]["company"]'); PH=$(rj 'd[0]["billing"]["phone"]')
[ "$CO" = "$TEST_COMPANY" ] && pass "Société enregistrée" "$CO" || warn "Société enregistrée" "billing.company='$CO'"
[ -n "$PH" ] && pass "Téléphone enregistré" "$PH" || warn "Téléphone enregistré" "billing.phone vide"
VAT=$(rj 'next((m["value"] for m in d[0]["meta_data"] if "vat" in m["key"].lower() or "tva" in m["key"].lower()), "")')
[ -n "$VAT" ] && pass "TVA enregistrée" "$VAT" || warn "TVA enregistrée" "aucune meta *vat*/*tva* trouvée"

# Doublon
register "$EMAIL" "$TEST_VAT" "on"
has_error && pass "Refus e-mail déjà inscrit" || fail "Refus e-mail déjà inscrit" "HTTP $HTTP_CODE"

# Connexion refusée tant que non validé : on fixe un mot de passe connu (par l'API admin) puis on tente de se connecter
rest POST "/wp/v2/users/$UID_" "{\"password\":\"$TEST_PASSWORD\"}"
[ "$REST_CODE" = "200" ] && info "Mot de passe de test fixé" "via API (peut déclencher l'e-mail « mot de passe modifié »)" \
                         || warn "Mot de passe de test fixé" "HTTP $REST_CODE"
rm -f "$J"; req "$J" GET "$(cb /mon-compte/)" "$P"
LN=$($PY field "$P" woocommerce-form-login woocommerce-login-nonce)
req "$J" POST /mon-compte/ "$O" --data-urlencode "username=$EMAIL" --data-urlencode "password=$TEST_PASSWORD" \
  --data-urlencode "woocommerce-login-nonce=$LN" --data-urlencode "_wp_http_referer=/mon-compte/" --data-urlencode "login=Se connecter"
logged_in "$J" && fail "Connexion bloquée avant validation" "la session s'est ouverte" \
               || pass "Connexion bloquée avant validation"

ESC=$(re_escape "$EMAIL")
expect_mail "accusé de réception au client" "$ESC" "."
expect_mail "alerte nouveau client à valider (admin)" "^((?!$ESC).)*$" "client|compte|inscription|approb|valid"

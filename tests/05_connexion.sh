#!/usr/bin/env bash
# Connexion client, mauvais mot de passe, mot de passe perdu, prix visibles une fois connecté.
. "$(dirname "$0")/../lib.sh"
section "05 · Connexion et mot de passe"
mail_baseline

[ -z "$CLIENT_EMAIL" ] && die "Pré-requis" "aucun client de test : lance 03 puis 04"
J="$WORK/client.jar"; P="$WORK/page.html"; O="$WORK/login.html"
ESC=$(re_escape "$CLIENT_EMAIL")

login() { # login JAR MOTDEPASSE
  rm -f "$1"
  req "$1" GET "$(cb /mon-compte/)" "$P"
  local n; n=$($PY field "$P" woocommerce-form-login woocommerce-login-nonce)
  req "$1" POST /mon-compte/ "$O" --data-urlencode "username=$CLIENT_EMAIL" --data-urlencode "password=$2" \
    --data-urlencode "rememberme=forever" --data-urlencode "woocommerce-login-nonce=$n" \
    --data-urlencode "_wp_http_referer=/mon-compte/" --data-urlencode "login=Se connecter"
}

login "$WORK/bad.jar" "mauvais-mot-de-passe"
logged_in "$WORK/bad.jar" && fail "Mauvais mot de passe refusé" || pass "Mauvais mot de passe refusé"

login "$J" "$TEST_PASSWORD"
if logged_in "$J"; then
  pass "Connexion client" "HTTP $HTTP_CODE ${HTTP_REDIRECT:+→ $HTTP_REDIRECT}"
else
  die "Connexion client" "pas de session ($(grep -o 'woocommerce-error[^<]*<li>[^<]*' "$O" | sed 's/.*<li>//' | head -1))"
fi

req "$J" GET /mon-compte/ "$P"
grep -q 'woocommerce-MyAccount-navigation' "$P" && pass "Tableau de bord Mon compte" || fail "Tableau de bord Mon compte" "navigation absente"
for ep in orders edit-address edit-account; do
  req "$J" GET "/mon-compte/$ep/" "$P" -L
  [ "$HTTP_CODE" = "200" ] && grep -q 'woocommerce-MyAccount-content' "$P" && pass "Mon compte › $ep" || warn "Mon compte › $ep" "HTTP $HTTP_CODE"
done

req "$J" GET "$(cb /boutique/)" "$P"
grep -q 'woocommerce-Price-amount' "$P" && pass "Prix visibles pour un client validé" || fail "Prix visibles pour un client validé" "aucun montant sur /boutique/"
req "$J" GET /panier/ "$P"
[ "$HTTP_CODE" = "200" ] && pass "Accès au panier" || fail "Accès au panier" "HTTP $HTTP_CODE ${HTTP_REDIRECT:+→ $HTTP_REDIRECT}"

# Mot de passe perdu (sans session)
L="$WORK/lost.jar"; rm -f "$L"
req "$L" GET "$(cb /mon-compte/mot-de-passe-perdu/)" "$P"
LPN=$($PY field "$P" lost_reset_password woocommerce-lost-password-nonce)
if [ -n "$LPN" ]; then
  req "$L" POST /mon-compte/mot-de-passe-perdu/ "$O" --data-urlencode "user_login=$CLIENT_EMAIL" \
    --data-urlencode "wc_reset_password=true" --data-urlencode "woocommerce-lost-password-nonce=$LPN" \
    --data-urlencode "_wp_http_referer=/mon-compte/mot-de-passe-perdu/"
  case "$HTTP_REDIRECT" in *reset-link-sent*) pass "Mot de passe perdu" "lien envoyé";;
    *) grep -q 'woocommerce-error' "$O" && fail "Mot de passe perdu" "erreur affichée" || pass "Mot de passe perdu" "HTTP $HTTP_CODE";; esac
  expect_mail "réinitialisation du mot de passe" "$ESC" "mot de passe|password|réinitialis"
else
  fail "Mot de passe perdu" "formulaire introuvable"
fi

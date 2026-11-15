#!/usr/bin/env bash
# Validation du compte comme le fait l'équipe dans « Clients Zaka Food » (snippet n°43, action AJAX zk_clients_do).
. "$(dirname "$0")/../lib.sh"
section "04 · Validation du compte par l'équipe"
mail_baseline

[ -z "$CLIENT_ID" ] && die "Pré-requis" "aucun client de test : lance d'abord 03_inscription.sh"
A="$WORK/admin.jar"; P="$WORK/page.html"; O="$WORK/ajax.json"
ESC=$(re_escape "$CLIENT_EMAIL")
VIA_AJAX=0

if [ -n "$WP_ADMIN_PASSWORD" ]; then
  rm -f "$A"
  req "$A" GET /wp-login.php "$P"
  req "$A" POST /wp-login.php "$P" -b "wordpress_test_cookie=WP%20Cookie%20check" \
    --data-urlencode "log=$WP_ADMIN_USER" --data-urlencode "pwd=$WP_ADMIN_PASSWORD" \
    --data-urlencode "wp-submit=Se connecter" --data-urlencode "redirect_to=$BASE_URL/wp-admin/" --data-urlencode "testcookie=1"
  if logged_in "$A"; then
    pass "Connexion admin (wp-login)"
    req "$A" GET "/wp-admin/admin.php?page=zk-clients" "$P"
    NONCE=$(grep -o '"ajax":"[^"]*","nonce":"[0-9a-f]*"' "$P" | head -1 | sed 's/.*"nonce":"\([0-9a-f]*\)"/\1/')
    if [ -n "$NONCE" ]; then
      grep -q "$CLIENT_EMAIL" "$P" && pass "Client visible dans « Clients Zaka Food »" || warn "Client visible dans « Clients Zaka Food »" "e-mail absent de la page (liste chargée en JS ?)"
      req "$A" POST /wp-admin/admin-ajax.php "$O" \
        --data "action=zk_clients_do" --data "nonce=$NONCE" --data "do=valider" --data "ids[]=$CLIENT_ID" \
        --data "mail_b2bking=1" --data "mail_pwd=1"
      if $PY jget "$O" 'd.get("success") is True' | grep -q True; then
        pass "Validation via Clients Zaka Food" "$(head -c 200 "$O")"; VIA_AJAX=1
      else
        fail "Validation via Clients Zaka Food" "HTTP $HTTP_CODE — $(head -c 300 "$O")"
      fi
    else
      fail "Écran Clients Zaka Food" "jeton AJAX introuvable sur admin.php?page=zk-clients"
    fi
  else
    warn "Connexion admin (wp-login)" "échec (2FA, captcha ou SSO Jetpack ?) — bascule sur l'API"
  fi
fi

if [ "$VIA_AJAX" = "0" ]; then
  info "Validation par API" "méta B2BKing posées directement ; e-mail d'approbation non déclenché"
  rest PUT "/wc/v3/customers/$CLIENT_ID" '{"meta_data":[{"key":"b2bking_account_approved","value":"yes"},{"key":"b2bking_b2buser","value":"yes"}]}'
  [ "$REST_CODE" = "200" ] && pass "Validation par API" || fail "Validation par API" "HTTP $REST_CODE"
fi

rest GET "/wc/v3/customers/$CLIENT_ID"
AP=$(rj 'next((m["value"] for m in d["meta_data"] if m["key"]=="b2bking_account_approved"), "absent")')
GR=$(rj 'next((m["value"] for m in d["meta_data"] if m["key"]=="b2bking_customergroup"), "aucun")')
[ "$AP" = "yes" ] && pass "Compte validé" "groupe B2BKing : $GR" || fail "Compte validé" "b2bking_account_approved=$AP"

if [ "$VIA_AJAX" = "1" ]; then
  expect_mail "compte approuvé (B2BKing)" "$ESC" "^(?!.*(mot de passe|password)).*(approuv|valid|activ|bienvenue|compte)"
  expect_mail "lien de création du mot de passe" "$ESC" "mot de passe|password|réinitialis"
fi

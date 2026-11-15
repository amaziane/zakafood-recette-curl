#!/usr/bin/env bash
# Formulaire de contact (SureForms 898) et newsletter (SureForms 1370).
. "$(dirname "$0")/../lib.sh"
section "02 · Formulaires contact et newsletter"
mail_baseline

J="$WORK/forms.jar"; rm -f "$J"; P="$WORK/page.html"; O="$WORK/submit.json"

# srfm_submit FORMID HEADER_TOKEN champ=valeur...
srfm_submit() {
  local fid=$1 tok=$2; shift 2
  local args=(--form-string "form-id=$fid" --form-string "srfm-form-language=" --form-string "srfm-sender-email-field=")
  local kv; for kv in "$@"; do args+=(--form-string "$kv"); done
  req "$J" POST /wp-json/sureforms/v1/submit-form "$O" -H "X-WP-Submit-Token: $tok" -H "Referer: $BASE_URL/" "${args[@]}"
}

# ---- Contact ----
C_EMAIL=$(make_email contact); state_set CONTACT_EMAIL "$C_EMAIL"
req "$J" GET "$(cb /contact/)" "$P"
TOK=$($PY fattr "$P" srfm-form-898 data-submit-token)
if [ -z "$TOK" ]; then
  fail "Contact : formulaire trouvé" "pas de data-submit-token sur /contact/"
else
  f() { $PY fname "$P" srfm-form-898 "$1"; }
  # Cas négatif : sans e-mail ni message
  srfm_submit 898 "$TOK" "$(f -text-field)=Test" "$(f -last-name)=Recette"
  $PY jget "$O" 'd.get("success") is True' | grep -q True \
    && fail "Contact : champs obligatoires" "envoi accepté sans e-mail/message" \
    || pass "Contact : champs obligatoires" "envoi incomplet refusé (HTTP $HTTP_CODE)"

  req "$J" GET "$(cb /contact/)" "$P"; TOK=$($PY fattr "$P" srfm-form-898 data-submit-token)
  srfm_submit 898 "$TOK" \
    "$(f -text-field)=Test" "$(f -last-name)=Recette auto" "$(f -societe)=$TEST_COMPANY" \
    "$(f -email)=$C_EMAIL" "$(f -objet)=Autre demande" \
    "$(f -message)=Message envoyé par la suite de tests curl (run $RUN_ID). Merci de l'ignorer." \
    "$(f -gdpr)=on"
  if $PY jget "$O" 'd.get("success") is True' | grep -q True; then
    pass "Contact : envoi" "HTTP $HTTP_CODE"
    expect_mail "notification contact (admin)" "." "$RUN_ID|Recette auto|contact|demande|message"
  else
    fail "Contact : envoi" "HTTP $HTTP_CODE — $(head -c 300 "$O")"
  fi
fi

# ---- Newsletter ----
N_EMAIL=$(make_email news); state_set NEWS_EMAIL "$N_EMAIL"
req "$J" GET "$(cb /)" "$P"
TOK=$($PY fattr "$P" srfm-form-1370 data-submit-token)
EF=$($PY fname "$P" srfm-form-1370 -email)
if [ -z "$TOK" ] || [ -z "$EF" ]; then
  fail "Newsletter : formulaire trouvé" "formulaire 1370 absent de l'accueil"
else
  srfm_submit 1370 "$TOK" "$EF=pas-une-adresse"
  $PY jget "$O" 'd.get("success") is True' | grep -q True \
    && fail "Newsletter : e-mail invalide" "adresse invalide acceptée" \
    || pass "Newsletter : e-mail invalide" "refusé (HTTP $HTTP_CODE)"

  req "$J" GET "$(cb /)" "$P"; TOK=$($PY fattr "$P" srfm-form-1370 data-submit-token)
  srfm_submit 1370 "$TOK" "$EF=$N_EMAIL" "srfm-page-break="
  if $PY jget "$O" 'd.get("success") is True' | grep -q True; then
    pass "Newsletter : inscription" "$N_EMAIL"
    expect_mail "newsletter (abonné ou admin)" "." "newsletter|inscri|bienvenue|abonn|confirm"
  else
    fail "Newsletter : inscription" "HTTP $HTTP_CODE — $(head -c 300 "$O")"
  fi
fi

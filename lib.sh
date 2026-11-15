#!/usr/bin/env bash
# Fonctions communes à tous les tests (compatible bash 3.2 / macOS).
set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$ROOT/.env" ]; then
  echo "Fichier .env manquant : cp .env.example .env puis remplis-le." >&2
  exit 1
fi
set -a; . "$ROOT/.env"; set +a

BASE_URL="${BASE_URL:-https://zakafood.com}"; BASE_URL="${BASE_URL%/}"
MAIL_WAIT="${MAIL_WAIT:-90}"
WORK="$ROOT/.work"; mkdir -p "$WORK"
STATE="$WORK/state.env"; touch "$STATE"
RESULTS="$WORK/results.tsv"; touch "$RESULTS"
UA="ZakaFood-TestSuite/1.0 (curl)"
PY="python3 $ROOT/tools.py"
. "$STATE"

if [ -t 1 ]; then G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[36m'; N=$'\e[0m'; else G=; R=; Y=; B=; N=; fi

# ---------- résultats ----------
section() { echo; echo "${B}== $* ==${N}"; CUR_SECTION="$*"; }
_rec()    { printf '%s\t%s\t%s\t%s\n' "$1" "${CUR_SECTION:-}" "$2" "${3:-}" >> "$RESULTS"; }
pass()    { echo "  ${G}PASS${N} $1 ${2:+— $2}"; _rec PASS "$1" "${2:-}"; }
fail()    { echo "  ${R}FAIL${N} $1 ${2:+— $2}"; _rec FAIL "$1" "${2:-}"; }
warn()    { echo "  ${Y}WARN${N} $1 ${2:+— $2}"; _rec WARN "$1" "${2:-}"; }
info()    { echo "  ${B}INFO${N} $1 ${2:+— $2}"; _rec INFO "$1" "${2:-}"; }
die()     { fail "$1" "${2:-}"; exit 1; }

state_set() { # state_set CLE VALEUR
  grep -v "^$1=" "$STATE" > "$STATE.tmp" 2>/dev/null; mv "$STATE.tmp" "$STATE"
  printf "%s='%s'\n" "$1" "$2" >> "$STATE"; eval "$1='$2'"
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "Outil requis manquant : $1" >&2; exit 1; }; }
need curl; need python3

# ---------- HTTP ----------
u()  { case "$1" in http*) echo "$1" ;; *) echo "$BASE_URL$1" ;; esac; }
cb() { case "$1" in *\?*) echo "$1&zkt=$(date +%s)$RANDOM" ;; *) echo "$1?zkt=$(date +%s)$RANDOM" ;; esac; } # contourne le cache LiteSpeed

# req JAR METHOD PATH OUTFILE [args curl...]  -> écrit "code url_redirection temps" dans HTTP_* ; JAR="-" = sans cookies
req() {
  local jar=$1 m=$2 p=$3 o=$4; shift 4
  local meta
  if [ "$jar" = "-" ]; then
    meta=$(curl -sS -A "$UA" --max-time 60 -X "$m" -o "$o" -w '%{http_code} %{time_total} %{redirect_url}' "$@" "$(u "$p")")
  else
    meta=$(curl -sS -A "$UA" --max-time 60 -b "$jar" -c "$jar" -X "$m" -o "$o" -w '%{http_code} %{time_total} %{redirect_url}' "$@" "$(u "$p")")
  fi
  HTTP_CODE=${meta%% *}; meta=${meta#* }; HTTP_TIME=${meta%% *}; HTTP_REDIRECT=${meta#* }
  [ "$HTTP_REDIRECT" = "$HTTP_TIME" ] && HTTP_REDIRECT=""
}

# rest METHOD /chemin [json]  -> corps dans $WORK/rest.json, code dans REST_CODE (auth = mot de passe d'application)
rest() {
  local m=$1 p=$2 body=${3:-}
  if [ -n "$body" ]; then
    REST_CODE=$(curl -sS -A "$UA" --max-time 60 -u "$WP_ADMIN_USER:$WP_APP_PASSWORD" -X "$m" \
      -H 'Content-Type: application/json' --data "$body" -o "$WORK/rest.json" -w '%{http_code}' "$BASE_URL/wp-json$p")
  else
    REST_CODE=$(curl -sS -A "$UA" --max-time 60 -u "$WP_ADMIN_USER:$WP_APP_PASSWORD" -X "$m" \
      -o "$WORK/rest.json" -w '%{http_code}' "$BASE_URL/wp-json$p")
  fi
}
rj() { $PY jget "$WORK/rest.json" "$1"; }   # lit le dernier JSON REST

# ---------- e-mails (journal SureMails) ----------
mail_fetch() { rest POST /suremails/v1/email-logs '{"page":1,"per_page":100}'; cp "$WORK/rest.json" "$WORK/maillogs.json"; }
mail_baseline() {
  mail_fetch
  if [ "$REST_CODE" = "200" ]; then state_set MAIL_BASE "$($PY maxid "$WORK/maillogs.json")"; else state_set MAIL_BASE "-1"; fi
}
# expect_mail "libellé" "regex destinataire" "regex sujet"  -> attend jusqu'à MAIL_WAIT s
expect_mail() {
  local label=$1 rto=$2 rsub=$3 t=0 hit
  if [ "${MAIL_BASE:--1}" = "-1" ]; then warn "E-mail : $label" "journal SureMails illisible, vérifie la boîte à la main"; return; fi
  while :; do
    mail_fetch
    hit=$($PY mails "$WORK/maillogs.json" "$MAIL_BASE" "$rto" "$rsub" | head -1)
    if [ -n "$hit" ]; then
      local st; st=$(echo "$hit" | cut -f3)
      case "$st" in failed|error|blocked) fail "E-mail : $label" "statut $st — $(echo "$hit" | cut -f4-5)";;
        *) pass "E-mail : $label" "$(echo "$hit" | cut -f4) | $(echo "$hit" | cut -f5)";; esac
      return
    fi
    [ $t -ge "$MAIL_WAIT" ] && { fail "E-mail : $label" "rien dans le journal après ${MAIL_WAIT}s (dest. ~ /$rto/, sujet ~ /$rsub/)"; return; }
    sleep 10; t=$((t+10))
  done
}

# ---------- divers ----------
re_escape() { printf '%s' "$1" | sed 's/[.[\*^$()+?{|]/\\&/g'; }
logged_in() { grep -q 'wordpress_logged_in_' "$1" 2>/dev/null; }

# Adresse de test : TEST_EMAIL avec un tag +zk<run> si EMAIL_PLUS=1 (chaque run = compte neuf)
make_email() { # make_email suffixe
  local local_part=${TEST_EMAIL%@*} domain=${TEST_EMAIL#*@}
  if [ "${EMAIL_PLUS:-1}" = "1" ]; then echo "${local_part}+zk${RUN_ID}$1@${domain}"; else echo "$TEST_EMAIL"; fi
}

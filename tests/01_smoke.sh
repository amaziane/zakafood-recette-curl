#!/usr/bin/env bash
# Pages publiques, SEO technique, API, et règles B2B côté visiteur.
. "$(dirname "$0")/../lib.sh"
section "01 · Pages publiques et règles visiteur"

O="$WORK/page.html"
for p in / /boutique/ /notre-catalogue/ /meilleures-ventes/ /nos-promos/ /nos-marques/ /produits-zaka/ \
         /devenir-client/ /mon-compte/ /contact/ /a-propos/ /blog/ \
         /conditions-generales-de-vente/ /politique-de-confidentialite/ /politique-cookies/ /mentions-legales/; do
  req - GET "$p" "$O"
  if [ "$HTTP_CODE" = "200" ]; then
    t=${HTTP_TIME%.*}
    if [ "${t:-0}" -ge 3 ]; then warn "GET $p" "200 mais lent (${HTTP_TIME}s)"; else pass "GET $p" "200 en ${HTTP_TIME}s"; fi
    grep -qi '<title>' "$O" || warn "GET $p" "pas de <title>"
  else
    fail "GET $p" "HTTP $HTTP_CODE ${HTTP_REDIRECT:+→ $HTTP_REDIRECT}"
  fi
done

req - GET "/zk-page-inexistante-$(date +%s)/" "$O"
[ "$HTTP_CODE" = "404" ] && pass "Page inexistante" "404" || fail "Page inexistante" "HTTP $HTTP_CODE (attendu 404)"

req - GET /robots.txt "$O"
if [ "$HTTP_CODE" = "200" ]; then
  grep -qi 'sitemap' "$O" && pass "robots.txt" "référence le sitemap" || warn "robots.txt" "pas de ligne Sitemap"
  grep -qiE '^Disallow: /\s*$' "$O" && fail "robots.txt" "Disallow: / bloque tout le site"
else fail "robots.txt" "HTTP $HTTP_CODE"; fi

req - GET /sitemap_index.xml "$O"
[ "$HTTP_CODE" = "200" ] && grep -q '<sitemap' "$O" && pass "sitemap_index.xml" "$(grep -o '<loc>' "$O" | wc -l | tr -d ' ') sitemaps" || fail "sitemap_index.xml" "HTTP $HTTP_CODE"

req - GET / "$O" -H 'Accept: text/html'
grep -q 'application/ld+json' "$O" && pass "Accueil : données structurées" || warn "Accueil : données structurées" "pas de JSON-LD"
grep -qi 'name="description"' "$O" && pass "Accueil : meta description" || warn "Accueil : meta description" "absente"

# API publiques
req - GET /wp-json/ "$O"
[ "$HTTP_CODE" = "200" ] && pass "API REST WordPress" || fail "API REST WordPress" "HTTP $HTTP_CODE"
req - GET "/wp-json/wc/store/v1/products?per_page=20" "$WORK/products.json"
if [ "$HTTP_CODE" = "200" ]; then
  n=$($PY jget "$WORK/products.json" 'len(d)')
  pass "API Store : produits" "$n produits renvoyés"
else warn "API Store : produits" "HTTP $HTTP_CODE"; fi

# Règles B2B visiteur
req - GET "$(cb /boutique/)" "$O"
if grep -q 'woocommerce-Price-amount' "$O"; then
  fail "Prix masqués aux visiteurs" "des montants apparaissent sur /boutique/ pour un visiteur"
else pass "Prix masqués aux visiteurs" "aucun montant sur /boutique/"; fi

PID=${PRODUCT_ID:-$($PY jget "$WORK/products.json" 'next(p["id"] for p in d if p.get("is_purchasable") and p.get("is_in_stock"))' 2>/dev/null)}
PID=${PID:-$($PY jget "$WORK/products.json" 'd[0]["id"]' 2>/dev/null)}
if [ -n "$PID" ]; then
  state_set PID "$PID"
  J="$WORK/guest.jar"; rm -f "$J"
  req "$J" POST "/?wc-ajax=add_to_cart" "$O" --data "product_id=$PID&quantity=1"
  if grep -q '"error":true' "$O" || ! grep -q 'cart_hash' "$O"; then
    pass "Ajout panier refusé au visiteur" "produit $PID"
  else
    warn "Ajout panier refusé au visiteur" "un visiteur a pu ajouter le produit $PID au panier"
  fi
  req "$J" GET /commander/ "$O"
  grep -q 'woocommerce-process-checkout-nonce' "$O" \
    && fail "Commande impossible pour un visiteur" "le formulaire de commande s'affiche" \
    || pass "Commande impossible pour un visiteur" "HTTP $HTTP_CODE ${HTTP_REDIRECT:+→ $HTTP_REDIRECT}"
else
  warn "Produit de test" "aucun ID trouvé : renseigne PRODUCT_ID dans .env"
fi

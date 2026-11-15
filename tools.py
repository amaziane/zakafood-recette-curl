#!/usr/bin/env python3
"""Petits outils de parsing HTML/JSON pour la suite de tests Zaka Food (stdlib uniquement)."""
import json
import re
import sys
from html.parser import HTMLParser


class Forms(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.forms, self.cur, self.sel = [], None, None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "form":
            self.cur = {"attrs": a, "fields": []}
            self.forms.append(self.cur)
            return
        if self.cur is None:
            return
        if tag == "input":
            self.cur["fields"].append({
                "name": a.get("name"), "type": (a.get("type") or "text").lower(),
                "value": a.get("value") or "", "checked": "checked" in a,
            })
        elif tag == "select":
            self.sel = {"name": a.get("name"), "type": "select", "value": None, "options": []}
            self.cur["fields"].append(self.sel)
        elif tag == "option" and self.sel is not None:
            v = a.get("value") or ""
            self.sel["options"].append(v)
            if "selected" in a:
                self.sel["value"] = v
        elif tag == "textarea":
            self.cur["fields"].append({"name": a.get("name"), "type": "textarea", "value": ""})
        elif tag == "button" and a.get("name"):
            self.cur["fields"].append({"name": a.get("name"), "type": "submit", "value": a.get("value") or ""})

    def handle_endtag(self, tag):
        if tag == "form":
            self.cur = None
        elif tag == "select" and self.sel is not None:
            if self.sel["value"] is None:
                opts = [o for o in self.sel["options"] if o]
                self.sel["value"] = opts[0] if len(opts) == 1 else ""
            self.sel = None


def load_form(path, match):
    p = Forms()
    with open(path, encoding="utf-8", errors="replace") as f:
        p.feed(f.read())
    for fm in p.forms:
        hay = " ".join(str(v) for v in fm["attrs"].values())
        if match in hay:
            return fm
    return None


def out(v):
    if v is None:
        sys.exit(1)
    print(json.dumps(v, ensure_ascii=False) if isinstance(v, (dict, list)) else v)


def main():
    cmd, args = sys.argv[1], sys.argv[2:]

    if cmd == "field":  # field FILE FORMMATCH NAME -> valeur
        fm = load_form(args[0], args[1])
        out(next((x["value"] for x in fm["fields"] if x["name"] == args[2]), None) if fm else None)

    elif cmd == "fattr":  # fattr FILE FORMMATCH ATTR
        fm = load_form(args[0], args[1])
        out(fm["attrs"].get(args[2]) if fm else None)

    elif cmd == "fname":  # fname FILE FORMMATCH SUFFIX -> premier nom de champ finissant par SUFFIX
        fm = load_form(args[0], args[1])
        out(next((x["name"] for x in fm["fields"] if x["name"] and x["name"].endswith(args[2])), None) if fm else None)

    elif cmd == "fields":  # fields FILE FORMMATCH REGEX -> lignes "nom<TAB>valeur"
        fm = load_form(args[0], args[1])
        if not fm:
            sys.exit(1)
        rx, seen = re.compile(args[2]), set()
        for x in fm["fields"]:
            n = x["name"]
            if not n or not rx.search(n) or n in seen:
                continue
            if x["type"] in ("checkbox", "radio") and not x["checked"]:
                continue
            seen.add(n)
            print(f"{n}\t{x['value']}")

    elif cmd == "radio":  # radio FILE FORMMATCH NAME -> valeur cochée, sinon la première
        fm = load_form(args[0], args[1])
        rs = [x for x in (fm["fields"] if fm else []) if x["name"] == args[2]]
        pick = next((x for x in rs if x["checked"]), rs[0] if rs else None)
        out(pick["value"] if pick else None)

    elif cmd == "jget":  # jget FILE EXPR  (la donnée JSON s'appelle d)
        with open(args[0], encoding="utf-8", errors="replace") as f:
            raw = f.read()
        try:
            d = json.loads(raw)
        except ValueError:
            sys.exit(2)
        try:
            v = eval(args[1], {"d": d, "re": re})  # noqa: S307 (expressions écrites dans les scripts)
        except Exception:
            sys.exit(1)
        out(v)

    elif cmd == "mails":  # mails FILE MINID TO_REGEX SUBJECT_REGEX -> lignes TSV des mails correspondants
        with open(args[0], encoding="utf-8") as f:
            d = json.load(f)
        minid, rto, rsub = int(args[1]), re.compile(args[2], re.I), re.compile(args[3], re.I)
        for l in d.get("logs", []):
            if int(l.get("id", 0)) <= minid:
                continue
            to = l.get("email_to") or ""
            to = ", ".join(to) if isinstance(to, list) else str(to)
            if rto.search(to) and rsub.search(l.get("subject") or ""):
                print("\t".join([str(l.get("id")), l.get("created_at") or "", l.get("status") or "", to, l.get("subject") or ""]))

    elif cmd == "maxid":
        with open(args[0], encoding="utf-8") as f:
            d = json.load(f)
        print(max([int(l.get("id", 0)) for l in d.get("logs", [])] or [0]))

    else:
        sys.exit(f"commande inconnue : {cmd}")


if __name__ == "__main__":
    main()

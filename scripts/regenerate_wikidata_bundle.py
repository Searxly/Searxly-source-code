#!/usr/bin/env python3
"""
Regenerate Searxly/Resources/WikidataEntities/entities.json from Wikidata (CC0).

Schema mirrors neelguha/simple-wikidata-db tables:
  - labels, descriptions, aliases, entity_values (facts)

Usage:
  python3 Scripts/regenerate_wikidata_bundle.py

Requires network access to wikidata.org. Output is bundled offline in the app — no runtime API.
"""

from __future__ import annotations

import json
import os
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(ROOT, "Searxly", "Resources", "WikidataEntities", "entities.json")

# canonicalKey -> verified Wikidata QID
ENTITY_QIDS: dict[str, str] = {
    "youtube": "Q866",
    "google": "Q95",
    "apple": "Q312",
    "tesla": "Q478214",
    "microsoft": "Q2283",
    "amazon": "Q3884",
    "netflix": "Q907311",
    "facebook": "Q355",
    "instagram": "Q209330",
    "x": "Q918",
    "reddit": "Q1136",
    "github": "Q364",
    "spotify": "Q689141",
    "twitch": "Q210399",
    "discord": "Q1848638",
    "linkedin": "Q213660",
    "openai": "Q21708200",
    "anthropic": "Q116758847",
    "spacex": "Q193701",
    "neuralink": "Q27988204",
    "starlink": "Q56283016",
    "xai": "Q124727262",
    "elon musk": "Q317521",
    "bernard arnault": "Q32055",
    "jeff bezos": "Q312556",
    "bill gates": "Q5284",
    "mark zuckerberg": "Q36215",
    "warren buffett": "Q47213",
    "steve jobs": "Q19837",
    "tim cook": "Q265852",
    "jensen huang": "Q556445",
    "sam altman": "Q27645609",
    "satya nadella": "Q7426870",
    "larry page": "Q167545",
    "sergey brin": "Q92764",
    "donald trump": "Q22686",
    "barack obama": "Q76",
    "taylor swift": "Q26876",
    "beyonce": "Q36153",
    "lionel messi": "Q615",
    "cristiano ronaldo": "Q11571",
    "francois pinault": "Q666587",
    "oprah winfrey": "Q43303",
    "wikipedia": "Q52",
    "duckduckgo": "Q12805",
    "tiktok": "Q48938223",
    "figma": "Q28464616",
    "notion": "Q60745680",
    "stripe": "Q7624104",
    "cloudflare": "Q43905424",
    "huggingface": "Q108943604",
    "nvidia": "Q182477",
    "meta": "Q380",
    "whatsapp": "Q13969",
    "zoom": "Q85765088",
    "dropbox": "Q142539",
    "vercel": "Q56069184",
    "brave": "Q22906900",
    "signal": "Q19829322",
    "protonmail": "Q17355735",
    "cursor": "Q131980386",
    "perplexity": "Q124333951",
    "midjourney": "Q116956702",
    "steam": "Q1065153",
    "gitlab": "Q16639197",
    "docker": "Q15206305",
    "bbc": "Q9531",
    "reuters": "Q130879",
}

FACT_PROPERTIES = {
    "P571": "Founded",
    "P169": "CEO",
    "P159": "Headquarters",
    "P452": "Industry",
    "P127": "Owned by",
    "P112": "Founded by",
    "P1128": "Employees",
    "P2139": "Revenue",
    "P17": "Country",
    "P749": "Parent organization",
    "P1056": "Product",
    "P1037": "Director",
    "P488": "Chairperson",
    "P178": "Developer",
    "P19": "Place of birth",
    "P27": "Citizenship",
    "P106": "Occupation",
    "P569": "Born",
    "P39": "Position",
    "P108": "Employer",
}

SKIP_FACT_LABELS = {"Website", "License", "Type"}

OCCUPATION_PRIORITY = (
    "chief executive",
    "business magnate",
    "businessperson",
    "businessman",
    "businesswoman",
    "entrepreneur",
    "investor",
    "engineer",
    "computer programmer",
    "politician",
    "president",
    "singer",
    "songwriter",
    "actor",
    "actress",
    "footballer",
    "athlete",
)


def api(params: dict, base: str = "https://www.wikidata.org/w/api.php") -> dict:
    url = f"{base}?{urllib.parse.urlencode(params)}"
    for attempt in range(6):
        time.sleep(0.8 + attempt * 0.4)
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "Searxly/1.0 (wikidata-bundle-regenerator)"},
        )
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as err:
            if err.code == 429 and attempt < 5:
                time.sleep(8 + attempt * 4)
                continue
            raise
    raise RuntimeError("api retries exhausted")


def fetch_entities(qids: list[str]) -> dict:
    all_ent: dict = {}
    for i in range(0, len(qids), 30):
        batch = qids[i : i + 30]
        data = api(
            {
                "action": "wbgetentities",
                "ids": "|".join(batch),
                "props": "labels|descriptions|aliases|claims|sitelinks",
                "languages": "en",
                "format": "json",
            }
        )
        all_ent.update(data.get("entities", {}))
    return all_ent


def enwiki_title(ent: dict) -> str | None:
    site = ent.get("sitelinks", {}).get("enwiki")
    if not site:
        return None
    return site.get("title")


def fetch_wikipedia_summaries(titles: list[str]) -> dict[str, str]:
    """Batch-fetch English Wikipedia lead sections (CC BY-SA, bundled offline)."""
    out: dict[str, str] = {}
    unique = [t for t in dict.fromkeys(titles) if t]
    for i in range(0, len(unique), 15):
        batch = unique[i : i + 15]
        data = api(
            {
                "action": "query",
                "prop": "extracts",
                "explaintext": "1",
                "exintro": "1",
                "exsectionformat": "plain",
                "exchars": "1400",
                "titles": "|".join(batch),
                "format": "json",
            },
            base="https://en.wikipedia.org/w/api.php",
        )
        for page in data.get("query", {}).get("pages", {}).values():
            title = page.get("title")
            extract = (page.get("extract") or "").strip()
            if title and len(extract) >= 80:
                out[title] = normalize_summary(extract)
    return out


def normalize_summary(text: str) -> str:
    text = text.replace("\n", " ").strip()
    while "  " in text:
        text = text.replace("  ", " ")
    # Trim at a sentence boundary when overly long.
    if len(text) > 1_400:
        cut = text[:1_400]
        if "." in cut:
            cut = cut[: cut.rfind(".") + 1]
        text = cut.strip()
    return text


def best_occupation(ent: dict, label_cache: dict[str, str]) -> str | None:
    options: list[str] = []
    for claim in ent.get("claims", {}).get("P106", [])[:8]:
        v = resolve_value(claim, label_cache)
        if v:
            options.append(v)
    if not options:
        return None
    lowered = [(o, o.lower()) for o in options]
    for pref in OCCUPATION_PRIORITY:
        for original, low in lowered:
            if pref in low:
                return original
    return options[0]


def format_time(raw_time: str) -> str:
    raw = raw_time.lstrip("+").split("T")[0]
    y, m, d = (raw + "-00-00").split("-")[:3]
    if m == "00":
        return y
    months = [
        "",
        "January",
        "February",
        "March",
        "April",
        "May",
        "June",
        "July",
        "August",
        "September",
        "October",
        "November",
        "December",
    ]
    try:
        mi = int(m)
        if d == "00":
            return f"{months[mi]} {y}"
        return f"{months[mi]} {int(d)}, {y}"
    except ValueError:
        return y


def resolve_value(claim: dict, label_cache: dict[str, str]) -> str | None:
    snak = claim["mainsnak"]
    if snak.get("snaktype") != "value":
        return None
    dv = snak["datavalue"]
    t = dv["type"]
    if t == "wikibase-entityid":
        return label_cache.get(dv["value"]["id"])
    if t == "time":
        return format_time(dv["value"]["time"])
    if t == "string":
        v = dv["value"]
        return None if v.startswith("http") else v
    if t == "monolingualtext":
        return dv["value"]["text"]
    if t == "quantity":
        amt = dv["value"].get("amount", "").lstrip("+")
        if not amt:
            return None
        try:
            n = float(amt)
            if n >= 1e9:
                return f"${n/1e9:.1f}B"
            if n >= 1e6:
                return f"${n/1e6:.0f}M"
            if n >= 1000:
                return f"{int(n):,}"
            return str(int(n)) if n == int(n) else amt
        except ValueError:
            return amt
    return None


def main() -> None:
    qids = sorted(set(ENTITY_QIDS.values()))
    entities = fetch_entities(qids)

    ref_qids: set[str] = set()
    for ent in entities.values():
        for pid in FACT_PROPERTIES:
            for c in ent.get("claims", {}).get(pid, [])[:4]:
                snak = c["mainsnak"]
                if snak.get("snaktype") == "value" and snak["datavalue"]["type"] == "wikibase-entityid":
                    ref_qids.add(snak["datavalue"]["value"]["id"])
    missing = [q for q in ref_qids if q not in entities]
    if missing:
        entities.update(fetch_entities(missing[:150]))

    label_cache = {
        qid: ent.get("labels", {}).get("en", {}).get("value", qid)
        for qid, ent in entities.items()
        if not ent.get("missing")
    }

    catalog = {
        "version": "1",
        "source": "Wikidata (CC0), schema inspired by neelguha/simple-wikidata-db",
        "license": "CC0 1.0 — https://www.wikidata.org/wiki/Wikidata:Data_access",
        "entities": {},
    }

    wiki_titles: list[str] = []
    pending: list[tuple[str, str, dict]] = []
    for key, qid in sorted(ENTITY_QIDS.items()):
        ent = entities.get(qid)
        if not ent or ent.get("missing"):
            print(f"skip missing {key} {qid}")
            continue
        desc = ent.get("descriptions", {}).get("en", {}).get("value", "").strip()
        label = ent.get("labels", {}).get("en", {}).get("value", "").strip()
        aliases = [a["value"] for a in ent.get("aliases", {}).get("en", [])][:10]
        if len(desc) < 12:
            print(f"skip short description {key}: {desc!r}")
            continue

        facts: list[dict] = []
        seen: set[str] = set()
        for pid, fact_label in FACT_PROPERTIES.items():
            if fact_label in SKIP_FACT_LABELS:
                continue
            if pid == "P106":
                occ = best_occupation(ent, label_cache)
                if occ and "Occupation" not in seen:
                    seen.add("Occupation")
                    facts.append({"label": "Occupation", "value": occ[:240]})
                continue
            for c in ent.get("claims", {}).get(pid, [])[:3]:
                v = resolve_value(c, label_cache)
                if not v or len(v) < 2 or fact_label in seen:
                    continue
                seen.add(fact_label)
                facts.append({"label": fact_label, "value": v[:240]})
                if len(facts) >= 10:
                    break
            if len(facts) >= 10:
                break

        title = enwiki_title(ent)
        if title:
            wiki_titles.append(title)
        pending.append((key, qid, {
            "qid": qid,
            "label": label or key.title(),
            "description": desc,
            "aliases": aliases,
            "facts": facts,
            "_wiki_title": title,
        }))

    wiki_summaries = fetch_wikipedia_summaries(wiki_titles)
    summary_count = 0

    for key, qid, record in pending:
        wiki_title = record.pop("_wiki_title", None)
        summary = wiki_summaries.get(wiki_title or "", "")
        if len(summary) >= 80:
            record["summary"] = summary
            summary_count += 1
        catalog["entities"][key] = record

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"wrote {len(catalog['entities'])} entities ({summary_count} with Wikipedia summaries) -> {OUT_PATH}")


if __name__ == "__main__":
    main()
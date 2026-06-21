# Searxly Premium Web Theme

Stark monochrome (black/grey/white), extreme minimalism, massive negative space.

Inspired by the official xAI website, Grok interface, and SpaceX’s futuristic restraint.

## Structure
- `templates/simple/` — Jinja overrides (base, index, search, results, result_templates)
- `static/themes/simple/searxly.css` — the complete design system + presentation layer

## Key Design Choices (2026)
- No colored accents whatsoever (pure monochrome as directed)
- Result titles: large (20.5px), bold, commanding with refined hover lift
- URLs: tiny, muted, refined sans (not mono), zero pills/favicons/tags
- Generous but calibrated 52px vertical rhythm between results (luxurious without sparsity)
- Contextual search bar: heroic + tall on home, refined + compact on results
- Beautiful soft-white focus ring + glow on the search bar
- Slim elegant 48px top nav
- Image results: clean minimalist grid with subtle depth on hover
- Home wordmark with premium tracking + quiet tagline

Recent tweaks focused on rhythm, typography precision, contextual search bar sizing, image grid refinement, and overall "expensive calm" feel.

## Updating on SearXNG Upgrades
1. `docker cp searxng:/usr/local/searxng/searx/templates/simple .` (or equivalent)
2. Re-apply our minimal overrides + re-test the CSS selectors.

The theme is automatically deployed via the one-click "Create Local SearXNG Setup Folder" flow in the Searxly macOS app.

Maintained as part of the Searxly project.

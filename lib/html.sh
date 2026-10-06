#!/usr/bin/env bash
# Shared Carbon Design System HTML page shell + a plain HTML-escape helper,
# used by every script that renders a report page (render-report-html.sh,
# render-index-html.sh) so the <head>/header/footer boilerplate isn't
# duplicated per page. Sourced by those scripts directly — not by area
# scripts, and not meant to be executed on its own.

html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# carbon_page_head <title> [extra_css]
# Emits <!doctype html> through the opening <main class="bx--content">.
# extra_css (optional) is page-specific CSS appended inside the same
# <style> block as the shared base rules.
carbon_page_head() {
  local title="$1" extra_css="${2:-}"
  cat <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${title}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:wght@300;400;600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/carbon-components@10/css/carbon-components.min.css">
<style>
  body { margin: 0; }
  main.bx--content { max-width: 960px; margin: 0 auto; padding: 3rem 1rem 4rem; }
  h1 { margin-bottom: 0; }
  h2 { margin: 2.5rem 0 1rem; }
  footer { color: #6f6f6f; font-size: 0.75rem; margin-top: 3rem; padding-top: 1.5rem; border-top: 1px solid #e0e0e0; max-width: 960px; margin-left: auto; margin-right: auto; padding-left: 1rem; padding-right: 1rem; box-sizing: border-box; }
  footer a { color: inherit; }
${extra_css}
</style>
</head>
<body>
<header class="bx--header" role="banner" aria-label="Quarkus Flow Exploratory">
  <a class="bx--header__name" href="https://github.com/mathecruz/quarkus-flow-exploratory">
    <span class="bx--header__name--prefix">Quarkus&nbsp;Flow&nbsp;</span>&nbsp;Exploratory
  </a>
</header>
<main class="bx--content">
HTML
}

# carbon_page_footer <footer_html>
carbon_page_footer() {
  local footer_html="$1"
  cat <<HTML
</main>
<footer>${footer_html}</footer>
</body>
</html>
HTML
}

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
  .bx--header__name { display: flex; align-items: center; height: 100%; padding: 0 1rem; }
  .bx--header__name svg { display: block; }
  footer { color: #6f6f6f; font-size: 0.75rem; margin-top: 3rem; padding-top: 1.5rem; border-top: 1px solid #e0e0e0; max-width: 960px; margin-left: auto; margin-right: auto; padding-left: 1rem; padding-right: 1rem; box-sizing: border-box; }
  footer a { color: inherit; }
${extra_css}
</style>
</head>
<body>
<header class="bx--header" role="banner" aria-label="Quarkus Flow Exploratory">
  <a class="bx--header__name" href="https://github.com/mathecruz/quarkus-flow-exploratory" aria-label="View quarkus-flow-exploratory on GitHub">
    <svg height="24" width="24" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
      <path fill-rule="evenodd" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"></path>
    </svg>
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

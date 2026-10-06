#!/usr/bin/env bash
# render-report-html.sh <area_id> <evidence_dir> <outfile>
#
# Renders a standalone HTML report from a single run's evidence directory
# (same results.tsv that SUMMARY.md is built from), for publishing to
# GitHub Pages. area_id looks up the area's display title in
# config/areas.tsv — this script itself has nothing Area-A-specific left in
# it, so any area's evidence dir renders the same way. Styled with IBM's
# Carbon Design System (carbon-components, loaded from a CDN — this is a
# real published page, not a sandboxed Claude artifact, so an external
# stylesheet is fine here).
# Not sourced by area scripts — invoked directly from CI or by hand.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=../lib/result.sh
source "${REPO_ROOT}/lib/result.sh"
# shellcheck source=../lib/html.sh
source "${REPO_ROOT}/lib/html.sh"

AREA_ID="${1:?usage: render-report-html.sh <area_id> <evidence_dir> <outfile>}"
EVIDENCE_DIR="${2:?usage: render-report-html.sh <area_id> <evidence_dir> <outfile>}"
OUT_FILE="${3:?usage: render-report-html.sh <area_id> <evidence_dir> <outfile>}"
RESULTS_TSV="${EVIDENCE_DIR}/results.tsv"
RUN_ID="$(basename "$EVIDENCE_DIR")"
AREAS_TSV="${REPO_ROOT}/config/areas.tsv"

if [ ! -f "$RESULTS_TSV" ]; then
  echo "No results.tsv found in ${EVIDENCE_DIR}" >&2
  exit 1
fi

AREA_TITLE="$AREA_ID"
if [ -f "$AREAS_TSV" ]; then
  found_title="$(awk -F'\t' -v id="$AREA_ID" '$1==id {print $2}' "$AREAS_TSV")"
  [ -n "$found_title" ] && AREA_TITLE="$found_title"
fi

# status_tag_color <status> — maps our PASS/OBSERVATION/FAIL/BLOCKED/FOLLOWUP
# statuses onto Carbon's fixed Tag color palette (no direct "yellow"/"amber"
# in Carbon v10 tags, so OBSERVATION gets teal rather than the legend's 🟡).
status_tag_color() {
  case "$1" in
    PASS) echo "green" ;;
    OBSERVATION) echo "teal" ;;
    FAIL) echo "red" ;;
    BLOCKED) echo "gray" ;;
    FOLLOWUP) echo "purple" ;;
    *) echo "cool-gray" ;;
  esac
}

REPORT_CSS='  .run-meta { color: #525252; margin: 0.5rem 0 2.5rem; }
  .run-meta code { font-family: '"'"'IBM Plex Mono'"'"', monospace; }
  .bx--data-table-container { margin-bottom: 1rem; }
  .bx--data-table td { vertical-align: top; }
  img.evidence-shot { max-width: 100%; display: block; margin: 1rem 0; border: 1px solid #e0e0e0; }
  details.env-details { border: 1px solid #e0e0e0; padding: 0 1rem 1rem; margin-bottom: 1rem; }
  details.env-details summary { cursor: pointer; padding: 1rem 0; font-weight: 600; }
  details.env-details h3 { font-size: 0.875rem; margin: 1rem 0 0.25rem; }
  details.env-details pre { background: #f4f4f4; padding: 0.75rem; overflow-x: auto; font-family: '"'"'IBM Plex Mono'"'"', monospace; font-size: 0.8125rem; margin: 0; }'

{
  carbon_page_head "Quarkus Flow Exploratory — ${AREA_TITLE}" "$REPORT_CSS"

  echo "<h1>${AREA_TITLE} — Exploratory Run Report</h1>"
  echo "<p class=\"run-meta\">Run <code>${RUN_ID}</code> &middot; Generated $(timestamp)</p>"

  echo '<div class="bx--data-table-container">'
  echo '<table class="bx--data-table bx--data-table--zebra">'
  echo "<thead><tr><th>Step</th><th>Description</th><th>Result</th><th>Note</th></tr></thead>"
  echo "<tbody>"
  tail -n +2 "$RESULTS_TSV" | while IFS=$'\t' read -r id desc status note; do
    printf '<tr><td>%s</td><td>%s</td><td><span class="bx--tag bx--tag--%s">%s %s</span></td><td>%s</td></tr>\n' \
      "$id" "$desc" "$(status_tag_color "$status")" "$(status_emoji "$status")" "$(status_label "$status")" "$note"
  done
  echo "</tbody></table></div>"

  if [ -f "${EVIDENCE_DIR}/java-version.txt" ] || [ -f "${EVIDENCE_DIR}/maven-version.txt" ] || [ -f "${EVIDENCE_DIR}/os-info.txt" ]; then
    echo '<details class="env-details">'
    echo "<summary>Captured environment</summary>"
    for pair in "java-version.txt:Java" "maven-version.txt:Maven" "os-info.txt:OS"; do
      file="${EVIDENCE_DIR}/${pair%%:*}"
      label="${pair##*:}"
      if [ -f "$file" ]; then
        echo "<h3>${label}</h3>"
        printf '<pre>%s</pre>\n' "$(tail -n +5 "$file" | html_escape)"
      fi
    done
    echo "</details>"
  fi

  if [ -f "${EVIDENCE_DIR}/01-dev-ui-extensions.png" ]; then
    echo "<h2>Dev UI Screenshots</h2>"
    echo "<p>Extensions page, then the Flow extension's Workflows list after clicking through:</p>"
    echo '<img class="evidence-shot" src="01-dev-ui-extensions.png" alt="Quarkus Dev UI Extensions page">'
    echo '<img class="evidence-shot" src="02-dev-ui-workflows.png" alt="Quarkus Dev UI Workflows list">'
    if [ -f "${EVIDENCE_DIR}/03-dev-ui-execute-valid.png" ]; then
      echo "<p>Executing from the Dev UI with valid, then malformed, input:</p>"
      echo '<img class="evidence-shot" src="03-dev-ui-execute-valid.png" alt="Dev UI execute with valid input">'
      [ -f "${EVIDENCE_DIR}/04-dev-ui-execute-invalid.png" ] && echo '<img class="evidence-shot" src="04-dev-ui-execute-invalid.png" alt="Dev UI execute with invalid input">'
    fi
  fi

  cat <<'HTML'
<h2>Result Legend</h2>
<div class="bx--data-table-container">
<table class="bx--data-table">
<thead><tr><th>Result</th><th>Meaning</th></tr></thead>
<tbody>
<tr><td><span class="bx--tag bx--tag--green">🟢 Passed</span></td><td>Expected behavior was confirmed.</td></tr>
<tr><td><span class="bx--tag bx--tag--teal">🟡 Passed with observations</span></td><td>Main path worked, but notes, risks, or UX gaps were found.</td></tr>
<tr><td><span class="bx--tag bx--tag--red">🔴 Failed</span></td><td>Expected behavior did not work and needs follow-up.</td></tr>
<tr><td><span class="bx--tag bx--tag--gray">⛔ Blocked</span></td><td>The scenario could not be completed due to environment, dependency, or access issues.</td></tr>
<tr><td><span class="bx--tag bx--tag--purple">🔁 Needs follow-up</span></td><td>More focused testing or automation is required.</td></tr>
</tbody>
</table>
</div>
HTML

  carbon_page_footer "Generated by <a href=\"https://github.com/mathecruz/quarkus-flow-exploratory\">quarkus-flow-exploratory</a> — automates the <a href=\"https://docs.quarkiverse.io/quarkus-flow/dev/\">Quarkus Flow Exploratory Testing Guide</a>. Styled with <a href=\"https://carbondesignsystem.com/\">IBM Carbon</a>. <a href=\"../\">All scenarios</a>."
} > "$OUT_FILE"

echo "Wrote ${OUT_FILE}"

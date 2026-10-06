# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Bash automation for the [Quarkus Flow Exploratory Testing Guide](https://docs.quarkiverse.io/quarkus-flow/dev/). The guide has 19 areas (A–S); this repo automates **Area A — Local Developer Workflow** (generate a project, add `quarkus-flow` + `rest-jackson`, write a Java DSL "hello" workflow, compile, run `quarkus:dev`, verify endpoints and live reload), **Area C — Dev UI and Local Tracing** (adds a richer multi-task workflow on top of Area A's base project, verifies trace log output, and drives the Dev UI's own "Run workflow" view with valid and invalid input), and **Area D — REST and Runner Execution** (adds the `quarkus-flow-runner` and `smallrye-openapi` extensions on top of Area A's base project, configures the Runner to source a YAML workflow from disk with security disabled for local dev, and exercises both the custom REST endpoint and the Runner's generic exec endpoint — valid sync/async execution plus a battery of invalid-input cases — then checks OpenAPI/Swagger UI exposure). Area B ("Workflow Definition Coverage: Java DSL vs YAML/JSON") was deliberately skipped — it's inherently comparative with no documented ground truth to assert pass/fail against. More areas are meant to be added later following the same pattern.

There is no application code to build here — the "product" is the automation script itself, plus the evidence/report it produces each run.

## Commands

Run the automation:
```bash
./scripts/areas/area-a.sh
./scripts/areas/area-c.sh
./scripts/areas/area-d.sh
# or via the dispatcher (scripts/run.sh <area>, picks up any script under scripts/areas/ automatically):
./scripts/run.sh area-a
./scripts/run.sh area-c
./scripts/run.sh area-d
```
Each area is independently runnable — Area C and Area D each regenerate their own project (reusing Area A's *templates*, not Area A's actual run output) rather than depending on a prior Area A run having happened.

Override config via env vars, e.g.:
```bash
QF_VERSION=1.2.0 QUARKUS_PLATFORM_VERSION=3.28.4 ./scripts/areas/area-a.sh
```
Exit code is `0` only if every step passed or was a best-effort observation, `1` if anything failed or was blocked (see `worst_status_exit_code` in `lib/result.sh`).

There is no separate test suite — running the script *is* the test; it validates itself end-to-end against a real generated Quarkus project. Before committing shell changes, sanity-check with:
```bash
bash -n scripts/areas/area-a.sh scripts/areas/area-c.sh scripts/areas/area-d.sh lib/*.sh scripts/*.sh   # syntax check
shellcheck scripts/areas/*.sh lib/*.sh scripts/*.sh                                                     # if installed
```
For a Playwright script:
```bash
node --check scripts/playwright/<name>.mjs
npm install && npx playwright install chromium   # one-time local setup
```

Render an HTML report or the landing page from existing evidence (used by CI, also runnable by hand):
```bash
./scripts/render-report-html.sh area-a evidence/area-a/<RUN_ID> /path/to/out.html
./scripts/render-index-html.sh /path/to/site /path/to/site/index.html   # site/<area_id>/index.html must already exist per area
```

## Architecture

**Orchestration pattern**: each area is a standalone, non-`set -e` script under `scripts/areas/*.sh`. It sources shared helpers from `lib/`, defines one `step_*` function per guide step, and a `main()` that calls them in order — setup through starting dev mode is fatal (`|| exit 1`); everything after that is independent and runs regardless of siblings' outcomes (`|| true`). A `trap cleanup EXIT INT TERM` always stops the background `quarkus:dev` process and renders the summary, even on failure or Ctrl-C.

**`lib/` helpers** (sourced, never executed directly — bash 3.2-compatible for macOS's stock `/bin/bash`):
- `common.sh` — logging, `require_cmd`, `render_template` (simple `@@KEY@@` substitution), `retry`, `is_ci`.
- `http.sh` — curl wrappers recording `HTTP_STATUS`/`CURL_EXIT`, JSON assertions via `jq` with substring-grep fallback when `jq` is absent, TCP port checks using bash's `/dev/tcp`, and `http_poll_until_json_equals` for live-reload polling.
- `process.sh` — background process lifecycle for `mvnw quarkus:dev`: starts it as its own process-group leader (`set -m` in the caller), stops via `SIGTERM` to the group then `SIGKILL` after a grace period, plus a PID-tree sweep as defense-in-depth against orphaned JVM children.
- `evidence.sh` — `init_evidence_dir`, `capture_cmd`, `capture_dev_ui_flow` (best-effort call into `scripts/playwright/dev-ui-workflows-flow.mjs`), `capture_dev_ui_execute` (best-effort call into `scripts/playwright/dev-ui-execute-workflow-flow.mjs`) — all degrade silently to skipped, never fail the caller, if `node` isn't installed.
- `result.sh` — result tracking. Results are appended to a TSV file (`results.tsv`), not an in-memory associative array, for bash 3.2 compatibility and so the file doubles as an evidence artifact. Statuses: `PASS`/`OBSERVATION`/`FAIL`/`BLOCKED`/`FOLLOWUP` (🟢/🟡/🔴/⛔/🔁). `render_summary <evidence_dir> <area_id>` builds `SUMMARY.md`, looking up the area's display title from `config/areas.tsv`.
- `bootstrap.sh` — `bootstrap_create_project`, `bootstrap_add_flow_extension`, `bootstrap_write_java_dsl_sources`, `bootstrap_compile`: the "generate project + add extension + write the Java DSL `hello` workflow + compile" phase, extracted out of `area-a.sh` so every area that needs a working base project (Area C, Area D today) reuses it instead of re-deriving it. Reads the same globals the calling area script already set (`WORKDIR`, `PROJECT_DIR`, `EVIDENCE_DIR`, `TEMPLATES_DIR`, etc.) — a caller can temporarily point `TEMPLATES_DIR` at `templates/area-a` for just the `bootstrap_write_java_dsl_sources` call (`TEMPLATES_DIR=... bootstrap_write_java_dsl_sources`) even if its own `TEMPLATES_DIR` default points elsewhere. Also `bootstrap_add_extension <gav> <result_id> <description> <log_name> [grep_pattern]` — a generic "add-extension, retry, verify pom.xml" helper (unlike `bootstrap_add_flow_extension`, which stays hardcoded to `quarkus-flow` for A/C) added for Area D's `quarkus-flow-runner` and `smallrye-openapi` extensions and reusable by any future area that needs to add an arbitrary extension.
- `html.sh` — `html_escape`, `carbon_page_head <title> [extra_css]`, `carbon_page_footer <footer_html>`: the Carbon Design System page shell shared by `render-report-html.sh` and `render-index-html.sh` instead of duplicating the `<head>`/header/footer boilerplate.

**Run/evidence layout**: every invocation gets a fresh `RUN_ID` (UTC timestamp) — nothing is ever overwritten.
- `work/area-<x>/<RUN_ID>/` — the generated Quarkus project (gitignored).
- `evidence/area-<x>/<RUN_ID>/` — logs, response bodies, screenshots, `results.tsv`, and `SUMMARY.md` (gitignored locally; uploaded as a CI artifact; the latest run on `main` is also rendered to HTML and published to GitHub Pages).

**Templates**: `templates/area-<x>/*.java` are fixture source files copied into the generated project via `render_template`. `templates/area-a/` holds the shared Java DSL `hello` workflow (`HelloFlow.java`, `Message.java`, `HelloResource.java`) reused by Area C and Area D via `lib/bootstrap.sh`. `templates/area-c/` holds Area C's own `traced` workflow (`TracedFlow.java` — three chained `function()` tasks, confirmed against the real `io.quarkiverse.flow.dsl.FlowDSL` API, not guessed — `TracedResult.java`, `TracedResource.java`) plus `TracedFlow.live-reload.java`, a full alternate version swapped in wholesale to exercise live reload (same pattern as `HelloFlow.live-reload.java`). `templates/area-d/` holds the Runner-sourced `greet.yaml` workflow (a required-field input schema so both success and schema-violation cases are testable) and an `application.properties` fragment (`quarkus.flow.runner.enabled`, `.source.path`, dev-only `.security.type=NONE`) appended onto the generated project's own file. Confirmed live: `quarkus-flow-runner` is **not** version-managed by the same BOM as `quarkus-flow` — adding it unpinned resolves an unrelated, much older release (e.g. `0.13.0` against a `1.1.0` `quarkus-flow`) whose `WorkflowApplication.Builder` API predates methods the pinned `quarkus-flow` runtime calls, crashing dev mode with `NoSuchMethodError: withAllowedCommands(Collection)` — `area-d.sh` therefore pins it to `${QF_VERSION}` explicitly, exactly like `bootstrap_add_flow_extension` does for `quarkus-flow` itself. Also confirmed live: the exec endpoint's declared `input.schema.required` is **not enforced** — posting an empty body or a JSON object missing the required field both return `200`/`COMPLETED` with the missing field silently resolving to an empty string, rather than a `4xx`. Area D's negative-case steps still assert "4xx expected" (matching the guide's expected results) and so correctly `FAIL` on this, with the actual response body captured as evidence either way.

**Dev UI Playwright flows** (`scripts/playwright/`):
- `dev-ui-workflows-flow.mjs` — clicks Extensions → the Flow extension's "Workflows" link (`<a class="extensionLink">`) → waits for the list's `<table>` to render an actual data row (excluding the always-present, initially-hidden `#emptystaterow` placeholder). Nothing Area-specific in it — shared as-is between Area A and Area C, the screenshot just shows more rows as more areas add workflows.
- `dev-ui-execute-workflow-flow.mjs` — drives the Dev UI's individual workflow "Run" view: clicks the row's `#play-diagramEditor-<namespace>-<name>-<version-with-dashes>` button, replaces the CodeMirror-backed input editor's content, clicks `#execute-workflow`, and reads the output panel's raw text directly from its `value` DOM attribute (no screenshot-OCR needed) before and after — reused for both the valid- and invalid-input steps rather than two near-identical scripts. Confirmed live: malformed JSON produces a `# Error` block naming the actual exception plus a visible toast, not a silent no-op — Area C asserts on that directly.

**CI** (`.github/workflows/exploratory.yml`, using the composite action `.github/actions/setup-flow-env` for the shared Java/Node/Playwright toolchain setup): four jobs.
1. `area-a` / `area-c` / `area-d` — run in parallel on `push`/`pull_request`/`schedule` (daily at `03:00 UTC`, cron `0 3 * * *`)/`workflow_dispatch`, each uploading the full evidence dir plus a `-latest-run` artifact scoped to just that run's `RUN_ID`. `CI=true`/`GITHUB_ACTIONS` auto-widen timeouts/retries via `is_ci()`.
2. `publish-report` — `needs: [area-a, area-c, area-d]`, only on `push` to `main` or the daily `schedule` run (scheduled runs always execute against the default branch, so the same `github.ref == 'refs/heads/main'` check still applies). Downloads whichever `-latest-run` artifacts exist, renders each into `site/<area_id>/index.html` via `render-report-html.sh <area_id> ...` (Carbon Design System, CSS from a CDN — safe here since this is a real published page, not a sandboxed artifact), renders `site/index.html` as a landing page via `render-index-html.sh` (reads `config/areas.tsv`, links to whichever `site/<area_id>/` actually exists), and deploys the whole `site/` tree to GitHub Pages (https://mathecruz.github.io/quarkus-flow-exploratory/) via `actions/deploy-pages`. Publishes even a failed run.

`config/areas.tsv` (`area_id\ttitle\tdescription`) is the single source of truth both `render-report-html.sh` and `render-index-html.sh` read from — adding an area to the published site is one new line here.

Config precedence in CI: manual `workflow_dispatch` input > repository/org Actions Variable > the script's own default in `config/defaults.env`. Only `QF_VERSION`, `QUARKUS_PLATFORM_VERSION`, `TEST_GROUP_ID`, `TEST_ARTIFACT_ID`, `APP_PORT` are exposed as manual inputs; the rest are Variables-only to keep the trigger form short.

## Adding a new area

1. Copy `scripts/areas/area-a.sh` (or `area-c.sh`, if it also needs a Dev UI interaction; or `area-d.sh`, if it's REST/HTTP-driven and needs to add extensions beyond `quarkus-flow` itself) as a starting skeleton.
2. Reuse `lib/bootstrap.sh` for the base project instead of re-deriving create/add-extension/write-sources/compile.
3. Add any Java/YAML fixtures under `templates/area-<x>/`.
4. Reuse the helpers in `lib/` before adding new ones.
5. Add a line to `config/areas.tsv` (area id, title, description).
6. `scripts/run.sh` picks up any script placed in `scripts/areas/` automatically — no registration needed. Add the new job to `.github/workflows/exploratory.yml` (copy an existing area job, using `./.github/actions/setup-flow-env`) and wire it into `publish-report`'s `needs:` and its download/render block.

## Known limitations

- The Dev UI Workflows-list flow confirms the list renders a row after clicking through from Extensions (best-effort — degrades to a plain `200` reachability check, not a failure, if Node/Playwright aren't available). It does not open the individual workflow to confirm its diagram renders; that judgment is still manual.
- Area B was skipped as inherently comparative/undocumented territory rather than something with a real pass/fail to assert.
- Area D found two real `quarkus-flow-runner` (1.1.0) gaps: (1) it isn't version-managed by the `quarkus-flow` BOM, so an unpinned `add-extension` resolves an incompatible old release — worked around by pinning to `${QF_VERSION}` explicitly; (2) the exec endpoint doesn't enforce a workflow's declared `input.schema.required` — a missing/empty body or a schema-violating payload both complete successfully (`200`) instead of being rejected with `4xx`. These are captured as `FAIL` results with the real response body as evidence, not asserted-away.
- Only Areas A, C, and D are automated; the other 16 areas in the guide are still manual.

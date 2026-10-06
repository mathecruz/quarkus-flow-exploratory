# Quarkus Flow Exploratory Automation

Bash automation for the [Quarkus Flow Exploratory Testing Guide](https://docs.quarkiverse.io/quarkus-flow/dev/). The guide has 19 areas (A–S); **this repo currently automates Area A (Local Developer Workflow) and Area C (Dev UI and Local Tracing)**. More areas may be added later following the same pattern (see [Adding a new area](#adding-a-new-area)).

Runs locally and in CI (GitHub Actions) — see [`.github/workflows/exploratory.yml`](.github/workflows/exploratory.yml).

**Latest run report:** https://mathecruz.github.io/quarkus-flow-exploratory/ (a landing page listing every scenario, published automatically after every push to `main` — see [Published report](#published-report)).

## What Area A validates

1. Generate a Quarkus project via the Maven plugin (no Quarkus CLI dependency).
2. Add the `quarkus-flow` and `rest-jackson` extensions.
3. Write a minimal Java DSL "hello" workflow and a REST resource exposing it.
4. Compile the project.
5. Start `quarkus:dev` in the background and wait for it to become ready.
6. `GET /hello-flow` returns `{"message":"hello world!"}`.
7. `GET /hello-flow/debug` returns the raw workflow output map.
8. `POST /hello-flow` is rejected with `405 Method Not Allowed`.
9. Dev UI: a Playwright flow clicks from the Extensions landing page into the Flow extension's Workflows link and confirms the list actually renders a row (not just that `/q/dev-ui` returns `200`) — screenshotting both pages. See [Known limitations](#known-limitations).
10. Live reload: edit the workflow's message while `quarkus:dev` is running and confirm the new message is served.

Every run always stops the background `quarkus:dev` process and writes a pass/fail/blocked summary, whether it succeeds, fails, or is interrupted.

## What Area C validates

Builds on the same base project as Area A (reused, not regenerated — see [Reuse architecture](#reuse-architecture-across-areas)), adding a second, richer Java DSL workflow (`traced`: three chained tasks — `function` → `function` → `function`, each one actually transforming the previous task's output — so there's a meaningful multi-node graph and a multi-line trace, not just one step) to exercise the Dev UI itself, not just REST endpoints:

1. Write the `traced` workflow + REST resource alongside Area A's `hello` workflow.
2. Compile, start `quarkus:dev`.
3. `GET /traced-flow` returns the workflow's output; the `Warming up 2 WorkflowDefinition beans` startup log line confirms both workflows registered.
4. Trace log verification: grep `devmode.log` for the `TraceLoggerExecutionListener` workflow-started / task-started / task-completed / workflow-completed line shapes (tracing is on by default in dev mode — confirmed directly from captured logs, no config needed).
5. Dev UI: reuses Area A's Workflows-list screenshot (now showing both `hello` and `traced` rows).
6. **Executes the `traced` workflow from the Dev UI itself** (not REST) with valid JSON input (`{"name":"World"}`), reading the output panel's raw value directly — no screenshot-guessing needed, Dev UI keeps the full result text in a DOM attribute.
7. Repeats with malformed JSON input. Confirmed live: Quarkus Flow's Dev UI reports this clearly — a red error toast plus a `# Error` block in the output panel naming the actual exception — so this is asserted as a real pass/fail, not just an observation.
8. Live reload: edit the workflow's greeting while `quarkus:dev` is running and confirm the new value is served.

The two Dev UI execution steps (6–7) are driven by [`scripts/playwright/dev-ui-execute-workflow-flow.mjs`](scripts/playwright/dev-ui-execute-workflow-flow.mjs), reused for both the valid and invalid case rather than writing two scripts.

## Prerequisites

- bash
- Java 17+
- Maven
- curl
- git
- `jq` recommended (assertions fall back to substring matching if absent)
- Network access to Maven Central (first run resolves the Quarkus platform + extensions)
- Node.js 18+ and npm — optional, only needed for the Dev UI click-through flow. Run `npm install && npx playwright install chromium` once; if `node` isn't found, the flow is skipped and the Dev UI step degrades to reachability-only, not a failure.

## Quick start

```bash
./scripts/areas/area-a.sh
./scripts/areas/area-c.sh
# or, via the dispatcher:
./scripts/run.sh area-a
./scripts/run.sh area-c
```

Each area is independently runnable — Area C regenerates its own project (reusing Area A's Java DSL templates, not Area A's actual run) rather than depending on a prior Area A run. Exit code is `0` only if every step passed or was a best-effort observation; `1` if anything failed or was blocked.

## Configuration

All variables are set with sane defaults in [`config/defaults.env`](config/defaults.env) and can be overridden via environment variables at invocation time:

```bash
QF_VERSION=1.2.0 QUARKUS_PLATFORM_VERSION=3.28.4 ./scripts/areas/area-a.sh
```

| Variable | Default | Notes |
|---|---|---|
| `QF_VERSION` | `1.1.0` | Quarkus Flow version to test. **Bump this first** if a run fails due to version drift — the guide is pinned to a released version that will lag behind `quarkus-flow`'s main branch. |
| `QUARKUS_PLATFORM_VERSION` | `3.37.4` | Quarkus platform version used to generate the project. **Bump this second** alongside `QF_VERSION`. |
| `TEST_GROUP_ID` | `org.acme` | Generated project's Java package / Maven group ID. |
| `TEST_ARTIFACT_ID` | `hello-flow` | Generated project's Maven artifact ID and directory name. |
| `APP_PORT` | `8080` | Port `quarkus:dev` listens on. |
| `READY_TIMEOUT_SECONDS` | `180` (doubled under CI) | How long to wait for `quarkus:dev` to become ready. Startup time is sensitive to machine load (IDE background processes, other builds running concurrently) — bump this if you see `dev mode did not become ready` on a busy dev machine even though the same run succeeds when nothing else is running. |
| `LIVE_RELOAD_TIMEOUT_SECONDS` | `30` | How long to poll for the live-reload change to take effect. |
| `LIVE_RELOAD_POLL_INTERVAL_SECONDS` | `2` | Poll interval for the live-reload check. |
| `HTTP_TIMEOUT_SECONDS` | `10` | Per-request curl timeout. |
| `GRACEFUL_STOP_SECONDS` | `10` | How long to wait after `SIGTERM` before escalating to `SIGKILL`. |
| `RETRY_MAX_ATTEMPTS` | `3` (+2 under CI) | Retries for network-dependent Maven commands (project creation, extension add). |
| `RETRY_DELAY_SECONDS` | `5` | Delay between retries. |

`CI=true` or `GITHUB_ACTIONS` being set automatically widens timeouts and retry counts — GitHub Actions sets both by default, so no extra configuration is needed there.

### Overriding configuration in GitHub Actions

The workflow ([`.github/workflows/exploratory.yml`](.github/workflows/exploratory.yml)) doesn't hardcode versions — both the `area-a` and `area-c` jobs pass `QF_VERSION`, `QUARKUS_PLATFORM_VERSION`, `TEST_GROUP_ID`, `TEST_ARTIFACT_ID`, and `APP_PORT` through as env vars, resolved in this order:

1. **Manual "Run workflow" input** — go to the *Actions* tab → *Quarkus Flow Exploratory* → *Run workflow*, and fill in any of the fields (e.g. a different `qf_version` to test an upcoming release). Applies to both jobs; only available for manually triggered runs, not `push`/`pull_request`.
2. **Repository (or organization) Variable** — *Settings → Secrets and variables → Actions → Variables*, add e.g. `QF_VERSION` = `1.2.0`. This applies to every trigger type, including `push`/`pull_request`, with no workflow file changes needed.
3. **The script's own default** in `config/defaults.env`, used whenever neither of the above is set.

The other timeout/retry knobs aren't exposed as manual inputs (to keep the trigger form short) but still follow the same Variables-then-default precedence if you add a matching repository Variable.

## What it produces

- `work/area-<x>/<RUN_ID>/hello-flow/` — the generated Quarkus project (gitignored).
- `evidence/area-<x>/<RUN_ID>/` — logs, response bodies, screenshots, and `SUMMARY.md` (gitignored locally; uploaded as a build artifact in CI).

Each run gets a fresh timestamped `RUN_ID`; nothing is ever overwritten, so runs can be repeated freely. Area A and Area C each generate their own independent project under their own `area-<x>/` tree.

## Reuse architecture across areas

Adding Area C on top of Area A was an exercise in not duplicating what already existed:

- [`lib/bootstrap.sh`](lib/bootstrap.sh) — the "generate a project, add the extension, write the Java DSL `hello` workflow, compile" steps, extracted out of `area-a.sh` so Area C (and any future area) can reuse them instead of copy-pasting.
- [`lib/html.sh`](lib/html.sh) — the shared Carbon `<head>`/header/footer HTML shell, used by both the per-area report renderer and the landing-page renderer.
- [`config/areas.tsv`](config/areas.tsv) — one line per area (id, title, description); the single source of truth both the per-area report title and the landing page's scenario cards read from. Adding an area to the published site is one new line here.
- [`scripts/playwright/dev-ui-workflows-flow.mjs`](scripts/playwright/dev-ui-workflows-flow.mjs) — the Workflows-list click-through screenshot is reused byte-for-byte between areas (it has no Area-A-specific assumptions — it just waits for *a* row to render).
- [`.github/actions/setup-flow-env`](.github/actions/setup-flow-env/action.yml) — the Java/Node/Playwright CI toolchain setup, one composite action used by every area's job instead of duplicated workflow YAML.

## Published report

Every push to `main` runs the `publish-report` job ([`.github/workflows/exploratory.yml`](.github/workflows/exploratory.yml)), which downloads each area's latest run evidence, renders each into its own page via [`scripts/render-report-html.sh`](scripts/render-report-html.sh) `<area_id>` — styled with [IBM's Carbon Design System](https://carbondesignsystem.com/) (`carbon-components` loaded from a CDN; this is a real published page, not a sandboxed artifact, so an external stylesheet is fine) — and renders a landing page via [`scripts/render-index-html.sh`](scripts/render-index-html.sh) linking to whichever areas actually published this run. Deploys the whole thing to GitHub Pages: **https://mathecruz.github.io/quarkus-flow-exploratory/**. It always reflects the most recent run on `main` — a failed run still gets published, since a red result is useful information too. Pull request runs are not published (only their evidence artifact is uploaded, per the existing behavior).

## Result Legend

| Result | Meaning |
|---|---|
| 🟢 Passed | Expected behavior was confirmed. |
| 🟡 Passed with observations | Main path worked, but notes, risks, or UX gaps were found. |
| 🔴 Failed | Expected behavior did not work and needs follow-up. |
| ⛔ Blocked | The scenario could not be completed due to environment, dependency, or access issues. |
| 🔁 Needs follow-up | More focused testing or automation is required. |

## Known limitations

- **Dev UI check clicks through to the Workflows list, but doesn't inspect the diagram.** [`scripts/playwright/dev-ui-workflows-flow.mjs`](scripts/playwright/dev-ui-workflows-flow.mjs) opens Extensions, clicks the Flow card's "Workflows" link, and waits for the list to render an actual row before screenshotting both pages (best-effort — if Node/Playwright aren't available it degrades to the plain `200` reachability check, always recorded as 🟡). It does not open the individual workflow to confirm its diagram renders — that judgment call is still manual.
- Area B ("Workflow Definition Coverage: Java DSL and YAML/JSON") was deliberately skipped: it's inherently comparative (is YAML "as good as" Java DSL?) with no documented ground truth to assert against, which made scripting a real pass/fail verdict dishonest rather than useful. May be revisited as an evidence-capture-only exercise later.
- Only Areas A and C are automated. The other 17 areas in the guide (messaging, persistence, resilience, OpenShift, agentic/HITL, etc.) are still manual.

## Adding a new area

1. Copy `scripts/areas/area-a.sh` (or `area-c.sh`, if the new area also needs a Dev UI interaction) as a starting skeleton.
2. Reuse [`lib/bootstrap.sh`](lib/bootstrap.sh) for the base project instead of re-deriving the create/add-extension/write-Java-DSL/compile steps.
3. Add any Java/YAML fixtures the new area needs under `templates/area-<x>/`.
4. Reuse the helpers in `lib/` (`common.sh`, `http.sh`, `process.sh`, `evidence.sh`, `result.sh`, `bootstrap.sh`, `html.sh`) before adding new ones.
5. Add a line to [`config/areas.tsv`](config/areas.tsv) (area id, title, description) so the new area's report gets a proper title and shows up on the landing page.
6. `scripts/run.sh` picks up any script placed in `scripts/areas/` automatically — no registration needed. Add the new job to `.github/workflows/exploratory.yml` (copy an existing area job, using the shared `./.github/actions/setup-flow-env` action) and add it to `publish-report`'s `needs:` list plus its own download/render block.

## Troubleshooting

| Symptom | Meaning | What the script does |
|---|---|---|
| `curl: (7) Failed to connect` (curl exit code, not HTTP status) | `quarkus:dev` isn't listening yet | Reported distinctly from HTTP status codes so it's clear the app never came up, not that an endpoint returned an error. |
| `{"message":null}` from `GET /hello-flow` | Typed response mapping issue | Automatically fetches `/hello-flow/debug` and attaches both bodies to the failure note for diagnosis. |
| Port already in use before start | Another process is on `APP_PORT` | Detected before launching `quarkus:dev`; reported as `⛔ Blocked` with the offending PID when `lsof` is available, rather than hanging. |
| `add-extension`/project creation fails after retries | Maven/network flakiness, or version incompatibility | Reported as `⛔ Blocked` (retries exhausted) vs. `🔴 Failed` (e.g. `pom.xml` malformed) — check `create-project.log` / `add-extension.log`, and consider bumping `QF_VERSION` / `QUARKUS_PLATFORM_VERSION`. |
| Live reload never observes the new message | Recompile taking longer than `LIVE_RELOAD_TIMEOUT_SECONDS`, or the edit broke compilation | Check `live-reload-devmode-log-tail.txt` and `hello-flow-response-after-reload.json`. |
| `dev mode did not become ready within Ns` | Almost always just slow startup under load, not a real hang — `devmode.log` will show it stopped mid-boot (e.g. right after `Listening for transport dt_socket at address: 5005`, the JVM debug-agent line, but before Quarkus's own `started in Xs. Listening on: http://localhost:8080` banner) rather than showing any error. Confirmed by re-running with `READY_TIMEOUT_SECONDS` raised: the exact same project finished in under 40s once the machine had less contention (other IDE/Maven processes running in the background). | Check `port 8080`/`5005` aren't held by a leftover process (`lsof -nP -iTCP:8080 -sTCP:LISTEN`); if they're free, just retry with a higher `READY_TIMEOUT_SECONDS`. |

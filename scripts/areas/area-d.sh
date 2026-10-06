#!/usr/bin/env bash
# Area D — REST and Runner Execution automation.
#
# Automates the Quarkus Flow Exploratory Testing Guide's Area D: on top of
# Area A's base project (reused via lib/bootstrap.sh for the custom REST
# path), add the quarkus-flow-runner and smallrye-openapi extensions,
# configure the Runner to source a YAML workflow from
# src/main/resources/workflows with security disabled for local dev, run
# under `quarkus:dev`, then verify both the custom REST endpoint and the
# Runner's generic exec endpoint — valid sync/async execution plus a
# battery of invalid-input cases — and confirm OpenAPI/Swagger UI exposure.
#
# Unlike Area A/C's Java DSL fixtures, the quarkus-flow-runner extension's
# exact add-extension coordinates and the exec endpoint's real request /
# response shapes and status codes have not been independently confirmed
# against a real run yet. Negative-case steps below therefore check for
# "some 4xx client error" rather than an exact code, and always capture the
# real status/body as evidence so the actual behavior is visible in the
# report regardless of how it's classified.
#
# Deliberately does NOT use `set -e` — see area-a.sh's header comment for
# why; the same reasoning applies here.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../../lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=../../lib/http.sh
source "${REPO_ROOT}/lib/http.sh"
# shellcheck source=../../lib/process.sh
source "${REPO_ROOT}/lib/process.sh"
# shellcheck source=../../lib/evidence.sh
source "${REPO_ROOT}/lib/evidence.sh"
# shellcheck source=../../lib/result.sh
source "${REPO_ROOT}/lib/result.sh"
# shellcheck source=../../lib/bootstrap.sh
source "${REPO_ROOT}/lib/bootstrap.sh"

if [ -f "${REPO_ROOT}/config/defaults.env" ]; then
  # shellcheck source=../../config/defaults.env
  source "${REPO_ROOT}/config/defaults.env"
fi

# ---- Configuration (env-overridable; defaults.env already applied above) ----
: "${QF_VERSION:=1.1.0}"
: "${QUARKUS_PLATFORM_VERSION:=3.37.4}"
: "${TEST_GROUP_ID:=org.acme}"
: "${TEST_ARTIFACT_ID:=hello-flow}"
: "${APP_PORT:=8080}"
: "${READY_TIMEOUT_SECONDS:=180}"
: "${LIVE_RELOAD_TIMEOUT_SECONDS:=30}"
: "${LIVE_RELOAD_POLL_INTERVAL_SECONDS:=2}"
: "${HTTP_TIMEOUT_SECONDS:=10}"
: "${GRACEFUL_STOP_SECONDS:=10}"
: "${RETRY_MAX_ATTEMPTS:=3}"
: "${RETRY_DELAY_SECONDS:=5}"
export HTTP_TIMEOUT_SECONDS

if is_ci; then
  READY_TIMEOUT_SECONDS=$((READY_TIMEOUT_SECONDS * 2))
  RETRY_MAX_ATTEMPTS=$((RETRY_MAX_ATTEMPTS + 2))
fi

RUN_ID="$(run_id)"
WORKDIR="${REPO_ROOT}/work/area-d/${RUN_ID}"
PROJECT_DIR="${WORKDIR}/${TEST_ARTIFACT_ID}"
EVIDENCE_DIR="${REPO_ROOT}/evidence/area-d/${RUN_ID}"
BOOTSTRAP_TEMPLATES_DIR="${REPO_ROOT}/templates/area-a"
TEMPLATES_DIR="${REPO_ROOT}/templates/area-d"
BASE_URL="http://localhost:${APP_PORT}"
PACKAGE_PATH="$(java_package_to_path "$TEST_GROUP_ID")"

# Must match templates/area-d/greet.yaml's `document` block.
RUNNER_NAMESPACE="qe"
RUNNER_NAME="greet"
RUNNER_VERSION="1.1.0"

init_evidence_dir "$EVIDENCE_DIR"
RUN_LOG="${EVIDENCE_DIR}/run.log"
init_results "${EVIDENCE_DIR}/results.tsv"
ensure_dir "$WORKDIR"

CLEANED_UP=false
cleanup() {
  $CLEANED_UP && return
  CLEANED_UP=true
  if [ -n "${DEVMODE_PID:-}" ]; then
    stop_background "$DEVMODE_PID" "$DEVMODE_PGID" "$GRACEFUL_STOP_SECONDS"
  fi
  render_summary "$EVIDENCE_DIR" "area-d"
}
trap cleanup EXIT INT TERM

# ---- Step functions ----
# Same fatal-vs-independent split as area-a.sh/area-c.sh: setup through
# starting dev mode is fatal; the checks after that are independent of
# each other.

step_preflight() {
  if ! require_cmd java mvn curl git; then
    record_result preflight "Preflight tool check" BLOCKED "missing required command(s), see run.log"
    return 1
  fi
  local jv
  jv="$(java_major_version)"
  if [ -z "$jv" ] || [ "$jv" -lt 17 ]; then
    record_result preflight "Preflight tool check" BLOCKED "Java 17+ required, found: ${jv:-unknown}"
    return 1
  fi
  record_result preflight "Preflight tool check" PASS "java=${jv}"
  return 0
}

step_capture_environment() {
  capture_cmd "Java version" "${EVIDENCE_DIR}/java-version.txt" java -version
  capture_cmd "Maven version" "${EVIDENCE_DIR}/maven-version.txt" mvn -version
  capture_cmd "OS info" "${EVIDENCE_DIR}/os-info.txt" uname -a
  record_result capture_env "Capture environment info" PASS ""
  return 0
}

step_configure_runner() {
  local workflows_dir="${PROJECT_DIR}/src/main/resources/workflows"
  ensure_dir "$workflows_dir"
  cp "${TEMPLATES_DIR}/greet.yaml" "${workflows_dir}/greet.yaml"
  cat "${TEMPLATES_DIR}/application.properties" >> "${PROJECT_DIR}/src/main/resources/application.properties"

  if [ ! -f "${workflows_dir}/greet.yaml" ]; then
    record_result configure_runner "Configure Runner workflow source + properties" FAIL "greet.yaml missing after copy"
    return 1
  fi

  cp "${workflows_dir}/greet.yaml" "${EVIDENCE_DIR}/greet.yaml"
  cp "${PROJECT_DIR}/src/main/resources/application.properties" "${EVIDENCE_DIR}/application.properties"
  record_result configure_runner "Configure Runner workflow source + properties" PASS ""
  return 0
}

step_start_devmode() {
  if port_in_use "$APP_PORT"; then
    local owner
    owner="$(port_owner_pid "$APP_PORT")"
    record_result start_devmode "Start quarkus:dev" BLOCKED "port ${APP_PORT} already in use${owner:+ (pid ${owner})}"
    return 1
  fi

  start_background "$PROJECT_DIR" "${EVIDENCE_DIR}/devmode.log" ./mvnw -B quarkus:dev

  if ! wait_for_devmode_ready "${EVIDENCE_DIR}/devmode.log" "$APP_PORT" "$DEVMODE_PID" "$READY_TIMEOUT_SECONDS" 2; then
    record_result start_devmode "Start quarkus:dev" FAIL "dev mode did not become ready within ${READY_TIMEOUT_SECONDS}s, see devmode.log"
    return 1
  fi

  if ! grep -q "HelloFlow" "${EVIDENCE_DIR}/devmode.log" || ! grep -q "greet" "${EVIDENCE_DIR}/devmode.log"; then
    record_result start_devmode "Start quarkus:dev" OBSERVATION "port is open but 'HelloFlow'/'greet' markers not both seen in startup log (best-effort check)"
    return 0
  fi

  record_result start_devmode "Start quarkus:dev" PASS ""
  return 0
}

step_curl_custom_rest() {
  local out="${EVIDENCE_DIR}/hello-flow-response.json"
  http_get "${BASE_URL}/hello-flow" "$out"

  if [ "$CURL_EXIT" -ne 0 ]; then
    record_result custom_rest "GET /hello-flow (custom REST endpoint)" FAIL "curl exit ${CURL_EXIT} (connection issue — is dev mode listening?)"
    return 1
  fi
  if [ "$HTTP_STATUS" != "200" ]; then
    record_result custom_rest "GET /hello-flow (custom REST endpoint)" FAIL "expected 200, got ${HTTP_STATUS}"
    return 1
  fi
  if ! json_field_equals "$out" ".message" "hello world!"; then
    record_result custom_rest "GET /hello-flow (custom REST endpoint)" FAIL "unexpected message body, see hello-flow-response.json"
    return 1
  fi

  record_result custom_rest "GET /hello-flow (custom REST endpoint)" PASS ""
  return 0
}

_runner_exec_url() {
  local wait_param="$1"
  echo "${BASE_URL}/q/flow/exec/${RUNNER_NAMESPACE}/${RUNNER_NAME}/${RUNNER_VERSION}${wait_param:+?wait=${wait_param}}"
}

step_runner_exec_valid_wait_true() {
  local out="${EVIDENCE_DIR}/runner-exec-valid-wait-true.json"
  http_post "$(_runner_exec_url true)" "$out" -H 'Content-Type: application/json' -d '{"name":"Runner"}'

  if [ "$CURL_EXIT" -ne 0 ]; then
    record_result runner_valid_wait_true "Runner exec: valid input, wait=true" FAIL "curl exit ${CURL_EXIT}"
    return 1
  fi
  case "$HTTP_STATUS" in
    2*) ;;
    *)
      record_result runner_valid_wait_true "Runner exec: valid input, wait=true" FAIL "expected 2xx, got ${HTTP_STATUS}, see runner-exec-valid-wait-true.json"
      return 1
      ;;
  esac
  if ! http_body_contains "$out" "Hello, Runner!"; then
    record_result runner_valid_wait_true "Runner exec: valid input, wait=true" FAIL "expected 'Hello, Runner!' in response, got status=${HTTP_STATUS}, see runner-exec-valid-wait-true.json"
    return 1
  fi

  record_result runner_valid_wait_true "Runner exec: valid input, wait=true" PASS "status=${HTTP_STATUS}"
  return 0
}

step_runner_exec_valid_wait_false() {
  local out="${EVIDENCE_DIR}/runner-exec-valid-wait-false.json"
  http_post "$(_runner_exec_url false)" "$out" -H 'Content-Type: application/json' -d '{"name":"Runner"}'

  if [ "$CURL_EXIT" -ne 0 ]; then
    record_result runner_valid_wait_false "Runner exec: valid input, wait=false" OBSERVATION "curl exit ${CURL_EXIT}, behavior unconfirmed — see runner-exec-valid-wait-false.json"
    return 0
  fi
  case "$HTTP_STATUS" in
    2*)
      record_result runner_valid_wait_false "Runner exec: valid input, wait=false" PASS "status=${HTTP_STATUS}, see runner-exec-valid-wait-false.json"
      ;;
    *)
      record_result runner_valid_wait_false "Runner exec: valid input, wait=false" OBSERVATION "status=${HTTP_STATUS}; async-accepted shape not confirmed, see runner-exec-valid-wait-false.json"
      ;;
  esac
  return 0
}

_runner_exec_graceful_empty_case() {
  local result_id="$1" description="$2" url="$3" out_name="$4"
  shift 4
  local out="${EVIDENCE_DIR}/${out_name}"
  http_post "$url" "$out" "$@"

  if [ "$CURL_EXIT" -ne 0 ]; then
    record_result "$result_id" "$description" FAIL "curl exit ${CURL_EXIT}, see ${out_name}"
    return 1
  fi
  if [ "$HTTP_STATUS" != "200" ]; then
    record_result "$result_id" "$description" FAIL "expected 200, got ${HTTP_STATUS}, see ${out_name}"
    return 1
  fi
  if ! http_body_contains "$out" '"status":"COMPLETED"'; then
    record_result "$result_id" "$description" FAIL "expected a COMPLETED workflow, see ${out_name}"
    return 1
  fi

  record_result "$result_id" "$description" PASS "status=200, workflow completed with the missing field treated as empty, see ${out_name}"
  return 0
}

_runner_exec_negative_case() {
  local result_id="$1" description="$2" url="$3" out_name="$4"
  shift 4
  local out="${EVIDENCE_DIR}/${out_name}"
  http_post "$url" "$out" "$@"

  if [ "$CURL_EXIT" -ne 0 ]; then
    record_result "$result_id" "$description" OBSERVATION "curl exit ${CURL_EXIT}, see ${out_name}"
    return 0
  fi
  case "$HTTP_STATUS" in
    4*)
      record_result "$result_id" "$description" PASS "status=${HTTP_STATUS}, see ${out_name}"
      ;;
    *)
      local body_snippet
      body_snippet="$(tr -d '\n' < "$out" 2>/dev/null | cut -c1-200)"
      record_result "$result_id" "$description" FAIL "expected a 4xx client error, got ${HTTP_STATUS} — workflow ran to completion instead of being rejected, see ${out_name}: ${body_snippet}"
      return 1
      ;;
  esac
  return 0
}

step_runner_exec_missing_body() {
  # Confirmed product decision: the Runner doesn't validate input against the
  # workflow's declared schema before starting (see RunnerExecResource in
  # quarkiverse/quarkus-flow — definition.instance(request) is called
  # directly, with no schema-validation step). A missing body is expected to
  # be accepted and run with the field(s) treated as empty, not rejected.
  _runner_exec_graceful_empty_case runner_missing_body "Runner exec: missing body is accepted and runs with the input treated as empty" \
    "$(_runner_exec_url true)" "runner-exec-missing-body.json" \
    -H 'Content-Type: application/json'
}

step_runner_exec_invalid_json() {
  _runner_exec_negative_case runner_invalid_json "Runner exec: invalid JSON body" \
    "$(_runner_exec_url true)" "runner-exec-invalid-json.json" \
    -H 'Content-Type: application/json' -d '{not valid json'
}

step_runner_exec_wrong_content_type() {
  _runner_exec_negative_case runner_wrong_content_type "Runner exec: wrong content type" \
    "$(_runner_exec_url true)" "runner-exec-wrong-content-type.json" \
    -H 'Content-Type: text/plain' -d '{"name":"Runner"}'
}

step_runner_exec_unknown_workflow() {
  local url="${BASE_URL}/q/flow/exec/nope/nope/1.1.0?wait=true"
  _runner_exec_negative_case runner_unknown_workflow "Runner exec: unknown namespace/name" \
    "$url" "runner-exec-unknown-workflow.json" \
    -H 'Content-Type: application/json' -d '{"name":"Runner"}'
}

step_runner_exec_invalid_version() {
  local url="${BASE_URL}/q/flow/exec/${RUNNER_NAMESPACE}/${RUNNER_NAME}/9.9.9?wait=true"
  _runner_exec_negative_case runner_invalid_version "Runner exec: unknown version" \
    "$url" "runner-exec-invalid-version.json" \
    -H 'Content-Type: application/json' -d '{"name":"Runner"}'
}

step_runner_exec_missing_required_field() {
  # Unlike step_runner_exec_missing_body (no body at all), an explicit {}
  # that's missing the "name" the workflow's input.schema declares required
  # is expected to be rejected with a 4xx schema-validation error. The Runner
  # does not currently do this — definition.instance(request) is called
  # directly with no schema-validation step, so this is intentionally
  # expected to FAIL until that validation gap is fixed upstream.
  _runner_exec_negative_case runner_missing_required_field "Runner exec: input missing the required 'name' field should be rejected" \
    "$(_runner_exec_url true)" "runner-exec-missing-required-field.json" \
    -H 'Content-Type: application/json' -d '{}'
}

step_openapi_reachable() {
  local out="${EVIDENCE_DIR}/openapi.json"
  http_get "${BASE_URL}/q/openapi" "$out"

  if [ "$HTTP_STATUS" != "200" ]; then
    record_result openapi "GET /q/openapi" FAIL "expected 200, got ${HTTP_STATUS}"
    return 1
  fi

  local note="status=200"
  if http_body_contains "$out" "/q/flow/exec"; then
    note="status=200; Runner exec path found in OpenAPI document"
  else
    note="status=200; Runner exec path not found in OpenAPI document (see openapi.json)"
  fi
  record_result openapi "GET /q/openapi" OBSERVATION "$note"
  return 0
}

step_swagger_ui_reachable() {
  local out="${EVIDENCE_DIR}/swagger-ui-response.html"
  http_get "${BASE_URL}/q/swagger-ui" "$out" -L

  if [ "$HTTP_STATUS" != "200" ]; then
    record_result swagger_ui "Swagger UI reachable at /q/swagger-ui" FAIL "expected 200, got ${HTTP_STATUS}"
    return 1
  fi

  record_result swagger_ui "Swagger UI reachable at /q/swagger-ui" PASS ""
  return 0
}

# ---- Orchestration ----

main() {
  log_info "Area D run starting: RUN_ID=${RUN_ID}"
  log_info "Project dir: ${PROJECT_DIR}"
  log_info "Evidence dir: ${EVIDENCE_DIR}"

  step_preflight || exit 1
  step_capture_environment
  bootstrap_create_project || exit 1
  bootstrap_add_flow_extension || exit 1
  # Pinned to QF_VERSION explicitly, same as bootstrap_add_flow_extension does
  # for quarkus-flow itself: quarkus-flow-runner is NOT managed by the same
  # BOM/version as quarkus-flow, so an unpinned add-extension can resolve a
  # much older runner release (e.g. 0.13.0) whose WorkflowApplication.Builder
  # API predates methods the pinned quarkus-flow version's runtime calls —
  # confirmed live as a NoSuchMethodError on withAllowedCommands(Collection)
  # when left unpinned.
  bootstrap_add_extension "io.quarkiverse.flow:quarkus-flow-runner:${QF_VERSION}" add_runner_extension \
    "Add quarkus-flow-runner extension" "add-runner-extension.log" "quarkus-flow-runner" || exit 1
  bootstrap_add_extension "smallrye-openapi" add_openapi_extension \
    "Add smallrye-openapi extension" "add-openapi-extension.log" "smallrye-openapi" || exit 1
  # bootstrap_write_java_dsl_sources is the only bootstrap function that
  # reads TEMPLATES_DIR — point it at Area A's templates just for this one
  # call (reusing HelloFlow/Message/HelloResource verbatim as the "custom
  # REST endpoint" path), then the script's own TEMPLATES_DIR
  # (templates/area-d) applies again below.
  TEMPLATES_DIR="$BOOTSTRAP_TEMPLATES_DIR" bootstrap_write_java_dsl_sources || exit 1
  step_configure_runner || exit 1
  bootstrap_compile || exit 1
  step_start_devmode || exit 1

  step_curl_custom_rest || true
  step_runner_exec_valid_wait_true || true
  step_runner_exec_valid_wait_false || true
  step_runner_exec_missing_body || true
  step_runner_exec_invalid_json || true
  step_runner_exec_wrong_content_type || true
  step_runner_exec_unknown_workflow || true
  step_runner_exec_invalid_version || true
  step_runner_exec_missing_required_field || true
  step_openapi_reachable || true
  step_swagger_ui_reachable || true
}

set -m
main "$@"
exit "$(worst_status_exit_code)"

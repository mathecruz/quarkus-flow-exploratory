#!/usr/bin/env bash
# Shared "generate a Quarkus project + add quarkus-flow + write the Java DSL
# hello workflow + compile" bootstrap, reused by every area that needs a
# working quarkus-flow project as its starting point (Area A, Area C, ...).
# Relies on globals the calling area script has already set: WORKDIR,
# PROJECT_DIR, EVIDENCE_DIR, TEMPLATES_DIR, TEST_GROUP_ID, TEST_ARTIFACT_ID,
# QUARKUS_PLATFORM_VERSION, QF_VERSION, RETRY_MAX_ATTEMPTS, RETRY_DELAY_SECONDS,
# PACKAGE_PATH, APP_PORT.
# Sourced by area scripts — do not execute directly.

_bootstrap_mvn_create_project() {
  mvn -B -q io.quarkus.platform:quarkus-maven-plugin:"${QUARKUS_PLATFORM_VERSION}":create \
    -DprojectGroupId="${TEST_GROUP_ID}" \
    -DprojectArtifactId="${TEST_ARTIFACT_ID}" \
    -DplatformVersion="${QUARKUS_PLATFORM_VERSION}" \
    -Dextensions="rest-jackson" \
    -DoutputDirectory="${WORKDIR}" \
    >> "${EVIDENCE_DIR}/create-project.log" 2>&1
}

# bootstrap_create_project — generates the Quarkus project via the Maven
# plugin (no Quarkus CLI dependency). Records result id "create_project".
bootstrap_create_project() {
  : > "${EVIDENCE_DIR}/create-project.log"

  if port_in_use "$APP_PORT"; then
    local owner
    owner="$(port_owner_pid "$APP_PORT")"
    record_result create_project "Create Quarkus project" BLOCKED "port ${APP_PORT} already in use${owner:+ (pid ${owner})}"
    return 1
  fi

  ensure_dir "$WORKDIR"
  if ! retry "$RETRY_MAX_ATTEMPTS" "$RETRY_DELAY_SECONDS" _bootstrap_mvn_create_project; then
    record_result create_project "Create Quarkus project" BLOCKED "project generation failed after retries, see create-project.log"
    return 1
  fi

  if [ ! -f "${PROJECT_DIR}/pom.xml" ] || [ ! -x "${PROJECT_DIR}/mvnw" ]; then
    record_result create_project "Create Quarkus project" FAIL "pom.xml or mvnw missing after generation"
    return 1
  fi

  find "$PROJECT_DIR" -type f | sort > "${EVIDENCE_DIR}/initial-files.txt"
  echo "$PROJECT_DIR" > "${EVIDENCE_DIR}/project-path.txt"
  record_result create_project "Create Quarkus project" PASS ""
  return 0
}

_bootstrap_mvn_add_flow_extension() {
  (cd "$PROJECT_DIR" && ./mvnw -B -q quarkus:add-extension \
    -Dextensions="io.quarkiverse.flow:quarkus-flow:${QF_VERSION}") \
    >> "${EVIDENCE_DIR}/add-extension.log" 2>&1
}

# bootstrap_add_flow_extension — adds the quarkus-flow extension. Records
# result id "add_extension".
bootstrap_add_flow_extension() {
  : > "${EVIDENCE_DIR}/add-extension.log"

  if ! retry "$RETRY_MAX_ATTEMPTS" "$RETRY_DELAY_SECONDS" _bootstrap_mvn_add_flow_extension; then
    record_result add_extension "Add quarkus-flow extension" BLOCKED "extension add failed after retries, see add-extension.log"
    return 1
  fi

  if ! grep -q "quarkus-flow" "${PROJECT_DIR}/pom.xml"; then
    record_result add_extension "Add quarkus-flow extension" FAIL "quarkus-flow not found in pom.xml after add-extension"
    return 1
  fi

  cp "${PROJECT_DIR}/pom.xml" "${EVIDENCE_DIR}/pom.xml"
  grep -n "quarkus-flow\|quarkus-rest-jackson" "${PROJECT_DIR}/pom.xml" > "${EVIDENCE_DIR}/pom-dependencies.txt" || true
  record_result add_extension "Add quarkus-flow extension" PASS ""
  return 0
}

# bootstrap_write_java_dsl_sources — renders HelloFlow.java, Message.java,
# and HelloResource.java from TEMPLATES_DIR into the generated project.
# Records result id "write_sources".
bootstrap_write_java_dsl_sources() {
  local pkg_dir="${PROJECT_DIR}/src/main/java/${PACKAGE_PATH}"
  ensure_dir "$pkg_dir"
  render_template "${TEMPLATES_DIR}/HelloFlow.java" "${pkg_dir}/HelloFlow.java" "PACKAGE=${TEST_GROUP_ID}"
  render_template "${TEMPLATES_DIR}/Message.java" "${pkg_dir}/Message.java" "PACKAGE=${TEST_GROUP_ID}"
  render_template "${TEMPLATES_DIR}/HelloResource.java" "${pkg_dir}/HelloResource.java" "PACKAGE=${TEST_GROUP_ID}"

  if [ ! -f "${pkg_dir}/HelloFlow.java" ] || [ ! -f "${pkg_dir}/Message.java" ] || [ ! -f "${pkg_dir}/HelloResource.java" ]; then
    record_result write_sources "Write workflow + REST source files" FAIL "one or more source files missing after render"
    return 1
  fi

  record_result write_sources "Write workflow + REST source files" PASS ""
  return 0
}

_bootstrap_mvn_add_extension() {
  local gav="$1" log_file="$2"
  (cd "$PROJECT_DIR" && ./mvnw -B -q quarkus:add-extension \
    -Dextensions="${gav}") \
    >> "${log_file}" 2>&1
}

# bootstrap_add_extension — adds an arbitrary extension GAV (no assumed
# version; relies on whatever platform BOM is already imported). Caller
# supplies its own result id/description/log file name so areas adding
# multiple extensions in one run don't collide. grep_pattern (if given) is
# checked against pom.xml in place of the GAV's artifact id substring.
bootstrap_add_extension() {
  local gav="$1" result_id="$2" description="$3" log_name="$4" grep_pattern="${5:-}"
  local log_file="${EVIDENCE_DIR}/${log_name}"
  : > "$log_file"

  if ! retry "$RETRY_MAX_ATTEMPTS" "$RETRY_DELAY_SECONDS" _bootstrap_mvn_add_extension "$gav" "$log_file"; then
    record_result "$result_id" "$description" BLOCKED "extension add failed after retries, see ${log_name}"
    return 1
  fi

  local needle="${grep_pattern:-$(echo "$gav" | cut -d: -f2)}"
  if ! grep -q "$needle" "${PROJECT_DIR}/pom.xml"; then
    record_result "$result_id" "$description" FAIL "'${needle}' not found in pom.xml after add-extension"
    return 1
  fi

  record_result "$result_id" "$description" PASS ""
  return 0
}

# bootstrap_compile — plain `clean compile`. Records result id "compile".
bootstrap_compile() {
  if ! (cd "$PROJECT_DIR" && ./mvnw -B clean compile) > "${EVIDENCE_DIR}/compile.log" 2>&1; then
    record_result compile "Compile project" FAIL "compile failed, see compile.log"
    return 1
  fi
  if grep -q "BUILD FAILURE" "${EVIDENCE_DIR}/compile.log"; then
    record_result compile "Compile project" FAIL "BUILD FAILURE found in compile.log despite exit 0"
    return 1
  fi
  record_result compile "Compile project" PASS ""
  return 0
}

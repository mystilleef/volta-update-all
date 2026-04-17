#!/usr/bin/env sh
# tests/test-volta-update-all.sh - test suite for volta-update-all.sh

set -eu

# ─── TEST HARNESS ─────────────────────────────────────────────────────────────
FAILURES=0

pass() {
  printf "✅ PASS: %s\n" "$1"
}

fail() {
  printf "❌ FAIL: %s\n" "$1"
  FAILURES=$((FAILURES + 1))
}

run_test() { # $1: test name, $2: function to run
  printf "\n▶️  RUN: %s\n" "$1"
  if "$2"; then
    pass "$1"
  else
    fail "$1"
  fi
}

# ─── MOCK SETUP ───────────────────────────────────────────────────────────────
MOCK_DIR="$(pwd)/tests/mock_bin"
SCRIPT="$(pwd)/volta-update-all.sh"

setup() {
  mkdir -p "${MOCK_DIR}"
  export PATH="${MOCK_DIR}:${PATH}"
  export VOLTA_FEATURE_PNPM=1 # Silence the warning
}

teardown() {
  rm -rf "${MOCK_DIR}"
}

create_mock_volta() {
  # The mock reads from environment variables to decide what to output
  cat << 'EOF' > "${MOCK_DIR}/volta"
#!/usr/bin/env sh
if [ "$1" = "list" ]; then
  if [ "${MOCK_VOLTA_LIST:-}" != "" ]; then
    printf "%b\n" "${MOCK_VOLTA_LIST}"
  else
    echo "node node@20.0.0"
  fi
elif [ "$1" = "install" ]; then
  if [ "${MOCK_VOLTA_INSTALL_FAIL:-0}" = "1" ]; then
    exit 1
  fi
  # Echo what was installed so we can assert on it
  echo "MOCK_INSTALL: $*" >&2
fi
EOF
  chmod +x "${MOCK_DIR}/volta"
}

# ─── TESTS ────────────────────────────────────────────────────────────────────

test_help() {
  setup
  OUT=$("${SCRIPT}" --help 2>&1 || true)
  teardown
  echo "${OUT}" | grep -q "Display the help message"
}

test_missing_volta() {
  setup
  # Overwrite path to hide our mock AND system volta
  export PATH="/usr/bin:/bin"
  OUT=$("${SCRIPT}" 2>&1 || true)
  teardown
  echo "${OUT}" | grep -q "Volta not found in PATH"
}

test_dry_run() {
  setup
  create_mock_volta
  export MOCK_VOLTA_LIST="node node@20.0.0"
  OUT=$("${SCRIPT}" --dry-run)
  teardown
  echo "${OUT}" | grep -q "would run: volta install --quiet node@lts" &&
    echo "${OUT}" | grep -q "Dry run complete."
}

test_exclude() {
  setup
  create_mock_volta
  export MOCK_VOLTA_LIST="node node@20.0.0\nnpm npm@10.0.0"
  OUT=$("${SCRIPT}" --exclude node 2>&1)
  teardown
  # Check that node was skipped and npm was installed
  echo "${OUT}" | grep -q "Skipping node" &&
    echo "${OUT}" | grep -q "npm already at 10.0.0"
}

test_exclude_missing_arg() {
  setup
  OUT=$("${SCRIPT}" --exclude 2>&1 || true)
  teardown
  echo "${OUT}" | grep -q "error: --exclude requires an argument."
}

test_upgrade_loop() {
  setup
  create_mock_volta
  export MOCK_VOLTA_LIST="node node@20.0.0"
  OUT=$("${SCRIPT}" 2>&1)
  teardown
  echo "${OUT}" | grep -q "Upgraded node" || echo "${OUT}" | grep -q "already at"
}

test_install_failure() {
  setup
  create_mock_volta
  export MOCK_VOLTA_LIST="node node@20.0.0"
  export MOCK_VOLTA_INSTALL_FAIL=1
  OUT=$("${SCRIPT}" 2>&1 || true)
  teardown
  echo "${OUT}" | grep -q "Failed to install node"
}

test_install() {
  setup
  _tmp_home="$(pwd)/tests/mock_home"
  mkdir -p "${_tmp_home}"
  export HOME="${_tmp_home}"

  OUT=$("${SCRIPT}" --install)
  _dest="${HOME}/.local/bin/volta-update-all"

  _res=1
  [ -x "${_dest}" ] && echo "${OUT}" | grep -q "Installed to" && _res=0

  rm -rf "${_tmp_home}"
  teardown
  return "${_res}"
}

test_scoped_packages() {
  setup
  create_mock_volta
  # Mock a scoped package and a normal package
  export MOCK_VOLTA_LIST="@openai/codex @openai/codex@0.121.0\nnormal normal@1.0.0"

  OUT=$("${SCRIPT}" --dry-run 2>&1)
  teardown

  # Ensure the scoped package and normal package were parsed correctly
  echo "${OUT}" | grep -q "would run: volta install --quiet @openai/codex@latest" &&
    echo "${OUT}" | grep -q "would run: volta install --quiet normal@latest"
}

test_pnpm_skipped_without_feature_flag() {
  setup
  create_mock_volta
  unset VOLTA_FEATURE_PNPM
  export MOCK_VOLTA_LIST="pnpm pnpm@9.0.0\nnode node@20.0.0"

  OUT=$("${SCRIPT}" --dry-run 2>&1)
  teardown

  echo "${OUT}" | grep -q "VOLTA_FEATURE_PNPM=1 not set; pnpm will be skipped." &&
    echo "${OUT}" | grep -q "Skipping pnpm" &&
    ! echo "${OUT}" | grep -q "would run: volta install --quiet pnpm@latest"
}

# ─── RUNNER ───────────────────────────────────────────────────────────────────
echo "🚀 Starting tests..."

run_test "Help output" test_help
run_test "Missing volta" test_missing_volta
run_test "Dry run" test_dry_run
run_test "Exclusion" test_exclude
run_test "Exclusion missing arg" test_exclude_missing_arg
run_test "Upgrade loop" test_upgrade_loop
run_test "Install failure" test_install_failure
run_test "Install flag" test_install
run_test "Scoped packages" test_scoped_packages
run_test "pnpm skipped without feature flag" test_pnpm_skipped_without_feature_flag

printf "\n🏁 Test Summary: %d failures\n" "${FAILURES}"
if [ "${FAILURES}" -gt 0 ]; then
  exit 1
fi

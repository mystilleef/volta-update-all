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

# Extract a function definition from the script for unit testing
extract_fn() { # $1: function name
  sed -n "/^${1}()/,/^}/p" "${SCRIPT}"
}

# ─── MOCK SETUP ───────────────────────────────────────────────────────────────
MOCK_DIR="${PWD}/tests/mock_bin"
SCRIPT="${PWD}/volta-update-all.sh"

setup() {
  unset MOCK_VOLTA_LIST MOCK_VOLTA_INSTALL_FAIL
  mkdir -p "${MOCK_DIR}"
  export PATH="${MOCK_DIR}:${PATH}"
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

test_version() {
  OUT=$("${SCRIPT}" --version 2>&1)
  echo "${OUT}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'
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
  export MOCK_VOLTA_LIST="node node@20.0.0-nightly\nnormal normal@1.0.0\npreview preview@0.0.1-nightly.20260508"
  OUT=$("${SCRIPT}" --dry-run)
  teardown
  echo "${OUT}" | grep -q "would run: volta install --quiet node@latest" &&
  echo "${OUT}" | grep -q "would run: volta install --quiet normal@latest" &&
  echo "${OUT}" | grep -q "would run: volta install --quiet preview@nightly" &&
  ! echo "${OUT}" | grep -q "would run: volta install --quiet node@nightly" &&
  echo "${OUT}" | grep -q "Dry run complete."
}

test_exclude() {
  setup
  create_mock_volta
  _root="${PWD}/tests/tmp_exclude"
  mkdir -p "${_root}"
  cp "${SCRIPT}" "${_root}/volta-update-all.sh"
  export MOCK_VOLTA_LIST="node node@20.0.0\nnpm npm@10.0.0"
  OUT=$(cd "${_root}" && ./volta-update-all.sh --exclude node 2>&1)
  rm -rf "${_root}"
  teardown
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
  _root="${PWD}/tests/tmp_upgrade"
  mkdir -p "${_root}"
  cp "${SCRIPT}" "${_root}/volta-update-all.sh"
  export MOCK_VOLTA_LIST="node node@20.0.0"
  OUT=$(cd "${_root}" && ./volta-update-all.sh 2>&1)
  rm -rf "${_root}"
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
  _root="${PWD}/tests/tmp_install_basic"
  mkdir -p "${_root}"
  cp "${SCRIPT}" "${_root}/volta-update-all.sh"

  _tmp_home="${PWD}/tests/mock_home"
  mkdir -p "${_tmp_home}"
  export HOME="${_tmp_home}"

  OUT=$(cd "${_root}" && ./volta-update-all.sh --install)
  _dest="${HOME}/.local/bin/volta-update-all"

  _res=1
  [ -L "${_dest}" ] && echo "${OUT}" | grep -q "Installed to" && _res=0

  rm -rf "${_tmp_home}" "${_root}"
  teardown
  return "${_res}"
}

test_scoped_packages() {
  setup
  create_mock_volta
  export MOCK_VOLTA_LIST="@openai/codex @openai/codex@0.121.0\nnormal normal@1.0.0"

  OUT=$("${SCRIPT}" --dry-run 2>&1)
  teardown

  echo "${OUT}" | grep -q "would run: volta install --quiet @openai/codex@latest" &&
  echo "${OUT}" | grep -q "would run: volta install --quiet normal@latest"
}

# ─── T-002: SNAPSHOT MAINTENANCE ─────────────────────────────────────────────

test_snapshot_created_after_upgrade() {
  setup
  create_mock_volta
  _proj_dir="${PWD}/tests/tmp_snap_proj"
  mkdir -p "${_proj_dir}"
  cp "${SCRIPT}" "${_proj_dir}/volta-update-all.sh"
  export MOCK_VOLTA_LIST="node node@20.0.0\nnpm npm@10.0.0"

  OUT=$(cd "${_proj_dir}" && ./volta-update-all.sh 2>&1)
  _res=0

  [ -f "${_proj_dir}/volta-packages.txt" ] || _res=1
  if [ "${_res}" -eq 0 ]; then
    _content=$(cat "${_proj_dir}/volta-packages.txt")
    echo "${_content}" | grep -q "node@20.0.0" || _res=1
    echo "${_content}" | grep -q "npm@10.0.0" || _res=1
  fi
  echo "${OUT}" | grep -q "Snapshot saved to" || _res=1

  rm -rf "${_proj_dir}"
  teardown
  return "${_res}"
}

test_snapshot_via_symlink() {
  setup
  create_mock_volta
  _proj_dir="${PWD}/tests/tmp_snap_sym_proj"
  _link_dir="${PWD}/tests/tmp_snap_sym_bin"
  mkdir -p "${_proj_dir}" "${_link_dir}"
  cp "${SCRIPT}" "${_proj_dir}/volta-update-all.sh"
  ln -sf "${_proj_dir}/volta-update-all.sh" "${_link_dir}/volta-update-all"
  export MOCK_VOLTA_LIST="node node@20.0.0"

  OUT=$("${_link_dir}/volta-update-all" 2>&1)
  _res=0

  # Snapshot written to real script location, not symlink dir
  [ -f "${_proj_dir}/volta-packages.txt" ] || _res=1
  [ ! -f "${_link_dir}/volta-packages.txt" ] || _res=1

  rm -rf "${_proj_dir}" "${_link_dir}"
  teardown
  return "${_res}"
}

test_dry_run_no_snapshot() {
  setup
  create_mock_volta
  _proj_dir="${PWD}/tests/tmp_snap_dry"
  mkdir -p "${_proj_dir}"
  cp "${SCRIPT}" "${_proj_dir}/volta-update-all.sh"
  export MOCK_VOLTA_LIST="node node@20.0.0"

  OUT=$(cd "${_proj_dir}" && ./volta-update-all.sh --dry-run 2>&1)
  _res=0

  echo "${OUT}" | grep -q "Dry run complete." || _res=1
  [ ! -f "${_proj_dir}/volta-packages.txt" ] || _res=1

  rm -rf "${_proj_dir}"
  teardown
  return "${_res}"
}

test_failed_upgrade_preserves_snapshot() {
  setup
  create_mock_volta
  _proj_dir="${PWD}/tests/tmp_snap_fail"
  mkdir -p "${_proj_dir}"
  cp "${SCRIPT}" "${_proj_dir}/volta-update-all.sh"
  echo "node@18.0.0" > "${_proj_dir}/volta-packages.txt"
  export MOCK_VOLTA_LIST="node node@20.0.0"
  export MOCK_VOLTA_INSTALL_FAIL=1

  OUT=$(cd "${_proj_dir}" && ./volta-update-all.sh 2>&1 || true)
  _res=0

  _content=$(cat "${_proj_dir}/volta-packages.txt")
  [ "${_content}" = "node@18.0.0" ] || _res=1

  rm -rf "${_proj_dir}"
  teardown
  return "${_res}"
}

test_snapshot_empty_tool_list() {
  setup
  create_mock_volta
  _proj_dir="${PWD}/tests/tmp_snap_empty"
  mkdir -p "${_proj_dir}"
  cp "${SCRIPT}" "${_proj_dir}/volta-update-all.sh"
  export MOCK_VOLTA_LIST=""

  OUT=$(cd "${_proj_dir}" && ./volta-update-all.sh 2>&1)
  _res=0

  [ -f "${_proj_dir}/volta-packages.txt" ] || _res=1

  rm -rf "${_proj_dir}"
  teardown
  return "${_res}"
}

test_snapshot_scoped_packages() {
  setup
  create_mock_volta
  _proj_dir="${PWD}/tests/tmp_snap_scoped"
  mkdir -p "${_proj_dir}"
  cp "${SCRIPT}" "${_proj_dir}/volta-update-all.sh"
  export MOCK_VOLTA_LIST="@openai/codex @openai/codex@0.121.0\n@scope/pkg @scope/pkg@1.0.0"

  OUT=$(cd "${_proj_dir}" && ./volta-update-all.sh 2>&1)
  _res=0

  [ -f "${_proj_dir}/volta-packages.txt" ] || _res=1
  if [ "${_res}" -eq 0 ]; then
    _content=$(cat "${_proj_dir}/volta-packages.txt")
    echo "${_content}" | grep -q "@openai/codex@0.121.0" || _res=1
    echo "${_content}" | grep -q "@scope/pkg@1.0.0" || _res=1
  fi

  rm -rf "${_proj_dir}"
  teardown
  return "${_res}"
}

test_snapshot_overwrite() {
  setup
  create_mock_volta
  _proj_dir="${PWD}/tests/tmp_snap_overwrite"
  mkdir -p "${_proj_dir}"
  cp "${SCRIPT}" "${_proj_dir}/volta-update-all.sh"

  # First run — snapshot v1
  export MOCK_VOLTA_LIST="node node@20.0.0"
  (cd "${_proj_dir}" && ./volta-update-all.sh > /dev/null 2>&1)

  # Second run — snapshot v2 should overwrite
  export MOCK_VOLTA_LIST="node node@22.0.0\nnpm npm@10.0.0"
  (cd "${_proj_dir}" && ./volta-update-all.sh > /dev/null 2>&1)

  _res=0
  _content=$(cat "${_proj_dir}/volta-packages.txt")
  echo "${_content}" | grep -q "node@22.0.0" || _res=1
  echo "${_content}" | grep -q "npm@10.0.0" || _res=1

  rm -rf "${_proj_dir}"
  teardown
  return "${_res}"
}

test_snapshot_saved_message() {
  setup
  create_mock_volta
  _proj_dir="${PWD}/tests/tmp_snap_msg"
  mkdir -p "${_proj_dir}"
  cp "${SCRIPT}" "${_proj_dir}/volta-update-all.sh"
  export MOCK_VOLTA_LIST="node node@20.0.0"

  OUT=$(cd "${_proj_dir}" && ./volta-update-all.sh 2>&1)
  _res=0

  echo "${OUT}" | grep -q "Snapshot saved to" || _res=1
  echo "${OUT}" | grep -q "All done!" || _res=1

  rm -rf "${_proj_dir}"
  teardown
  return "${_res}"
}

test_literal_package_names() {
  setup
  create_mock_volta
  _root="${PWD}/tests/tmp_literal"
  mkdir -p "${_root}"
  cp "${SCRIPT}" "${_root}/volta-update-all.sh"
  export MOCK_VOLTA_LIST="toolxjs toolxjs@2.0.0\ntool.js tool.js@1.0.0"

  OUT=$(cd "${_root}" && ./volta-update-all.sh --exclude toolxjs 2>&1)
  rm -rf "${_root}"
  teardown

  echo "${OUT}" | grep -q "tool.js already at 1.0.0"
}

test_multiple_excludes() {
  setup
  create_mock_volta
  _root="${PWD}/tests/tmp_multi_excl"
  mkdir -p "${_root}"
  cp "${SCRIPT}" "${_root}/volta-update-all.sh"
  export MOCK_VOLTA_LIST="node node@20.0.0\nnpm npm@10.0.0\nyarn yarn@1.22.0"

  OUT=$(cd "${_root}" && ./volta-update-all.sh --exclude "node,npm" 2>&1)
  rm -rf "${_root}"
  teardown

  echo "${OUT}" | grep -q "Skipping node" &&
  echo "${OUT}" | grep -q "Skipping npm" &&
  ! echo "${OUT}" | grep -q "Skipping yarn" &&
  echo "${OUT}" | grep -q "yarn"
}

test_exclude_flag_like_arg() {
  setup
  OUT=$("${SCRIPT}" --exclude --someflag 2>&1 || true)
  teardown
  echo "${OUT}" | grep -q "error: --exclude requires an argument."
}

test_unknown_flag() {
  setup
  OUT=$("${SCRIPT}" --unknown-flag 2>&1 || true)
  teardown
  echo "${OUT}" | grep -q "unknown flag: --unknown-flag"
}

# ─── T-003: INSTALL-MODE SNAPSHOT RESTORE ────────────────────────────────────

test_install_restore_snapshot() {
  setup
  create_mock_volta
  _root="${PWD}/tests/tmp_install_restore"
  mkdir -p "${_root}"
  cp "${SCRIPT}" "${_root}/volta-update-all.sh"

  printf 'node@20.0.0\nnpm@10.0.0\n' > "${_root}/volta-packages.txt"

  _tmp_home="${PWD}/tests/tmp_install_home_1"
  mkdir -p "${_tmp_home}"
  export HOME="${_tmp_home}"

  OUT=$(cd "${_root}" && ./volta-update-all.sh --install 2>&1)
  _res=0

  _lines=$(echo "${OUT}" | grep -n "Restoring")
  echo "${_lines}" | grep -q "node @ 20.0.0" || _res=1
  echo "${_lines}" | grep -q "npm @ 10.0.0" || _res=1

  echo "${OUT}" | grep -q "Installed to" || _res=1
  echo "${OUT}" | grep -q "PATH" || _res=1

  # Script symlinked
  [ -L "${HOME}/.local/bin/volta-update-all" ] || _res=1

  rm -rf "${_root}" "${_tmp_home}"
  teardown
  return "${_res}"
}

test_install_absent_snapshot_warning() {
  setup
  _root="${PWD}/tests/tmp_install_no_snap"
  mkdir -p "${_root}"
  cp "${SCRIPT}" "${_root}/volta-update-all.sh"

  _tmp_home="${PWD}/tests/tmp_install_home_2"
  mkdir -p "${_tmp_home}"
  export HOME="${_tmp_home}"

  OUT=$(cd "${_root}" && ./volta-update-all.sh --install 2>&1)
  _res=0

  _count=$(echo "${OUT}" | grep -c "No volta-packages.txt")
  [ "${_count}" -eq 1 ] || _res=1

  echo "${OUT}" | grep -q "Installed to" || _res=1
  [ -L "${HOME}/.local/bin/volta-update-all" ] || _res=1

  rm -rf "${_root}" "${_tmp_home}"
  teardown
  return "${_res}"
}

test_install_restore_failure() {
  setup
  create_mock_volta
  export MOCK_VOLTA_INSTALL_FAIL=1
  _root="${PWD}/tests/tmp_install_fail"
  mkdir -p "${_root}"
  cp "${SCRIPT}" "${_root}/volta-update-all.sh"
  printf 'node@20.0.0\n' > "${_root}/volta-packages.txt"

  _tmp_home="${PWD}/tests/tmp_install_home_3"
  mkdir -p "${_tmp_home}"
  export HOME="${_tmp_home}"

  OUT=$(cd "${_root}" && ./volta-update-all.sh --install 2>&1 || true)
  _res=0

  echo "${OUT}" | grep -q "Failed to restore" || _res=1

  ! echo "${OUT}" | grep -q "Installed to" || _res=1
  ! echo "${OUT}" | grep -q "PATH" || _res=1

  # Script should NOT be symlinked
  [ ! -e "${HOME}/.local/bin/volta-update-all" ] || _res=1

  rm -rf "${_root}" "${_tmp_home}"
  teardown
  return "${_res}"
}

test_install_restore_missing_volta() {
  setup
  _root="${PWD}/tests/tmp_install_novolta"
  mkdir -p "${_root}"
  cp "${SCRIPT}" "${_root}/volta-update-all.sh"
  printf 'node@20.0.0\n' > "${_root}/volta-packages.txt"

  _tmp_home="${PWD}/tests/tmp_install_home_4"
  mkdir -p "${_tmp_home}"
  export HOME="${_tmp_home}"

  _saved_path="${PATH}"
  export PATH="/usr/bin:/bin"

  OUT=$(cd "${_root}" && ./volta-update-all.sh --install 2>&1 || true)
  _res=0

  echo "${OUT}" | grep -q "Volta not found" || _res=1
  ! echo "${OUT}" | grep -q "Installed to" || _res=1

  export PATH="${_saved_path}"
  rm -rf "${_root}" "${_tmp_home}"
  teardown
  return "${_res}"
}

test_install_blank_lines_skipped() {
  setup
  create_mock_volta
  _root="${PWD}/tests/tmp_install_blank"
  mkdir -p "${_root}"
  cp "${SCRIPT}" "${_root}/volta-update-all.sh"

  printf '\nnode@20.0.0\n   \n\tnpm@10.0.0\n\n' > "${_root}/volta-packages.txt"

  _tmp_home="${PWD}/tests/tmp_install_home_5"
  mkdir -p "${_tmp_home}"
  export HOME="${_tmp_home}"

  OUT=$(cd "${_root}" && ./volta-update-all.sh --install 2>&1)
  _res=0

  echo "${OUT}" | grep -q "node @ 20.0.0" || _res=1
  echo "${OUT}" | grep -q "npm @ 10.0.0" || _res=1
  echo "${OUT}" | grep -q "Installed to" || _res=1

  rm -rf "${_root}" "${_tmp_home}"
  teardown
  return "${_res}"
}

test_install_symlink_roundtrip() {
  setup
  create_mock_volta
  _proj_dir="${PWD}/tests/tmp_install_sym_proj"
  mkdir -p "${_proj_dir}"
  cp "${SCRIPT}" "${_proj_dir}/volta-update-all.sh"

  _tmp_home="${PWD}/tests/tmp_install_home_7"
  mkdir -p "${_tmp_home}"
  export HOME="${_tmp_home}"

  # Install creates a symlink pointing back to the project
  OUT=$(cd "${_proj_dir}" && ./volta-update-all.sh --install 2>&1)
  _link="${HOME}/.local/bin/volta-update-all"
  _res=0
  [ -L "${_link}" ] || _res=1

  # Run via symlink — snapshot goes to project dir, not symlink dir
  export MOCK_VOLTA_LIST="node node@20.0.0"
  OUT2=$("${_link}" 2>&1)
  echo "${OUT2}" | grep -q "already at 20.0.0" || _res=1
  [ -f "${_proj_dir}/volta-packages.txt" ] || _res=1
  [ ! -f "${HOME}/.local/bin/volta-packages.txt" ] || _res=1

  rm -rf "${_proj_dir}" "${_tmp_home}"
  teardown
  return "${_res}"
}

test_install_paths_with_spaces() {
  setup
  create_mock_volta
  _root="${PWD}/tests/tmp install with spaces"
  mkdir -p "${_root}"
  cp "${SCRIPT}" "${_root}/volta-update-all.sh"
  printf 'node@20.0.0\n' > "${_root}/volta-packages.txt"

  _tmp_home="${PWD}/tests/tmp home with spaces"
  mkdir -p "${_tmp_home}"
  export HOME="${_tmp_home}"

  OUT=$(cd "${_root}" && ./volta-update-all.sh --install 2>&1)
  _res=0

  echo "${OUT}" | grep -q "Restoring node @ 20.0.0" || _res=1
  echo "${OUT}" | grep -q "Installed to" || _res=1
  [ -L "${HOME}/.local/bin/volta-update-all" ] || _res=1

  rm -rf "${_root}" "${_tmp_home}"
  teardown
  return "${_res}"
}

# ─── T-001: SHARED POSIX HELPER SEAMS ────────────────────────────────────────

test_is_blank_line_helper() {
  _trim_fn=$(extract_fn "trim")
  _fn=$(extract_fn "is_blank_line")

  ( eval "${_trim_fn}"; eval "${_fn}"
    is_blank_line "" || exit 1
    is_blank_line "   " || exit 1
    is_blank_line "		" || exit 1
    ! is_blank_line "node@20.0.0" || exit 1
    ! is_blank_line "@scope/pkg@1.0.0" || exit 1
    ! is_blank_line "node" || exit 1
    ! is_blank_line "  node  " || exit 1
  ) || return 1
}

test_extract_tool_from_entry_helper() {
  _fn=$(extract_fn "extract_tool_from_entry")

  ( eval "${_fn}"
    _tool=$(extract_tool_from_entry "node@20.0.0")
    [ "${_tool}" = "node" ] || exit 1

    _tool=$(extract_tool_from_entry "@openai/codex@0.121.0")
    [ "${_tool}" = "@openai/codex" ] || exit 1

    _tool=$(extract_tool_from_entry "@scope/pkg@1.0.0")
    [ "${_tool}" = "@scope/pkg" ] || exit 1

    _tool=$(extract_tool_from_entry "pnpm@9.0.0")
    [ "${_tool}" = "pnpm" ] || exit 1
  ) || return 1
}

test_extract_version_from_entry_helper() {
  _fn=$(extract_fn "extract_version_from_entry")

  ( eval "${_fn}"
    _ver=$(extract_version_from_entry "node@20.0.0")
    [ "${_ver}" = "20.0.0" ] || exit 1

    _ver=$(extract_version_from_entry "@openai/codex@0.121.0")
    [ "${_ver}" = "0.121.0" ] || exit 1

    _ver=$(extract_version_from_entry "@scope/pkg@1.0.0")
    [ "${_ver}" = "1.0.0" ] || exit 1

    _ver=$(extract_version_from_entry "pnpm@9.0.0")
    [ "${_ver}" = "9.0.0" ] || exit 1
  ) || return 1
}

# ─── RUNNER ───────────────────────────────────────────────────────────────────
echo "🚀 Starting tests..."

run_test "Help output" test_help
run_test "Version output" test_version
run_test "Missing volta" test_missing_volta
run_test "Dry run" test_dry_run
run_test "Exclusion" test_exclude
run_test "Exclusion missing arg" test_exclude_missing_arg
run_test "Upgrade loop" test_upgrade_loop
run_test "Install failure" test_install_failure
run_test "Install flag" test_install
run_test "Scoped packages" test_scoped_packages
run_test "Literal package names" test_literal_package_names
run_test "Multiple comma-separated excludes" test_multiple_excludes
run_test "Exclude with flag-like argument" test_exclude_flag_like_arg
run_test "Unknown flag error" test_unknown_flag
run_test "Helper: is_blank_line" test_is_blank_line_helper
run_test "Helper: extract_tool_from_entry" test_extract_tool_from_entry_helper
run_test "Helper: extract_version_from_entry" test_extract_version_from_entry_helper
run_test "Snapshot: created after upgrade" test_snapshot_created_after_upgrade
run_test "Snapshot: via symlink" test_snapshot_via_symlink
run_test "Snapshot: dry-run no-write" test_dry_run_no_snapshot
run_test "Snapshot: failed upgrade preserves" test_failed_upgrade_preserves_snapshot
run_test "Snapshot: empty tool list" test_snapshot_empty_tool_list
run_test "Snapshot: scoped packages" test_snapshot_scoped_packages
run_test "Snapshot: overwrite on second run" test_snapshot_overwrite
run_test "Snapshot: saved message" test_snapshot_saved_message
run_test "Install: restore from snapshot" test_install_restore_snapshot
run_test "Install: absent snapshot warning" test_install_absent_snapshot_warning
run_test "Install: restore failure" test_install_restore_failure
run_test "Install: restore missing volta" test_install_restore_missing_volta
run_test "Install: blank lines skipped" test_install_blank_lines_skipped
run_test "Install: symlink roundtrip" test_install_symlink_roundtrip
run_test "Install: paths with spaces" test_install_paths_with_spaces

printf "\n🏁 Test Summary: %d failures\n" "${FAILURES}"
if [ "${FAILURES}" -gt 0 ]; then
  exit 1
fi

#!/bin/sh
# volta-update-all.sh - update every Volta-managed tool
#
# Flags:
#   --dry-run         Show what would change, make no installs
#   --exclude a,b,c   Comma-separated list of tool names to skip
#   --install         Install the script to ~/.local/bin/volta-update-all
#   --version         Print version and exit
#   -h, --help        Display the help message
#
# Works with POSIX sh - no Bash-only features.

set -eu

VERSION="0.1.0"

IFS='
' # newline

# ─── HELPERS ──────────────────────────────────────────────────────────────────
usage() {
  sed -n '2,11p' "$0"
  exit 1
}

trim() { # stdin → trimmed stdout
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

contains() { # $1 needle, $2 newline-separated haystack
  printf '%s\n' "$2" | grep -Fxq -- "$1"
}

current_version() { # $1 tool-name → prints "22.16.0", or "" if absent
  volta list --format=plain |
  awk -v tool="$1" '
      NF >= 2 {
        pkg = $2
        sub(/@[^@]*$/, "", pkg)
        if (pkg == tool) {
          sub(/.*@/, "", $2)
          print $2
          exit
        }
      }
    '
}

install_target() { # $1 tool-name, $2 current version → prints "tool@tag"
  if [ "$1" = node ]; then
    echo "$1@latest"
    return 0
  fi

  case $2 in
    *nightly*) echo "$1@nightly" ;;
    *) echo "$1@latest" ;;
  esac
}

script_dir() { # prints real directory of this script (follows one symlink level)
  _self=$(command -v "$0" 2>/dev/null || echo "$0")
  if _link=$(readlink "${_self}" 2>/dev/null); then
    dirname "${_link}"
  else
    cd "$(dirname "${_self}")" && pwd
  fi
}

# ─── SNAPSHOT ENTRY PARSING ──────────────────────────────────────────────────
is_blank_line() {
  [ -z "$(printf '%s\n' "$1" | trim)" ]
}

# $1: "tool@version" or "@scope/name@version" → prints "tool" or "@scope/name"
extract_tool_from_entry() {
  printf '%s\n' "$1" | sed 's/@[^@]*$//'
}

# $1: "tool@version" or "@scope/name@version" → prints "version"
extract_version_from_entry() {
  printf '%s\n' "$1" | sed 's/.*@//'
}

# ─── FLAG PARSE ───────────────────────────────────────────────────────────────
DRY=0
INSTALL=0
EXCL=""
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY=1 ;;
    --install) INSTALL=1 ;;
    --exclude)
      shift
      if [ $# -eq 0 ] || [ "$1" = "" ]; then
        echo "error: --exclude requires an argument." >&2
        usage
      fi
      case $1 in
        -*)
          echo "error: --exclude requires an argument." >&2
          usage
          ;;
        *) ;;
      esac
      EXCL=$1
      ;;
    --version) echo "${VERSION}"; exit 0 ;;
    -h | --help) usage ;;
    *)
      echo "unknown flag: $1" >&2
      usage
      ;;
  esac
  shift
done

if [ "${INSTALL}" -eq 1 ]; then
  _script_dir=$(script_dir)
  _snapshot="${_script_dir}/volta-packages.txt"

  if [ -f "${_snapshot}" ]; then
    command -v volta > /dev/null ||
    {
      echo "❌ Volta not found in PATH; cannot restore snapshot." >&2
      exit 1
    }

    while IFS= read -r _entry; do
      if is_blank_line "${_entry}"; then
        continue
      fi

      _tool=$(extract_tool_from_entry "${_entry}")
      _version=$(extract_version_from_entry "${_entry}")

      echo "📦 Restoring ${_tool} @ ${_version}..."
      if ! volta install --quiet "${_tool}@${_version}"; then
        echo "❌ Failed to restore ${_tool} @ ${_version}" >&2
        exit 1
      fi
    done < "${_snapshot}"

    echo "✅ Snapshot restore complete."
  else
    echo "⚠️  No volta-packages.txt snapshot found; skipping restore." >&2
  fi

  _dest="${HOME}/.local/bin"
  mkdir -p "${_dest}"
  ln -sf "${_script_dir}/$(basename "$0")" "${_dest}/volta-update-all"
  echo "✅ Installed to ${_dest}/volta-update-all"
  echo "💡 Please ensure ${_dest} is in your PATH."
  exit 0
fi

command -v volta > /dev/null ||
{
  echo "Volta not found in PATH" >&2
  exit 1
}

# ─── BUILD EXCLUDE LIST ───────────────────────────────────────────
set +e
EXCLUDES=$(printf '%s\n' "${EXCL}" |
  tr ',' '\n' |
  while IFS= read -r _exclude_item; do
    _exclude_item=$(printf '%s\n' "${_exclude_item}" | trim)
    [ "${_exclude_item}" != "" ] && printf '%s\n' "${_exclude_item}"
done)
set -e

# ─── COLLECT INSTALLED TOOL NAMES ─────────────────────────────────────────────
# Note: `volta list all` finds every tool Volta has registered, even if not
# installed. The loop logic correctly handles this by treating tools with no
# current version as a new installation.
TOOLS=$(volta list all --format=plain |
awk 'NF>=2 {print $2}' | sed 's/@[^@]*$//' | sort -u)

# ─── UPGRADE LOOP ─────────────────────────────────────────────────────────────
while IFS= read -r T; do
  [ "${T}" != "" ] || continue

  set +e
  contains "${T}" "${EXCLUDES}"
  _res=$?
  set -e
  if [ "${_res}" -eq 0 ]; then
    echo "⏩  Skipping ${T}"
    continue
  fi

  BEFORE=$(current_version "${T}")

  TARGET=$(install_target "${T}" "${BEFORE}")

  if [ "${DRY}" -eq 1 ]; then
    echo "would run: volta install --quiet ${TARGET}"
    continue
  fi

  if ! volta install --quiet "${TARGET}"; then
    echo "❌ Failed to install ${T}" >&2
    exit 1
  fi

  AFTER=$(current_version "${T}")

  if [ "${BEFORE}" = "" ]; then
    echo "➕ Installed ${T} @ ${AFTER}"
  elif [ "${BEFORE}" = "${AFTER}" ]; then
    echo "✅ ${T} already at ${AFTER}"
  else
    echo "⬆️  Upgraded ${T} ${BEFORE} → ${AFTER}"
  fi
done <<TOOLS_END
${TOOLS}
TOOLS_END

if [ "${DRY}" -eq 1 ]; then
  echo "✅ Dry run complete."
else
  _proj_dir=$(script_dir)
  _snapshot=$(volta list --format=plain | awk 'NF>=2 {print $2}')
  printf '%s\n' "${_snapshot}" > "${_proj_dir}/volta-packages.txt"
  echo "📸 Snapshot saved to ${_proj_dir}/volta-packages.txt"
  echo "🎉 All done!"
fi

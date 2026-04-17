#!/usr/bin/env bash
# volta-update-all.sh - update every Volta-managed tool
#
# Flags:
#   --dry-run         Show what would change, make no installs
#   --exclude a,b,c   Comma-separated list of tool names to skip
#   --install         Install the script to ~/.local/bin/volta-update-all
#   -h, --help        Display the help message
#
# Works with POSIX sh - no Bash-only features.

set -eu

IFS='
' # newline

# ─── CONFIG ────────────────────────────────────────────────────────────────────
NODE_CHANNEL=lts       # change to "latest" if you prefer cutting-edge Node
DEFAULT_CHANNEL=latest # all other tools follow this channel

# ─── HELPERS ──────────────────────────────────────────────────────────────────
usage() {
  sed -n '2,10p' "$0"
  exit 1
}

contains() { # $1 needle   $2 space-separated haystack
  _old_ifs=${IFS}
  IFS=' '
  for _x in $2; do
    IFS=${_old_ifs}
    # Remove leading/trailing spaces
    _x=$(echo "${_x}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ "${_x}" = "$1" ] && return 0
  done
  IFS=${_old_ifs}
  return 1
} || true

current_version() { # $1 tool-name → prints "22.16.0", or "" if absent
  # Extract the package string e.g. "@openai/codex@0.121.0"
  _pkg=$(volta list --format=plain | awk 'NF>=2 {print $2}' | grep "^$1@" | head -n 1)
  [ -z "${_pkg}" ] && return 0
  # Extract the version suffix (everything after the last @)
  echo "${_pkg}" | sed 's/.*@//'
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
      if [ $# -eq 0 ] || [ "$1" = "" ] || expr "$1" : '-\{1,2\}' > /dev/null; then
        echo "error: --exclude requires an argument." >&2
        usage
      fi
      EXCL=$1
      ;;
    -h | --help) usage ;;
    *)
      echo "unknown flag: $1" >&2
      usage
      ;;
  esac
  shift
done

if [ "${INSTALL}" -eq 1 ]; then
  _dest="${HOME}/.local/bin"
  mkdir -p "${_dest}"
  cp "$0" "${_dest}/volta-update-all"
  chmod +x "${_dest}/volta-update-all"
  echo "✅ Installed to ${_dest}/volta-update-all"
  echo "💡 Please ensure ${_dest} is in your PATH."
  exit 0
fi

command -v volta > /dev/null ||
  {
    echo "Volta not found in PATH" >&2
    exit 1
  }

PNPM_ENABLED=1
if [ "${VOLTA_FEATURE_PNPM:-0}" != 1 ]; then
  PNPM_ENABLED=0
  echo "⚠️  VOLTA_FEATURE_PNPM=1 not set; pnpm will be skipped."
fi

# ─── BUILD EXCLUDE LIST ───────────────────────────────────────────
EXCLUDES=""
OLD_IFS=${IFS}
IFS=','
for _x in ${EXCL}; do
  # Trim spaces and add to list if not empty
  _x=$(echo "${_x}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ "${_x}" != "" ] && EXCLUDES="${EXCLUDES} ${_x}"
done
IFS=${OLD_IFS}

[ "${PNPM_ENABLED}" -eq 1 ] || EXCLUDES="${EXCLUDES} pnpm"

# ─── COLLECT INSTALLED TOOL NAMES ─────────────────────────────────────────────
# Note: `volta list all` finds every tool Volta has registered, even if not
# installed. The loop logic correctly handles this by treating tools with no
# current version as a new installation.
TOOLS=$(volta list all --format=plain |
  awk 'NF>=2 {print $2}' | sed 's/@[^@]*$//' | sort -u)

# ─── UPGRADE LOOP ─────────────────────────────────────────────────────────────
for T in ${TOOLS}; do
  set +e
  contains "${T}" "${EXCLUDES}"
  _res=$?
  set -e
  if [ "${_res}" -eq 0 ]; then
    echo "⏩  Skipping ${T}"
    continue
  fi

  CHAN=${DEFAULT_CHANNEL}
  [ "${T}" = node ] && CHAN=${NODE_CHANNEL}

  BEFORE=$(current_version "${T}")

  if [ "${DRY}" -eq 1 ]; then
    echo "would run: volta install --quiet ${T}@${CHAN}"
    continue
  fi

  if ! volta install --quiet "${T}@${CHAN}"; then
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
done

if [ "${DRY}" -eq 1 ]; then
  echo "✅ Dry run complete."
else
  echo "🎉 All done!"
fi

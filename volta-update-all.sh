#!/bin/sh
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

# ─── HELPERS ──────────────────────────────────────────────────────────────────
usage() {
  sed -n '2,10p' "$0"
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
set +e
EXCLUDES=$(printf '%s\n' "${EXCL}" |
  tr ',' '\n' |
  while IFS= read -r _exclude_item; do
    _exclude_item=$(printf '%s\n' "${_exclude_item}" | trim)
    [ "${_exclude_item}" != "" ] && printf '%s\n' "${_exclude_item}"
done)
set -e

if [ "${PNPM_ENABLED}" -ne 1 ]; then
  EXCLUDES=$(printf '%s\n%s\n' "${EXCLUDES}" pnpm)
fi

# ─── COLLECT INSTALLED TOOL NAMES ─────────────────────────────────────────────
# Note: `volta list all` finds every tool Volta has registered, even if not
# installed. The loop logic correctly handles this by treating tools with no
# current version as a new installation.
TOOLS=$(volta list all --format=plain |
awk 'NF>=2 {print $2}' | sed 's/@[^@]*$//' | sort -u)

# ─── UPGRADE LOOP ─────────────────────────────────────────────────────────────
printf '%s\n' "${TOOLS}" | while IFS= read -r T; do
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
done

if [ "${DRY}" -eq 1 ]; then
  echo "✅ Dry run complete."
else
  echo "🎉 All done!"
fi

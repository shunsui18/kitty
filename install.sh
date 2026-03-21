#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║   yozakura — kitty colour theme installer                    ║
# ║   Usage: bash install.sh [--theme <flavor>]                  ║
# ║   Flavors: yoru (default) · hiru                             ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── ANSI palette ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()    { echo -e "${CYAN}  →${RESET}  $*"       >&2; }
success() { echo -e "${GREEN}  ✓${RESET}  $*"     >&2; }
warn()    { echo -e "${YELLOW}  ⚠${RESET}  $*"    >&2; }
die()     { echo -e "${RED}  ✗  $*${RESET}"       >&2; exit 1; }
section() { echo -e "\n${BOLD}${MAGENTA}$*${RESET}" >&2; }

# ── Resolve repo root (wherever this script lives) ───────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse CLI flags ───────────────────────────────────────────────────────────
FLAVOR="yoru"

while [[ $# -gt 0 ]]; do
  case $1 in
    --theme)
      [[ -n "${2:-}" ]] || die "--theme requires a flavor argument (e.g. yoru, hiru)"
      FLAVOR="$2"; shift 2 ;;
    --theme=*)
      FLAVOR="${1#*=}"; shift ;;
    -h|--help)
      echo "Usage: bash install.sh [--theme <flavor>]"
      echo "       Available flavors: $(
        ls "${SCRIPT_DIR}"/yozakura-*.conf 2>/dev/null \
          | sed 's/.*yozakura-//;s/\.conf//' \
          | tr '\n' ' '
      )"
      exit 0 ;;
    *)
      die "Unknown option: $1 — run with --help for usage" ;;
  esac
done

# ── Validate theme file exists in repo ───────────────────────────────────────
THEME_FILE="yozakura-${FLAVOR}.conf"
THEME_SRC="${SCRIPT_DIR}/${THEME_FILE}"

if [[ ! -f "$THEME_SRC" ]]; then
  AVAILABLE="$(
    ls "${SCRIPT_DIR}"/yozakura-*.conf 2>/dev/null \
      | sed 's/.*yozakura-//;s/\.conf//' \
      | tr '\n' ' '
  )"
  die "Theme '${FLAVOR}' not found.\n       Available flavors: ${AVAILABLE:-<none>}"
fi

# ── Destination paths ─────────────────────────────────────────────────────────
KITTY_CFG_DIR="${HOME}/.config/kitty"
KITTY_CONF="${KITTY_CFG_DIR}/kitty.conf"
INCLUDE_LINE="include ${THEME_FILE}"

# ── Step 1 — Create directories ───────────────────────────────────────────────
section "[ 1/3 ]  Preparing directories"
mkdir -p "$KITTY_CFG_DIR"
success "Config dir ready: ${DIM}${KITTY_CFG_DIR}${RESET}"

# ── Step 2 — Copy all theme files ─────────────────────────────────────────────
section "[ 2/3 ]  Installing theme files"
COPIED=0
for src in "${SCRIPT_DIR}"/yozakura-*.conf; do
  [[ -f "$src" ]] || continue
  dest="${KITTY_CFG_DIR}/$(basename "$src")"
  cp "$src" "$dest"
  if [[ "$(basename "$src")" == "$THEME_FILE" ]]; then
    success "Installed ${BOLD}$(basename "$src")${RESET}${GREEN} ← active${RESET}"
  else
    success "Installed $(basename "$src")"
  fi
  COPIED=$((COPIED + 1))
done
[[ $COPIED -gt 0 ]] || die "No yozakura-*.conf theme files found in ${SCRIPT_DIR}"

# ── Step 3 — Patch kitty.conf ─────────────────────────────────────────────────
section "[ 3/3 ]  Patching kitty.conf"

# Create kitty.conf if it doesn't exist
if [[ ! -f "$KITTY_CONF" ]]; then
  touch "$KITTY_CONF"
  warn "kitty.conf not found — created empty file: ${DIM}${KITTY_CONF}${RESET}"
fi

# ── Collect all colour-property key names from every theme file ───────────────
declare -A COLOR_KEY_MAP
for f in "${SCRIPT_DIR}"/yozakura-*.conf; do
  [[ -f "$f" ]] || continue
  while IFS= read -r line; do
    # Extract key from non-comment, non-blank lines (key followed by whitespace)
    if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]] ]]; then
      COLOR_KEY_MAP["${BASH_REMATCH[1]}"]="1"
    fi
  done < "$f"
done

# ── Process kitty.conf line-by-line into a temp file ─────────────────────────
TMP_CONF="$(mktemp)"
INCLUDE_FOUND=0
COMMENTED=0

while IFS= read -r line || [[ -n "$line" ]]; do

  # ── (a) include directives ──────────────────────────────────────────────────
  if [[ "$line" =~ ^[[:space:]]*include[[:space:]] ]]; then
    if [[ "$INCLUDE_FOUND" -eq 0 ]]; then
      # First include line — replace with chosen theme
      if [[ "$line" != "$INCLUDE_LINE" ]]; then
        info "Replaced:  ${DIM}${line}${RESET}  →  ${INCLUDE_LINE}"
      fi
      echo "$INCLUDE_LINE"
      INCLUDE_FOUND=1
    else
      # Subsequent include lines — comment out to avoid conflicts
      echo "# ${line}"
      warn "Commented duplicate include: ${DIM}${line}${RESET}"
    fi
    continue
  fi

  # ── (b) inline colour properties ────────────────────────────────────────────
  # Match active (uncommented) lines whose first token is a known colour key
  if [[ "$line" =~ ^([[:space:]]*)([a-zA-Z_][a-zA-Z0-9_]*)([[:space:]].*)$ ]]; then
    key="${BASH_REMATCH[2]}"
    if [[ -n "${COLOR_KEY_MAP[$key]+_}" ]]; then
      echo "# ${line}"
      COMMENTED=$((COMMENTED + 1))
      continue
    fi
  fi

  echo "$line"

done < "$KITTY_CONF" > "$TMP_CONF"

# ── Append include if it was never found ──────────────────────────────────────
if [[ "$INCLUDE_FOUND" -eq 0 ]]; then
  {
    echo ""
    echo "# colour scheme"
    echo "$INCLUDE_LINE"
  } >> "$TMP_CONF"
  info "Appended:  ${INCLUDE_LINE}"
fi

mv "$TMP_CONF" "$KITTY_CONF"

success "kitty.conf updated: ${DIM}${KITTY_CONF}${RESET}"

if [[ "$COMMENTED" -gt 0 ]]; then
  warn "${COMMENTED} inline colour properties commented out (superseded by theme file)"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo "" >&2
echo -e "${BOLD}${GREEN}  ✦  yozakura / ${FLAVOR} installed successfully!${RESET}" >&2
echo -e "${DIM}      Config : ${KITTY_CONF}" >&2
echo -e "      Theme  : ${KITTY_CFG_DIR}/${THEME_FILE}${RESET}" >&2
echo "" >&2
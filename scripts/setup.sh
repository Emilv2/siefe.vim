#!/usr/bin/env bash
# scripts/setup.sh — Install siefe Rust binaries.
#
# Strategy (in order):
#   1. If cargo is available, build from source (always correct for the local arch).
#   2. Otherwise, download the pre-built tarball for the current platform from the
#      latest GitHub release.
#
# Environment variables:
#   SIEFE_FORCE=1   — (re-)install even if all binaries are already present
#   SIEFE_NOCOLOR=1 — disable ANSI colour in output

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$PLUGIN_DIR/bin"
REPO="Emilv2/siefe.vim"
BINARIES=(rg2fzf shada2fzf diffgrep pickaxe-diff)

# ── Helpers ───────────────────────────────────────────────────────────────────

_nc=""
_bold=""
_red=""
_green=""
_yellow=""
if [[ "${SIEFE_NOCOLOR:-}" != "1" ]] && [[ -t 1 ]]; then
  _nc="\033[0m"
  _bold="\033[1m"
  _red="\033[31m"
  _green="\033[32m"
  _yellow="\033[33m"
fi

info()    { echo -e "${_bold}siefe:${_nc} $*"; }
success() { echo -e "${_green}${_bold}siefe:${_nc} $*"; }
warn()    { echo -e "${_yellow}${_bold}siefe:${_nc} $*" >&2; }
error()   { echo -e "${_red}${_bold}siefe:${_nc} $*" >&2; exit 1; }

all_present() {
  for b in "${BINARIES[@]}"; do
    [[ -x "$BIN_DIR/$b" ]] || return 1
  done
  return 0
}

# ── Already installed? ────────────────────────────────────────────────────────

if all_present && [[ "${SIEFE_FORCE:-}" != "1" ]]; then
  success "all binaries already present in $BIN_DIR — nothing to do."
  exit 0
fi

mkdir -p "$BIN_DIR"

# ── Strategy 1: build from source ────────────────────────────────────────────

if command -v cargo >/dev/null 2>&1; then
  info "cargo found — building binaries from source..."
  cd "$PLUGIN_DIR"
  cargo build --release
  for b in "${BINARIES[@]}"; do
    # pickaxe_diff binary is named pickaxe-diff on disk
    src="target/release/${b}"
    install -m 755 "$src" "$BIN_DIR/$b"
  done
  success "binaries built and installed to $BIN_DIR"
  exit 0
fi

# ── Strategy 2: download from GitHub releases ─────────────────────────────────

warn "cargo not found — downloading pre-built binaries from GitHub..."

# Detect platform
OS="$(uname -s)"
ARCH="$(uname -m)"
case "${OS}-${ARCH}" in
  Linux-x86_64)   TARGET="x86_64-unknown-linux-gnu" ;;
  Linux-aarch64)  TARGET="aarch64-unknown-linux-gnu" ;;
  Darwin-x86_64)  TARGET="x86_64-apple-darwin" ;;
  Darwin-arm64)   TARGET="aarch64-apple-darwin" ;;
  *) error "unsupported platform ${OS}-${ARCH}; please build from source with cargo" ;;
esac

# Pick download tool
if command -v curl >/dev/null 2>&1; then
  DL="curl"
elif command -v wget >/dev/null 2>&1; then
  DL="wget"
else
  error "neither curl nor wget found; please install one and retry"
fi

# Resolve latest release tag
info "resolving latest release tag from github.com/$REPO..."
API_URL="https://api.github.com/repos/${REPO}/releases/latest"
if [[ "$DL" == "curl" ]]; then
  LATEST_JSON="$(curl -fsSL "$API_URL")"
else
  LATEST_JSON="$(wget -qO- "$API_URL")"
fi
LATEST="$(echo "$LATEST_JSON" | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
[[ -n "$LATEST" ]] || error "could not determine latest release tag (is the repo public?)"

# Download and extract
ARCHIVE="siefe-binaries-${TARGET}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${LATEST}/${ARCHIVE}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

info "downloading ${ARCHIVE} from release ${LATEST}..."
if [[ "$DL" == "curl" ]]; then
  curl -fsSL "$URL" -o "$TMP/$ARCHIVE"
else
  wget -q "$URL" -O "$TMP/$ARCHIVE"
fi

tar -xzf "$TMP/$ARCHIVE" -C "$TMP"

for b in "${BINARIES[@]}"; do
  install -m 755 "$TMP/$b" "$BIN_DIR/$b"
done

success "binaries installed from release ${LATEST} into $BIN_DIR"

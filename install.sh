#!/bin/bash
# Installs Markdown Editor (Quick Look extension) by building it from source.
#   curl -fsSL https://raw.githubusercontent.com/LauLamanApps/markdown-preview/main/install.sh | bash
# Building locally means no Gatekeeper warnings and no Apple Developer account needed.
set -euo pipefail

REPO="LauLamanApps/markdown-preview"
REF="${MARKDOWN_PREVIEW_REF:-main}"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "This only works on macOS." >&2; exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
    echo "The Xcode Command Line Tools are required. Starting their installer…"
    xcode-select --install || true
    echo "Run this script again once the installation has finished."
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "→ downloading $REPO@$REF"
curl -fsSL "https://github.com/$REPO/archive/$REF.tar.gz" | tar -xz -C "$tmp" --strip-components 1

INSTALL_DIR="${INSTALL_DIR:-/Applications}"
if [[ ! -w "$INSTALL_DIR" ]]; then INSTALL_DIR="$HOME/Applications"; fi

make -C "$tmp" install INSTALL_DIR="$INSTALL_DIR"

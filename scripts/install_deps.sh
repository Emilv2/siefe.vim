#!/bin/bash
set -euo pipefail

echo "=== Installing siefe.vim dependencies for Red Hat / Fedora ==="

# 1. Enable EPEL (needed for some packages on RHEL)
echo "[1/5] Configuring repositories..."
sudo dnf install -y epel-release

# 2. Core dependencies
echo "[2/5] Installing packages..."
sudo dnf install -y fzf ripgrep fd-find

# 3. Rust toolchain (for building Rust helper binaries)
if ! command -v cargo &>/dev/null; then
  echo "[3/5] Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
else
  echo "[3/5] Rust already installed"
fi

# 4. fzf-lua (Neovim plugin dependency — clone for e2e tests)
if [ ! -d /tmp/fzf-lua ]; then
  echo "[4/5] Cloning fzf-lua..."
  git clone --depth=1 https://github.com/ibhagwan/fzf-lua /tmp/fzf-lua
else
  echo "[4/5] fzf-lua already present"
fi

# 5. Build Rust helper binaries
echo "[5/5] Building Rust helper binaries..."
cd "$(dirname "$0")/.."
make build

echo "=== Done ==="

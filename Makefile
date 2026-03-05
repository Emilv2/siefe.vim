.PHONY: build test test-lua test-plugin test-rust test-integration test-neovim test-e2e \
        coverage coverage-rust coverage-lua lint lint-lua lint-rust fmt fmt-lua fmt-rust

NVIM      ?= nvim
CARGO     ?= cargo
LUACHECK  ?= luacheck
STYLUA    ?= stylua

# ── Build ─────────────────────────────────────────────────────────────────────

build:
	$(CARGO) build --release
	cp target/release/diffgrep bin/diffgrep
	cp target/release/pickaxe-diff bin/pickaxe-diff

# ── Tests ─────────────────────────────────────────────────────────────────────

test-rust:
	$(CARGO) test

test-lua:
	$(NVIM) --headless -u NONE -l test/test_config.lua
	$(NVIM) --headless -u NONE -l test/test_utils.lua
	$(NVIM) --headless -u NONE -l test/test_rg.lua
	$(NVIM) --headless -u NONE -l test/test_history.lua

# Plugin load test: sources plugin/siefe.lua the same way Neovim does on startup.
# Catches load-time bugs (e.g. config.options.map_keys nil-index) invisible to
# module-level require() tests.
test-plugin:
	$(NVIM) --headless -u NONE -l test/test_plugin.lua

# Neovim integration tests: exercise functions that require real Neovim state
# (buffers, cursor positions, registers, quickfix, feedkeys).
test-neovim:
	$(NVIM) --headless -u NONE -l test/test_neovim.lua
	$(NVIM) --headless -u NONE -l test/test_picker_actions.lua

# End-to-end tests: launch real fzf via fzf-lua, interact via chansend(), assert side-effects.
# Requires fzf binary and fzf-lua in runtimepath (set FZF_LUA_PATH, default /tmp/fzf-lua).
# Clone: git clone --depth=1 https://github.com/ibhagwan/fzf-lua /tmp/fzf-lua
FZF_LUA_PATH ?= /tmp/fzf-lua
test-e2e:
	FZF_LUA_PATH=$(FZF_LUA_PATH) $(NVIM) --headless -u NONE -l test/test_e2e.lua
	FZF_LUA_PATH=$(FZF_LUA_PATH) $(NVIM) --headless -u NONE -l test/test_e2e_gitlog.lua

# Integration tests call real external binaries; requires `make build` first.
test-integration: build
	$(NVIM) --headless -u NONE -l test/test_integration.lua

test: test-rust test-lua test-plugin test-neovim

# ── Coverage ──────────────────────────────────────────────────────────────────

# Rust: line/region/function coverage via cargo-llvm-cov (requires `rustup component add llvm-tools`
# and `cargo install cargo-llvm-cov`). Produces an HTML report in coverage/rust/.
coverage-rust:
	$(CARGO) llvm-cov --html --output-dir coverage/rust
	@echo "Rust coverage report: coverage/rust/index.html"

# Rust: summary to stdout (no files written)
coverage-rust-summary:
	$(CARGO) llvm-cov --summary-only

# Lua: line coverage via luacov (requires `luarocks install luacov`).
# Each test file is run with -lluacov; luacov then aggregates the stats file
# and writes a text report to luacov.report.out.
coverage-lua:
	$(NVIM) --headless -u NONE -e "lua require('luacov')" -l test/test_config.lua  2>/dev/null || \
	$(NVIM) --headless -u NONE -l test/test_config.lua
	LUACOV_RUNNING=1 $(NVIM) --headless -u NONE \
	  -c "lua package.path = package.path .. ';/usr/local/share/lua/5.1/?.lua'" \
	  -c "lua require('luacov')" \
	  -l test/test_config.lua  || true
	LUACOV_RUNNING=1 $(NVIM) --headless -u NONE \
	  -c "lua package.path = package.path .. ';/usr/local/share/lua/5.1/?.lua'" \
	  -c "lua require('luacov')" \
	  -l test/test_utils.lua   || true
	LUACOV_RUNNING=1 $(NVIM) --headless -u NONE \
	  -c "lua package.path = package.path .. ';/usr/local/share/lua/5.1/?.lua'" \
	  -c "lua require('luacov')" \
	  -l test/test_rg.lua      || true
	LUACOV_RUNNING=1 $(NVIM) --headless -u NONE \
	  -c "lua package.path = package.path .. ';/usr/local/share/lua/5.1/?.lua'" \
	  -c "lua require('luacov')" \
	  -l test/test_history.lua || true
	luacov && cat luacov.report.out

coverage: coverage-rust-summary coverage-lua

# ── Lint ──────────────────────────────────────────────────────────────────────

lint-lua:
	$(LUACHECK) lua/ test/ plugin/siefe.lua
	$(STYLUA) --check lua/ test/ plugin/siefe.lua

lint-rust:
	$(CARGO) clippy -- -D warnings
	$(CARGO) fmt --check

lint: lint-lua lint-rust

# ── Format ────────────────────────────────────────────────────────────────────

fmt-lua:
	$(STYLUA) lua/ test/ plugin/siefe.lua

fmt-rust:
	$(CARGO) fmt

fmt: fmt-lua fmt-rust

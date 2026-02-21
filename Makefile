.PHONY: build test test-lua test-rust test-integration

NVIM  ?= nvim
CARGO ?= cargo

build:
	$(CARGO) build --release
	cp target/release/rg2fzf bin/rg2fzf
	cp target/release/shada2fzf bin/shada2fzf
	cp target/release/diffgrep bin/diffgrep
	cp target/release/pickaxe-diff bin/pickaxe-diff

test-rust:
	$(CARGO) test

test-lua:
	$(NVIM) --headless -u NONE -l test/test_config.lua
	$(NVIM) --headless -u NONE -l test/test_utils.lua
	$(NVIM) --headless -u NONE -l test/test_rg.lua
	$(NVIM) --headless -u NONE -l test/test_history.lua

# Integration tests call real external binaries; requires `make build` first.
test-integration: build
	$(NVIM) --headless -u NONE -l test/test_integration.lua

test: test-rust test-lua

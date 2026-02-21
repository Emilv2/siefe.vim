.PHONY: build test test-lua test-rust

NVIM  ?= nvim
CARGO ?= cargo

build:
	$(CARGO) build --release
	cp target/release/rg2fzf bin/rg2fzf

test-rust:
	$(CARGO) test

test-lua:
	$(NVIM) --headless -u NONE -l test/test_config.lua
	$(NVIM) --headless -u NONE -l test/test_utils.lua

test: test-rust test-lua

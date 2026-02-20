.PHONY: test

NVIM ?= nvim

test:
	$(NVIM) --headless -u NONE -l test/test_config.lua
	$(NVIM) --headless -u NONE -l test/test_utils.lua

.PHONY: help check test docker-test
.DEFAULT_GOAL := help

# Read here, before any include, so it names this file even when MAKEFILES loads others.
THIS_MAKEFILE := $(lastword $(MAKEFILE_LIST))
SHELL_FILES := governor.sh test

# The status tag, coloured only on a terminal and never with NO_COLOR set.
ifeq ($(NO_COLOR)$(if $(MAKE_TERMOUT),,plain),)
esc := $(shell printf '\033')
ok := $(esc)[90m[$(esc)[38;5;154m  OK  $(esc)[90m]$(esc)[0m
else
ok := [  OK  ]
endif

help: ## List the targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf " %-11s %s\n", $$1, $$2}' $(THIS_MAKEFILE)

check: ## Lint the scripts, compose file and workflows (shellcheck, shfmt, compose, actionlint)
	@shellcheck -- $(SHELL_FILES)
	@echo ' $(ok) shellcheck: $(words $(SHELL_FILES)) files'
	@shfmt -d -- $(SHELL_FILES)
	@echo ' $(ok) shfmt: $(words $(SHELL_FILES)) files'
	@docker compose config -q
	@echo ' $(ok) docker compose config: docker-compose.yml'
	@actionlint
	@echo ' $(ok) actionlint: $(words $(wildcard .github/workflows/*.yml)) workflows'

test: ## Run governor.sh against fake sysfs files
	@bash test

# The image governor.sh runs in, read from docker-compose.yml so the two stay the same.
IMAGE := $(shell awk '$$1 == "image:" {print $$2; exit}' docker-compose.yml)

docker-test: ## Run the tests in the compose image, so governor.sh runs under BusyBox sh
	@docker run --rm -v "$(CURDIR):/src:ro" -w /src $(IMAGE) \
		sh -c 'apk add --no-cache --quiet bash >/dev/null && bash test'

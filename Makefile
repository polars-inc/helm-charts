.PHONY: schema docs all clean
.DEFAULT_GOAL := all

.ONESHELL:

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

# Silence by default; enable with: make V=1 <target>
V ?= 0
ifeq ($(V),0)
.SILENT:
endif

DEFINITIONS_VERSION := 1.34.3
DEFINITIONS_FILE := _definitions-v$(DEFINITIONS_VERSION).json
DEFINITIONS_LINK := _definitions.json
CHARTS_DIR := charts

all: schema docs

schema:
	if [[ ! -f "$(DEFINITIONS_FILE)" ]]; then \
		echo "Downloading Kubernetes definitions v$(DEFINITIONS_VERSION)..."; \
		curl -s "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v$(DEFINITIONS_VERSION)/_definitions.json" > "$(DEFINITIONS_FILE)"; \
		jq 'del(.. | .format?)' "$(DEFINITIONS_FILE)" | sponge "$(DEFINITIONS_FILE)"; \
	fi
	ln -sf "$(DEFINITIONS_FILE)" "$(DEFINITIONS_LINK)"
	helm schema --chart-search-root="$(CHARTS_DIR)" --helm-docs-compatibility-mode --log-level=debug --skip-auto-generation required
	for chart in "$(CHARTS_DIR)"/*; do \
		echo "Updating $$chart"; \
		jq '. + input' "$(DEFINITIONS_LINK)" "$$chart/values.schema.json" | sponge "$$chart/values.schema.json"; \
		sed -i 's|../../_definitions.json||g' "$$chart/values.schema.json"; \
	done

docs:
	helm-docs --chart-search-root="$(CHARTS_DIR)" --sort-values-order=file --ignore-non-descriptions

clean:
	rm -f "$(DEFINITIONS_LINK)" _definitions-v*.json

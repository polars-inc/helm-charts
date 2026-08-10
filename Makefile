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

# Space separated, e.g. IGNORE_CHARTS := polars-k8s-operator license-server
IGNORE_CHARTS := polars-k8s-operator

CHARTS := $(filter-out $(addprefix $(CHARTS_DIR)/,$(IGNORE_CHARTS)), \
	$(patsubst %/,%,$(wildcard $(CHARTS_DIR)/*/)))

all: schema docs fmt

schema:
	if [[ ! -f "$(DEFINITIONS_FILE)" ]]; then \
		echo "Downloading Kubernetes definitions v$(DEFINITIONS_VERSION)..."; \
		curl -s "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v$(DEFINITIONS_VERSION)/_definitions.json" > "$(DEFINITIONS_FILE)"; \
		jq 'del(.. | .format?)' "$(DEFINITIONS_FILE)" | sponge "$(DEFINITIONS_FILE)"; \
	fi
	ln -sf "$(DEFINITIONS_FILE)" "$(DEFINITIONS_LINK)"
	for chart in $(CHARTS); do \
		echo "Updating $$chart"; \
		helm schema --chart-search-root="$$chart" --helm-docs-compatibility-mode --log-level=debug --skip-auto-generation required --no-dependencies; \
		jq '. + input' "$(DEFINITIONS_LINK)" "$$chart/values.schema.json" | sponge "$$chart/values.schema.json"; \
		sed -i 's|../../_definitions.json||g' "$$chart/values.schema.json"; \
	done

docs:
	for chart in $(CHARTS); do \
		echo "Documenting $$chart"; \
		helm-docs --chart-search-root="$$chart" --sort-values-order=file --ignore-non-descriptions; \
	done

fmt:
	for chart in $(CHARTS); do \
		echo "Formatting $$chart"; \
		helmfmt "$$chart" --disable-indent=tpl; \
	done

clean:
	rm -f "$(DEFINITIONS_LINK)" _definitions-v*.json

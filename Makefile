.PHONY: all schema docs fmt clean
.DEFAULT_GOAL := all

.ONESHELL:

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

# Silence by default; enable with: make V=1 <target>
V ?= 0
ifeq ($(V),0)
.SILENT:
endif

K8S_VERSION := v1.34.3
SCHEMA_DRAFT := 7
CHARTS_DIR := charts

HELM_SCHEMA ?= helm schema

# Space separated, e.g. IGNORE_CHARTS := polars-k8s-operator license-server
IGNORE_CHARTS := polars-k8s-operator

CHARTS := $(filter-out $(addprefix $(CHARTS_DIR)/,$(IGNORE_CHARTS)), \
	$(patsubst %/,%,$(wildcard $(CHARTS_DIR)/*/)))

all: schema docs fmt

# Recipes use "\" continuations: .ONESHELL needs make >= 3.82, macOS ships 3.81.
schema:
	for chart in $(CHARTS); do \
		echo "Updating $$chart"; \
		$(HELM_SCHEMA) \
			--values="$$chart/values.yaml" \
			--output="$$chart/values.schema.json" \
			--draft=$(SCHEMA_DRAFT) \
			--bundle \
			--bundle-without-id \
			--use-helm-docs \
			--no-additional-properties \
			--k8s-schema-version=$(K8S_VERSION); \
		if grep -q '"\$$ref": *"[^#]' "$$chart/values.schema.json"; then \
			echo "ERROR: $$chart/values.schema.json contains an unbundled external \$$ref" >&2; \
			exit 1; \
		fi; \
		if [ "$$(jq '[.. | objects | select(has("allOf")) | .allOf \
			| select(any(.[]; has("$$ref"))) | select(any(.[]; has("properties")))] \
			| length' "$$chart/values.schema.json")" != 0 ]; then \
			echo "ERROR: $$chart/values.schema.json narrows a \$$ref with an inferred" \
				"schema. Add '# @schema hidden' to that key's children in values.yaml." >&2; \
			exit 1; \
		fi; \
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
	rm -f _definitions.json _definitions-v*.json

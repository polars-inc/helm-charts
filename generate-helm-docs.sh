#!/usr/bin/env bash

set -e

helm-docs --chart-search-root=charts --sort-values-order=file --ignore-non-descriptions

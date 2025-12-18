#!/usr/bin/env bash

set -e

DEFINITIONS_VERSION=1.34.3

if [ ! -f _definitions-v${DEFINITIONS_VERSION}.json ]; then
  curl -s https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v${DEFINITIONS_VERSION}/_definitions.json > _definitions-v${DEFINITIONS_VERSION}.json

  jq 'del(.. | .format?)' _definitions-v${DEFINITIONS_VERSION}.json | sponge _definitions-v${DEFINITIONS_VERSION}.json
fi

ln -sf _definitions-v${DEFINITIONS_VERSION}.json _definitions.json

helm schema --chart-search-root=charts --helm-docs-compatibility-mode --log-level=debug --skip-auto-generation required

for CHART in charts/*; do
  echo "Updating $CHART"

  jq '. + input' _definitions.json $CHART/values.schema.json | sponge $CHART/values.schema.json

  sed -i "s|../../_definitions.json#||g" $CHART/values.schema.json

done


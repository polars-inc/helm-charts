# Polars License Server

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

Polars License Server

**Homepage:** <https://cloud.pola.rs>

Validates Polars licenses inside your own network, for clusters that don't have
access to the Polars cloud. Run one instance and point your Polars deployments at
it.

## Prerequisites

- Kubernetes 1.22+ (uses the `ReadWriteOncePod` PVC access mode)
- Helm 3.x
- A default StorageClass, or set `report.storageClass`
- Two credentials from Polars:
  - a **license file** (JSON)
  - a **TLS bundle** (PEM: server cert + key + CA) used to serve HTTPS

## Install

Provide the license and TLS bundle inline with `--set-file`. The chart creates
the backing Secrets from these values:

```console
$ helm upgrade --install license-server . \
    --namespace polars --create-namespace \
    --set-file license.content=license.json \
    --set-file tlsBundle.content=bundle.pem
```

### Using pre-existing Secrets

Leave `license.content` / `tlsBundle.content` empty and reference Secrets you manage
out of band (recommended for GitOps — keeps secrets out of Helm values):

```console
$ kubectl -n polars create secret generic license-server-license \
    --from-file=license.json=license.json
$ kubectl -n polars create secret generic license-server-tls-bundle \
    --from-file=bundle.pem=bundle.pem
$ helm upgrade --install license-server . --namespace polars
```

## Connecting a Polars cluster

Point the [`polars`](../polars) chart's scheduler at the server:

```yaml
license:
  licenseServer:
    enabled: true
    uri: "https://license-server.polars.svc.cluster.local:50051"
```

## Metrics

The server exposes Prometheus metrics at `/metrics` on the HTTP port
(`service.httpPort`, default `8081`). Point your scraper at:

```
http://license-server.polars.svc.cluster.local:8081/metrics
```

The same port also serves health checks at `/healthz` and `/readyz`.

If you run the Prometheus Operator, set `serviceMonitor.enabled=true` to scrape
`/metrics` automatically.

## Notes

- Run a single instance — don't scale it up.
- Its data is kept even if you uninstall the chart, so licenses stay valid across
  upgrades. To reclaim space, delete only already-submitted usage reports from the
  volume — never the volume or its state, which would reset the server.
- Updating the license or TLS bundle restarts the server automatically.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Polars | <developers@polars.tech> | <https://github.com/polars-inc> |

## Source Code

* <https://github.com/polars-inc/helm-charts>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| name | string | `"license-server"` | Base name for all resources. Also the Service DNS name clients dial, so keep it stable (referenced by the polars chart `license.licenseServer.uri`). |
| report.mountPath | string | `"/data"` | Mount path for the state DB + report ledger |
| report.storageClass | string | `nil` | StorageClass for the report PVC. Uses the cluster default when empty. |
| report.size | string | `"1Gi"` | Size of the report PVC |
| license.secretName | string | `"license-server-license"` | Name of the Secret holding the license JSON |
| license.key | string | `"license.json"` | Key within the license Secret |
| license.mountPath | string | `"/config/license-server-license.json"` | Path the license file is mounted at inside the container |
| license.content | string | `""` | Inline license JSON. When set, the chart creates the license Secret; leave empty to reference a pre-existing Secret (`license.secretName`). Prefer `--set-file` over committing this. |
| tlsBundle.secretName | string | `"license-server-tls-bundle"` | Name of the Secret holding the TLS bundle (PEM: cert + key + CA) |
| tlsBundle.key | string | `"bundle.pem"` | Key within the TLS bundle Secret |
| tlsBundle.mountPath | string | `"/config/license-server-bundle.pem"` | Path the TLS bundle is mounted at inside the container |
| tlsBundle.content | string | `""` | Inline TLS bundle PEM. When set, the chart creates the TLS Secret; leave empty to reference a pre-existing Secret (`tlsBundle.secretName`). Prefer `--set-file` over committing this. |
| image.repository | string | `"polarscloud/license-server"` | Image repository |
| image.tag | string | `""` | Image tag. Defaults to the chart appVersion when left empty. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| imagePullSecrets | list | `[]` | Secrets for pulling the image from a private registry |
| resources.requests.cpu | string | `"100m"` | CPU request |
| resources.requests.memory | string | `"128Mi"` | Memory request |
| resources.limits.memory | string | `"128Mi"` | Memory limit (no CPU limit, to avoid throttling) |
| service.port | int | `50051` | gRPC/HTTPS port the server listens on |
| service.httpPort | int | `8081` | HTTP port serving health probes (`/healthz`, `/readyz`) and Prometheus metrics (`/metrics`) |
| serviceMonitor | object | `{"enabled":false,"interval":"30s"}` | ServiceMonitor for scraping /metrics. Requires the Prometheus Operator CRDs. |
| serviceMonitor.enabled | bool | `false` | Create a ServiceMonitor for the Prometheus Operator |
| serviceMonitor.interval | string | `"30s"` | Scrape interval |
| serviceAccount.create | bool | `true` | Create a dedicated ServiceAccount |
| serviceAccount.name | string | `""` | ServiceAccount name. Defaults to `name` when empty. |
| serviceAccount.annotations | object | `{}` | Annotations to add to the ServiceAccount |
| podSecurityContext | object | `{"fsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context. Hardened defaults; the server needs no elevated privileges. |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}` | Container-level security context |
| podAnnotations | object | `{}` | Extra annotations for the pod |
| podLabels | object | `{}` | Extra labels for the pod |
| nodeSelector | object | `{}` | Node selector for pod scheduling |
| tolerations | list | `[]` | Tolerations for pod scheduling |
| affinity | object | `{}` | Affinity rules for pod scheduling |
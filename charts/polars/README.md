# Polars on-premises: Extremely fast distributed Query Engine for DataFrames

![Version: 1.3.0](https://img.shields.io/badge/Version-1.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 20260202](https://img.shields.io/badge/AppVersion-20260202-informational?style=flat-square)

Distributed query execution engine for Polars

**Homepage:** <https://pola.rs>

## Access to Polars on-premises artifacts

First of all, make sure to obtain a license for Polars on-premises by [signing up here](https://w0lzyfh2w8o.typeform.com/to/zuoDgoMv).
You will receive an access key for our private Docker registry as well as a license for running Polars on-premises.
Refer to the official Kubernetes documentation on [how to create a secret for pulling images from a private registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/).

## Quick Start

To install the chart, ensure you have created an image pull secret as described above and ensure that a secret containing the license file exists.

```console
$ kubectl create secret docker-registry dockerhub-secret-name --docker-username=polarscustomer --docker-password=dckr_pat
$ kubectl create secret generic polars-secret-name --from-file=license.json=license.json
$ helm repo add polars-inc https://polars-inc.github.io/helm-charts
$ helm upgrade --install polars polars-inc/polars \
    --set imagePullSecrets[0].name=dockerhub-secret-name \
    --set license.secretName=polars-secret-name \
    --set license.secretProperty=license.json
$ kubectl port-forward svc/polars-scheduler 5051:5051
$ kubectl port-forward svc/polars-observatory 3001:3001
```

Then connect to the cluster from Python as follows:

```python
import polars_cloud as pc
import polars as pl

# Directly connect to the cluster
ctx = pc.ClusterContext(compute_address="127.0.0.1", compute_port=5051, insecure=True)
query = (
    pl.LazyFrame()
    .with_columns(a=pl.arange(0, 100000000).sum())
    .remote(ctx)
    .distributed()
    .execute()
)
print(query.await_result())
```

You can see your query progress and node metrics by accessing the observatory service at `http://localhost:3001`.

### Helm Tests

You can instead also run the provided helm tests by running `helm test polars`. The chart contains a default list of images in `.Values.tests.images` that correspond to the supported polars-cloud client versions. The tests currently always run using the runtime image specified in `.Values.runtime.composed.runtime` since the client and compute cluster need to run the same version.

## Configuration

Running Polars on-premises in a production environment requires some configuration. The most important aspects are described below.

### Runtime

Polars on-premises consists of a single scheduler and multiple workers. Both components are contained in a single binary. While the scheduler can run without any system-level dependencies, the worker node needs the following:

* Python runtime (e.g. any version)
* Polars (i.e. pip wheel)
* Additional python requirements (e.g. numpy, pyarrow)

If your Kubernetes cluster has internet access, we support installing these all at worker boot. For example, you can use the following configuration:

```yaml
runtime:
  prebuilt:
    enabled: false

  composed:
    enabled: true

    dist:
      repository: "polarscloud/polars-on-premises"
      tag: ""
      pullPolicy: "IfNotPresent"

    runtime:
      repository: "python"
      tag: "3.13.9-slim-bookworm"
      pullPolicy: ""

    requirements: |
      boto3==1.40.70
      urllib==2.5.0

    polarsExtras: "async,cloudpickle,database,deltalake,fsspec,iceberg,numpy,pandas,pyarrow,pydantic,timezone"
```

Behind the scenes, this mechanism copies the Polars on-premises binary, wheel, uv, and a setup script from an init-container to the pod's main container. On startup of the main container, the setup script uses uv to install the polars wheel with the additional specified packages before starting the worker.

If you prefer self-building a Docker image, you can instead configure the chart to use your image:

```yaml
runtime:
  prebuilt:
    enabled: false

    runtime:
      repository: "your-prebuilt-image"
      tag: ""
      pullPolicy: ""

  composed:
    enabled: false
```

The Dockerfile for a prebuilt image can look something like this:

```Dockerfile
# your specific python version (you could also use any other base image and install python in a run statement)
FROM python:3.13.9-slim-bookworm

WORKDIR /opt

# your os-level dependencies
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libpq-dev \
    gcc \
 && rm -rf /var/lib/apt/lists/*

# install polars with specific features enabled for these packages
ENV POLARS_EXTRAS="async,cloudpickle,database,deltalake,fsspec,iceberg,numpy,pandas,pyarrow,pydantic,timezone"

# enale bash so we can write multiline strings
SHELL ["/bin/bash", "-c"]
RUN --mount=from=ghcr.io/astral-sh/uv:0.9.8,source=/uv,target=/bin/uv \
    --mount=type=cache,target=/root/.cache/uv \
    --mount=from=polarscloud/polars-on-premises:20251203,source=/opt/whl/polars-1.35.2-py3-none-any.whl,target=/opt/polars-1.35.2-py3-none-any.whl \
    --mount=type=bind,source=./requirements.txt,target=/opt/requirements.txt \
    # install polars with extras from wheel overriding to prevent installation of runtimes as those are already included in pc-cublet \
    echo -e "\
polars[$POLARS_EXTRAS] @ file:///opt/polars-1.35.2-py3-none-any.whl\n\
polars-runtime-32; sys_platform == 'never'\n\
polars-runtime-64; sys_platform == 'never'\n\
polars-runtime-compat; sys_platform == 'never'\n" | \
  uv pip install \
  -r requirements.txt \
  "polars[$POLARS_EXTRAS] @ file:///opt/polars-1.35.2-py3-none-any.whl" \
  --system \
  --overrides=-

COPY --from=polarscloud/polars-on-premises:20251203 /opt/bin/pc-cublet /opt/bin/pc-cublet

CMD ["/opt/bin/pc-cublet", "service"]
```

Note that the helm tests will still use the runtime defined in `.Values.runtime.composed.runtime`, so ensure that this image contains the same Python version as your prebuilt image. All the Python dependencies required for the tests are already included in the image used in the helm test, and the test does not require internet access, so a prebuilt image for the tests has no direct advantage.

### Storage

Polars requires large data storage for its operation. There are two main types of storage that need to be configured:

#### Shuffle data

High-performance storage for shuffle data. The storage is only used during query execution. By default, the ephemeral volume for this is disabled, and an `emptyDir` volume is used instead. However, to prevent the host from running out of disk space during large queries, it is recommended to enable an ephemeral volume for this purpose. The feature below will add a [Generic Ephemeral Volume](https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/) to each of the pods.

```yaml
shuffleData:
  ephemeralVolumeClaim:
    enabled: true
    storageClassName: "hostpath" # As configured in your k8s cluster
    size: 125Gi
```

You can also configure to shuffle to S3 instead of local disk. This is currently experimental. It may reduce shuffle performance compared to an ephemeral volume using a local SSD. You may configure the credentials as shown below. The key names correspond to the [`storage_options` parameter in `scan_parquet`](https://docs.pola.rs/api/python/stable/reference/api/polars.scan_parquet.html) (e.g. `aws_access_key_id`, `aws_secret_access_key`, `aws_session_token`, `aws_region`). We currently only support the AWS keys of the `storage_options` dictionary, but note that you can use any other cloud provider that supports the S3 API, such as MinIO or DigitalOcean Spaces.

```yaml
shuffleData:
  s3:
    enabled: true
    endpoint: "s3://my-bucket/path/to/dir"
    options:
      - name: aws_access_key_id
        valueFrom:
          secretKeyRef:
            name: my-s3-secret
            key: accessKeyId
      - name: aws_endpoint_url
        value: "http://localhost:9000"
  # etc.
```

Finally, you may also configure a shared persistent volume for anonymous results data. This is useful when you have a `ReadWriteMany` storage class available in your Kubernetes cluster.

```yaml
anonymousResults:
  sharedPersistentVolumeClaim:
    enabled: true
    storageClassName: "cephfs" # As configured in your k8s cluster
    size: 125Gi
```

#### Anonymous results data

For remote polars queries without a specific output sink, Polars Cloud can automatically add persistent sink. We call these sinks "anonymous results" sinks. Infrastructure-wise, these sinks are backed by S3-compatible storage, which should be accessible from all worker nodes and the python client. The data written to this location is not automatically deleted, so you need to configure a retention policy for this data yourself. You may configure the credentials as shown below. The key names correspond to the [`storage_options` parameter in `scan_parquet`](https://docs.pola.rs/api/python/stable/reference/api/polars.scan_parquet.html) (e.g. `aws_access_key_id`, `aws_secret_access_key`, `aws_session_token`, `aws_region`). We currently only support the AWS keys of the `storage_options` dictionary, but note that you can use any other cloud provider that supports the S3 API, such as MinIO or DigitalOcean Spaces.

```yaml
anonymousResults:
  s3:
    enabled: true
    endpoint: "s3://my-bucket/path/to/dir"
    options:
      - name: aws_access_key_id
        valueFrom:
          secretKeyRef:
            name: my-s3-secret
            key: accessKeyId
      - name: aws_endpoint_url
        value: "http://localhost:9000"
  # etc.
```

#### Temporary data

Polars itself uses some temporary storage location in the streaming engine and in some cases when downloading remote files. For most queries this is a relatively small volume and is not performance sensitive. By default, the persistent volume for this is disabled, and an `emptyDir` volume is used instead. However, to prevent the host from running out of disk space during large queries, it is recommended to enable a persistent volume for this purpose. The feature below will add a [Generic Ephemeral Volume](https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/) to each of the pods.

```yaml
temporaryData:
  ephemeralVolumeClaim:
    enabled: true
    storageClassName: "hostpath" # As configured in your k8s cluster
    size: 125Gi
```

### Resource allocation and node selectors

Most of the time, it is a good idea to run Polars on-premises on dedicated nodes, with only one worker pod per node.

First, figure out the available resources on your nodes. This is usually lower than the actual node resources, as Kubernetes reserves some resources for system daemons. For example, if you have a cluster of 3 `m4.xlarge` nodes (4 vCPUs, 16GiB memory), you may have 3770m CPU and 14.31GiB memory available.

```yaml
worker:
  deployment:
    replicaCount: 3

    runtimeContainer:
      resources:
        requests:
          cpu: 3770m
          memory: 14.31GiB
   
        limits:
          cpu: 3770m
          memory: 14.31GiB
```

If your cluster has other workloads running on it, we still recommend running Polars on-premises on dedicated nodes, and using node selectors and taints/tolerations to ensure that only Polars on-premises pods are scheduled on those nodes. For example, you can add a node selector, toleration, and affinity rules like this:

```yaml
worker:
  deployment:
    nodeSelector:
      kubernetes.io/e2e-az-name: e2e-az1
    tolerations:
    - key: "key"
      operator: "Equal"
      value: "value"
      effect: "NoSchedule"

    affinity:
     nodeAffinity:
       requiredDuringSchedulingIgnoredDuringExecution:
         nodeSelectorTerms:
         - matchExpressions:
           - key: kubernetes.io/e2e-az-name
             operator: In
             values:
             - e2e-az1
```

A compute cluster can be fully occupied running a query, preventing new queries from being scheduled. To avoid this, you can deploy this chart multiple times in the same cluster, reserving the resources between the different deployments.

The observatory service stores host metrics and preallocates a number of bytes for host metrics. This is configurable using the `observatory.maxMetricsBytesTotal` value. For every node in the cluster, the observatory service needs around 50 bytes of storage. So if you have 3 nodes, and you want to store an hour of host metrics, you need to set `observatory.maxMetricsBytesTotal` to 3 * 50 * 3600 = 540000.

### Host metrics

The dashboard shows host metrics for each worker node. These metrics are exported by default and can be disabled by setting `disableHostMetrics: true`.

### Exposing Polars on-premise

To use Polars on-premises from the Python client, the scheduler endpoint must be reachable from the client. By default, the chart creates a `ClusterIP` service for the scheduler, which is only reachable from within the cluster. To expose the scheduler outside the cluster, you can change the `scheduler.services.scheduler.type` value to `LoadBalancer` or `NodePort`. We recommend using the `LoadBalancer` type and configuring TLS such that the connection to the cluster is encrypted. If you decide to use an insecure connection, you must set `insecure=True` in the `ClusterContext`.

When the python client can't reach the scheduler, it will fail with a connection timeout like this:

```
RuntimeError: Error setting up gRPC connection, transport error
tcp connect error
Hint: you may need to restart the query if this error persists
```

The dashboard for Polars on-premises can be accessed at `http://localhost:3001`, and can be exposed outside the cluster by changing the `scheduler.services.observatory.type` value to `LoadBalancer` or `NodePort`.

## Telemetry

Polars on-premises uses OpenTelemetry as its telemetry framework. To receive OTLP metrics and traces, configure `telemetry.otlpEndpoint` to point to your OTLP collector. Logs are written to stdout in JSON format. For the compute plane, the log level can be configured using the `logLevel` value (see values section below).

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Polars | <developers@polars.tech> | <https://github.com/polars-inc> |

## Source Code

* <https://github.com/pola-rs/polars>
* <https://github.com/polars-inc/helm-charts>

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| nameOverride | string | `""` | Override the name of the chart |
| fullnameOverride | string | `""` | Override the full name of the chart |
| podLabels | object | `{}` | Common labels for all resources |
| podAnnotations | object | `{}` | Common annotations for all resources |
| clusterId | uuid | `""` | Unique identifier for the Polars cluster. Must be a valid UUID. This ID is used to identify the cluster in a multi-tenant environment. Defaults to "helm namespace/helm release name" if not set. |
| acceptEula | bool | `false` | To use this Helm Chart, you must accept the EULA. If you don't accept the EULA, this chart creates a single deployment that prints the EULA. |
| license.secretName | string | `""` | the name containing your polars license key |
| license.secretProperty | string | `""` | the property on the secret containing your license key |
| imagePullSecrets | list | `[]` | ImagePullSecrets is an optional list of references to secrets in the same namespace to use for pulling any of the images used by this PodSpec. If specified, these secrets will be passed to individual puller implementations for them to use. More info: https://kubernetes.io/docs/concepts/containers/images#specifying-imagepullsecrets-on-a-pod |
| runtime.prebuilt.runtime.repository | string | `"your-prebuilt-image"` | Container image name. More info: https://kubernetes.io/docs/concepts/containers/images |
| runtime.prebuilt.runtime.tag | string | `""` | Container image tag. More info: https://kubernetes.io/docs/concepts/containers/images |
| runtime.prebuilt.runtime.pullPolicy | string | `""` | Image pull policy. One of Always, Never, IfNotPresent. Defaults to Always if :latest tag is specified, or IfNotPresent otherwise. Cannot be updated. More info: https://kubernetes.io/docs/concepts/containers/images#updating-images |
| runtime.composed.dist.repository | string | `"polarscloud/polars-on-premises"` | Container image name. More info: https://kubernetes.io/docs/concepts/containers/images |
| runtime.composed.dist.tag | string | `""` | Container image tag. More info: https://kubernetes.io/docs/concepts/containers/images |
| runtime.composed.dist.pullPolicy | string | `"IfNotPresent"` | Image pull policy. One of Always, Never, IfNotPresent. Defaults to Always if :latest tag is specified, or IfNotPresent otherwise. Cannot be updated. More info: https://kubernetes.io/docs/concepts/containers/images#updating-images |
| runtime.composed.runtime.repository | string | `"python"` | Container image name. More info: https://kubernetes.io/docs/concepts/containers/images |
| runtime.composed.runtime.tag | string | `"3.13.9-slim-bookworm"` | Container image tag. More info: https://kubernetes.io/docs/concepts/containers/images |
| runtime.composed.runtime.pullPolicy | string | `""` | Image pull policy. One of Always, Never, IfNotPresent. Defaults to Always if :latest tag is specified, or IfNotPresent otherwise. Cannot be updated. More info: https://kubernetes.io/docs/concepts/containers/images#updating-images |
| telemetry.otlpEndpoint | string | `""` | Endpoint to send OTLP traces and metrics to. |
| logLevel | string | `"info"` | One of "info", "debug", "trace". |
| workerHeartbeatIntervalSecs | int | `5` | Heartbeat interval between polars workers and the scheduler in seconds. |
| disableHostMetrics | bool | `false` | Disable host metrics collection for the dashboard |
| anonymousResults | object | `{"s3":{"enabled":false,"endpoint":"s3://my-bucket/path/to/dir","options":[]}}` | Ephemeral storage for queries that don't specify a result location. Recommended to use S3 storage for persistence of results, but a volume claim may also be used. The compute plane does not automatically clean up anonymous results. |
| anonymousResults.s3 | object | `{"enabled":false,"endpoint":"s3://my-bucket/path/to/dir","options":[]}` | Configure S3 storage for anonymous results. |
| anonymousResults.s3.enabled | bool | `false` | Enable S3 storage for anonymous results. |
| anonymousResults.s3.endpoint | string | `"s3://my-bucket/path/to/dir"` | The entire S3 URI. If the bucket requires authentication, make sure to provide the credentials in the options field. |
| anonymousResults.s3.options | list | `[]` | Storage options for the S3 bucket. These correspond to scan_parquet's `storage_options` parameter. We only support the AWS keys. More info: https://docs.pola.rs/api/python/stable/reference/api/polars.scan_parquet.html |
| allowSharedDisk | bool | `true` | Disabling this option prevents the worker from writing to local disk. It is currently not possible to configure which sink locations are allowed. Users can alternatively configure sinks that write to S3. More info: https://docs.pola.rs/user-guide/io/cloud-storage/#writing-to-cloud-storage |
| shuffleData | object | `{"ephemeralVolumeClaim":{"enabled":false,"size":"125Gi","storageClassName":"hostpath"},"s3":{"enabled":false,"endpoint":"s3://my-bucket/path/to/dir","options":[]},"sharedPersistentVolumeClaim":{"enabled":false,"size":"125Gi","storageClassName":""}}` | Ephemeral storage for shuffle data. |
| shuffleData.ephemeralVolumeClaim | object | `{"enabled":false,"size":"125Gi","storageClassName":"hostpath"}` | Configure ephemeral storage for shuffle data. |
| shuffleData.ephemeralVolumeClaim.enabled | bool | `false` | Enable ephemeral volume claim for shuffle data. |
| shuffleData.ephemeralVolumeClaim.storageClassName | string | `"hostpath"` | storageClassName is the name of the StorageClass required by the claim. More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1 |
| shuffleData.ephemeralVolumeClaim.size | string | `"125Gi"` | Size of the volume requested by the claim. More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#capacity |
| shuffleData.sharedPersistentVolumeClaim | object | `{"enabled":false,"size":"125Gi","storageClassName":""}` | Shared persistent storage for shuffle data. |
| shuffleData.sharedPersistentVolumeClaim.enabled | bool | `false` | Enable shared persistent volume claim for shuffle data. |
| shuffleData.sharedPersistentVolumeClaim.storageClassName | string | `""` | storageClassName is the name of the StorageClass required by the claim. More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1 |
| shuffleData.sharedPersistentVolumeClaim.size | string | `"125Gi"` | Size of the volume requested by the claim. More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#capacity |
| shuffleData.s3 | object | `{"enabled":false,"endpoint":"s3://my-bucket/path/to/dir","options":[]}` | Configure S3 storage as shuffle data location. |
| shuffleData.s3.enabled | bool | `false` | Enable S3 storage for shuffle data. |
| shuffleData.s3.endpoint | string | `"s3://my-bucket/path/to/dir"` | The entire S3 URI. If the bucket requires authentication, make sure to provide the credentials in the options field. |
| shuffleData.s3.options | list | `[]` | Storage options for the S3 bucket. These correspond to scan_parquet's `storage_options` parameter. We only support the AWS keys. More info: https://docs.pola.rs/api/python/stable/reference/api/polars.scan_parquet.html |
| temporaryData | object | `{"ephemeralVolumeClaim":{"enabled":false,"size":"125Gi","storageClassName":"hostpath"}}` | Ephemeral storage for temporary data used in polars (e.g. polars streaming data). Recommended to use some host local SSD storage for better performance. |
| temporaryData.ephemeralVolumeClaim | object | `{"enabled":false,"size":"125Gi","storageClassName":"hostpath"}` | Configure ephemeral storage for temporary data. |
| temporaryData.ephemeralVolumeClaim.enabled | bool | `false` | Enable ephemeral volume claim for temporary data. |
| temporaryData.ephemeralVolumeClaim.storageClassName | string | `"hostpath"` | storageClassName is the name of the StorageClass required by the claim. More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1 |
| temporaryData.ephemeralVolumeClaim.size | string | `"125Gi"` | Size of the volume requested by the claim. More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#capacity |
| observatory.maxMetricsBytesTotal | int | `104857600` | Maximum number of bytes for host metrics storage |
| worker.serviceAccount.create | bool | `false` | Whether to create a service account. |
| worker.serviceAccount.name | string | `""` | The name of the service account to bind the leader election role binding to when create is false. Ignored if create is true. Defaults to "default" if not set. |
| worker.serviceAccount.automount | bool | `true` | AutomountServiceAccountToken indicates whether pods running as this service account should have an API token automatically mounted. Can be overridden at the pod level. |
| worker.deployment.replicaCount | int | `2` | Number of polars worker replicas. |
| worker.deployment.podAnnotations | object | `{}` | Additional annotations to add to the scheduler pod. |
| worker.deployment.podLabels | object | `{}` | Additional labels to add to the scheduler pod. |
| scheduler.services.internal.type | string | `"ClusterIP"` | type determines how the Service is exposed. Defaults to ClusterIP. Valid options are ClusterIP, NodePort, and LoadBalancer. "ClusterIP" allocates a cluster-internal IP address for load-balancing to endpoints. Endpoints are determined by the selector or if that is not specified, by manual construction of an Endpoints object or EndpointSlice objects. If clusterIP is "None", no virtual IP is allocated and the endpoints are published as a set of endpoints rather than a virtual IP. "NodePort" builds on ClusterIP and allocates a port on every node which routes to the same endpoints as the clusterIP. "LoadBalancer" builds on NodePort and creates an external load-balancer (if supported in the current cloud) which routes to the same endpoints as the clusterIP. "ExternalName" aliases this service to the specified externalName. Several other fields do not apply to ExternalName services. More info: https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types |
| scheduler.services.internal.annotations | object | `{}` | Additional annotations on the service object. Used by some controllers to setup TLS termination or load balancers. |
| scheduler.services.scheduler.type | string | `"ClusterIP"` | type determines how the Service is exposed. Defaults to ClusterIP. Valid options are ClusterIP, NodePort, and LoadBalancer. "ClusterIP" allocates a cluster-internal IP address for load-balancing to endpoints. Endpoints are determined by the selector or if that is not specified, by manual construction of an Endpoints object or EndpointSlice objects. If clusterIP is "None", no virtual IP is allocated and the endpoints are published as a set of endpoints rather than a virtual IP. "NodePort" builds on ClusterIP and allocates a port on every node which routes to the same endpoints as the clusterIP. "LoadBalancer" builds on NodePort and creates an external load-balancer (if supported in the current cloud) which routes to the same endpoints as the clusterIP. "ExternalName" aliases this service to the specified externalName. Several other fields do not apply to ExternalName services. More info: https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types |
| scheduler.services.scheduler.annotations | object | `{}` | Additional annotations on the service object. Used by some controllers to setup TLS termination or load balancers. |
| scheduler.services.observatory.type | string | `"ClusterIP"` | type determines how the Service is exposed. Defaults to ClusterIP. Valid options are ClusterIP, NodePort, and LoadBalancer. "ClusterIP" allocates a cluster-internal IP address for load-balancing to endpoints. Endpoints are determined by the selector or if that is not specified, by manual construction of an Endpoints object or EndpointSlice objects. If clusterIP is "None", no virtual IP is allocated and the endpoints are published as a set of endpoints rather than a virtual IP. "NodePort" builds on ClusterIP and allocates a port on every node which routes to the same endpoints as the clusterIP. "LoadBalancer" builds on NodePort and creates an external load-balancer (if supported in the current cloud) which routes to the same endpoints as the clusterIP. "ExternalName" aliases this service to the specified externalName. Several other fields do not apply to ExternalName services. More info: https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types |
| scheduler.services.observatory.annotations | object | `{}` | Additional annotations on the service object. Used by some controllers to setup TLS termination or load balancers. |
| scheduler.serviceAccount.create | bool | `false` | Whether to create a service account for the scheduler. |
| scheduler.serviceAccount.name | string | `""` | The name of the service account to bind the leader election role binding to when create is false. Ignored if create is true. Defaults to "default" if not set. |
| scheduler.serviceAccount.automount | bool | `true` | AutomountServiceAccountToken indicates whether pods running as this service account should have an API token automatically mounted. Can be overridden at the pod level. |
| scheduler.deployment.podAnnotations | object | `{}` | Additional annotations to add to the scheduler pod. |
| scheduler.deployment.podLabels | object | `{}` | Additional labels to add to the scheduler pod. |
| tests.serviceAccount.create | bool | `false` | Whether to create a service account. |
| tests.serviceAccount.name | string | `""` | The name of the service account to bind the leader election role binding to when create is false. Ignored if create is true. Defaults to "default" if not set. |
| tests.serviceAccount.automount | bool | `true` | AutomountServiceAccountToken indicates whether pods running as this service account should have an API token automatically mounted. Can be overridden at the pod level. |
| tests.pod.dnsPolicy | string | `""` | Set DNS policy for the pod. Defaults to "ClusterFirst". Valid values are 'ClusterFirstWithHostNet', 'ClusterFirst', 'Default' or 'None'. DNS parameters given in DNSConfig will be merged with the policy selected with DNSPolicy. To have DNS options set along with hostNetwork, you have to specify DNS policy explicitly to 'ClusterFirstWithHostNet'. More info: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/#pod-s-dns-policy |

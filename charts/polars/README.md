# Polars on-premise: Extremely fast distributed Query Engine for DataFrames

![Version: 0.0.8](https://img.shields.io/badge/Version-0.0.8-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 20251203](https://img.shields.io/badge/AppVersion-20251203-informational?style=flat-square)

Distributed query execution engine for Polars

**Homepage:** <https://pola.rs>

## Access to Polars on-premises artifacts

First of all, make sure to obtain a license for Polars on-premises by [signing up here](https://w0lzyfh2w8o.typeform.com/to/zuoDgoMv).
You will receive an access key for our private Docker registry as well as a license for running Polars on-premises.
Refer to the official Kubernetes documentation on [how to create a secret for pulling images from a private registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/).

## Quick Start

To install the chart, ensure you have created an image pull secret as described above and ensure that a secret containing the license file exists.

```console
$ kubectl create secret generic my-secret --from-file=license.json=license.json
$ helm repo add polars-inc https://polars-inc.github.io/helm-charts
$ helm upgrade --install polars polars-inc/polars \
    --set imagePullSecrets[0].name=dockerhub-secret-name \
    --set license.secretName=polars-secret-name \
    --set license.secretProperty=license.json
$ kubectl port-forward svc/polars-scheduler 5051:5051
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

### Helm Tests

You can instead also run the provided helm tests by running `helm test polars`. The chart contains a default list of images in `.Values.tests.images` that correspond to the supported polars-cloud client versions. The tests currently always run using the runtime image specified in `.Values.runtime.composed.runtime` since the client and compute cluster need to run the same version.

## Configuration

Running Polars on-premise in a production environment requires some configuration. The most important aspects are described below.

### Runtime

Polars on-premise consists of a single scheduler and multiple workers. Both components are contained in a single binary. While the scheduler can run without any system-level dependencies, the worker node needs the following:

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

Behind the scenes, this mechanism copies the Polars on-premise binary, wheel, uv, and a setup script from an init-container to the pod's main container. On startup of the main container, the setup script uses uv to install the polars wheel with the additional specified packages before starting the worker.

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

#### Temporary data

High-performance storage for shuffle data and other Polars temporary data. The storage is only used during query execution. By default, the persistent volume for this is disabled, and an `emptyDir` volume is used instead. However, to prevent the host from running out of disk space during large queries, it is recommended to enable a persistent volume for this purpose. The feature below will add a [Generic Ephemeral Volume](https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/) to each of the pods.

```yaml
temporaryData:
  persistentVolumeClaim:
    enabled: true
    storageClassName: "hostpath" # As configured in your k8s cluster
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

#### Volume retention

When using S3-compatible storage for anonymous results, it is recommended to configure the retention policy of the temporary data volume to `Delete`, so that temporary data is automatically cleaned up when the pod is deleted. Don't enable this if you store anonymous results on a persistent volume claim, as this would delete all anonymous results when the pod is deleted.

```yaml
worker:
  deployment:
    persistentVolumeClaimRetentionPolicy:
      whenDeleted: Delete
      whenScaled: Delete
```

### Resource allocation and node selectors

Most of the time, it is a good idea to run Polars on-premise on dedicated nodes, with only one worker pod per node.

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

If your cluster has other workloads running on it, we still recommend running Polars on-premise on dedicated nodes, and using node selectors and taints/tolerations to ensure that only Polars on-premise pods are scheduled on those nodes. For example, you can add a node selector, toleration, and affinity rules like this:

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

### Exposing Polars on-premise

To use Polars on-premise from the Python client, the scheduler endpoint must be reachable from the client. By default, the chart creates a `ClusterIP` service for the scheduler, which is only reachable from within the cluster. To expose the scheduler outside the cluster, you can change the `scheduler.services.scheduler.type` value to `LoadBalancer` or `NodePort`. We recommend using the `LoadBalancer` type and configuring TLS such that the connection to the cluster is encrypted. If you decide to use an insecure connection, you must set `insecure=True` in the `ClusterContext`.

When the python client can't reach the scheduler, it will fail with a connection timeout like this:

```
RuntimeError: Error setting up gRPC connection, transport error
tcp connect error
Hint: you may need to restart the query if this error persists
```

## Telemetry

Polars on-premise uses OpenTelemetry as its telemetry framework. To receive OTLP metrics and traces, configure `telemetry.otlpEndpoint` to point to your OTLP collector. Logs are written to stdout in JSON format. For the compute plane, the log level can be configured using the `logLevel` value (see values section below).

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
| runtime.prebuilt.enabled | bool | `false` |  |
| runtime.prebuilt.runtime.repository | string | `"your-prebuilt-image"` | Container image name. More info: https://kubernetes.io/docs/concepts/containers/images |
| runtime.prebuilt.runtime.tag | string | `""` | Container image tag. More info: https://kubernetes.io/docs/concepts/containers/images |
| runtime.prebuilt.runtime.pullPolicy | string | `""` | Image pull policy. One of Always, Never, IfNotPresent. Defaults to Always if :latest tag is specified, or IfNotPresent otherwise. Cannot be updated. More info: https://kubernetes.io/docs/concepts/containers/images#updating-images |
| runtime.composed.enabled | bool | `true` |  |
| runtime.composed.dist.repository | string | `"polarscloud/polars-on-premises"` | Container image name. More info: https://kubernetes.io/docs/concepts/containers/images |
| runtime.composed.dist.tag | string | `""` | Container image tag. More info: https://kubernetes.io/docs/concepts/containers/images |
| runtime.composed.dist.pullPolicy | string | `"IfNotPresent"` | Image pull policy. One of Always, Never, IfNotPresent. Defaults to Always if :latest tag is specified, or IfNotPresent otherwise. Cannot be updated. More info: https://kubernetes.io/docs/concepts/containers/images#updating-images |
| runtime.composed.runtime.repository | string | `"python"` | Container image name. More info: https://kubernetes.io/docs/concepts/containers/images |
| runtime.composed.runtime.tag | string | `"3.13.9-slim-bookworm"` | Container image tag. More info: https://kubernetes.io/docs/concepts/containers/images |
| runtime.composed.runtime.pullPolicy | string | `""` | Image pull policy. One of Always, Never, IfNotPresent. Defaults to Always if :latest tag is specified, or IfNotPresent otherwise. Cannot be updated. More info: https://kubernetes.io/docs/concepts/containers/images#updating-images |
| runtime.composed.requirements | string | `""` |  |
| runtime.composed.polarsExtras | string | `"async,cloudpickle,database,deltalake,fsspec,iceberg,numpy,pandas,pyarrow,pydantic,timezone"` |  |
| telemetry.otlpEndpoint | string | `""` | Endpoint to send OTLP traces and metrics to. |
| logLevel | string | `"info"` | One of "info", "debug", "trace". |
| workerHeartbeatIntervalSecs | int | `5` | Heartbeat interval between polars workers and the scheduler in seconds. |
| anonymousResults | object | `{"s3":{"enabled":false,"endpoint":"s3://my-bucket/path/to/dir","options":[]}}` | Ephemeral storage for queries that don't specify a result location. Recommended to use S3 storage for persistence of results, but a volume claim may also be used. The compute plane does not automatically clean up anonymous results. |
| anonymousResults.s3.enabled | bool | `false` | Write anonymous results to S3. |
| anonymousResults.s3.endpoint | string | `"s3://my-bucket/path/to/dir"` | The entire S3 URI. If the bucket requires authentication, make sure to provide the credentials in the options field. |
| anonymousResults.s3.options | list | `[]` | Storage options for the S3 bucket. These correspond to scan_parquet's `storage_options` parameter. We only support the AWS keys. More info: https://docs.pola.rs/api/python/stable/reference/api/polars.scan_parquet.html |
| allowSharedDisk | bool | `true` | Disabling this option prevents the worker from writing to local disk. It is currently not possible to configure which sink locations are allowed. Users can alternatively configure sinks that write to S3. More info: https://docs.pola.rs/user-guide/io/cloud-storage/#writing-to-cloud-storage |
| shuffleData.ephemeralVolumeClaim.enabled | bool | `false` | Write shuffle data to volume claimEphemeral storage for temporary data used in shuffles. Recommended to use some host local SSD storage for better performance. More info: https://kubernetes.io/docs/concepts/storage/volumes/#local |
| shuffleData.ephemeralVolumeClaim.storageClassName | string | `"hostpath"` | storageClassName is the name of the StorageClass required by the claim. More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1 |
| shuffleData.ephemeralVolumeClaim.size | string | `"125Gi"` | Size of the volume requested by the claim. More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#capacity |
| shuffleData.s3.enabled | bool | `false` | Write shuffle data to S3. |
| shuffleData.s3.endpoint | string | `"s3://my-bucket/path/to/dir"` | The entire S3 URI. If the bucket requires authentication, make sure to provide the credentials in the options field. |
| shuffleData.s3.options | list | `[]` | Storage options for the S3 bucket. These correspond to scan_parquet's `storage_options` parameter. We only support the AWS keys. More info: https://docs.pola.rs/api/python/stable/reference/api/polars.scan_parquet.html |
| temporaryData.ephemeralVolumeClaim.enabled | bool | `false` | Ephemeral storage for temporary data used in polars (e.g. polars streaming data). More info: https://kubernetes.io/docs/concepts/storage/volumes/#local |
| temporaryData.ephemeralVolumeClaim.storageClassName | string | `"hostpath"` | storageClassName is the name of the StorageClass required by the claim. More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1 |
| temporaryData.ephemeralVolumeClaim.size | string | `"125Gi"` | Size of the volume requested by the claim. More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#capacity |
| observatory.maxMetricsBytesTotal | int | `104857600` | Maximum number of bytes for host metrics storage |
| worker.serviceAccount.create | bool | `false` | Whether to create a service account. |
| worker.serviceAccount.name | string | `""` | The name of the service account to bind the leader election role binding to when create is false. Ignored if create is true. Defaults to "default" if not set. |
| worker.serviceAccount.automount | bool | `true` | AutomountServiceAccountToken indicates whether pods running as this service account should have an API token automatically mounted. Can be overridden at the pod level. |
| worker.deployment.replicaCount | int | `2` | Number of polars worker replicas. |
| worker.deployment.revisionHistoryLimit | int | `10` | revisionHistoryLimit is the maximum number of revisions that will be maintained in the Deployment's revision history. The default value is 10. |
| worker.deployment.podAnnotations | object | `{}` | Additional annotations to add to the scheduler pod. |
| worker.deployment.podLabels | object | `{}` | Additional labels to add to the scheduler pod. |
| worker.deployment.dnsPolicy | string | `""` | Set DNS policy for the pod. Defaults to "ClusterFirst". Valid values are 'ClusterFirstWithHostNet', 'ClusterFirst', 'Default' or 'None'. DNS parameters given in DNSConfig will be merged with the policy selected with DNSPolicy. To have DNS options set along with hostNetwork, you have to specify DNS policy explicitly to 'ClusterFirstWithHostNet'. More info: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/#pod-s-dns-policy |
| worker.deployment.dnsConfig | object | `{}` | Specifies the DNS parameters of a pod. Parameters specified here will be merged to the generated DNS configuration based on DNSPolicy. More info: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/#pod-dns-config |
| worker.deployment.schedulerName | string | `""` | If specified, the pod will be dispatched by specified scheduler. If not specified, the pod will be dispatched by default scheduler. |
| worker.deployment.automountServiceAccountToken | bool | `true` | AutomountServiceAccountToken indicates whether a service account token should be automatically mounted. |
| worker.deployment.podSecurityContext | object | `{}` | SecurityContext holds pod-level security attributes and common container settings. |
| worker.deployment.hostAliases | list | `[]` | List of host aliases to add to the pod's /etc/hosts file. More info: https://kubernetes.io/docs/concepts/services-networking/add-entries-to-pod-etc-hosts-with-host-aliases/ |
| worker.deployment.distContainer.securityContext | object | `{}` | SecurityContext defines the security options the container should be run with. If set, the fields of SecurityContext override the equivalent fields of PodSecurityContext. More info: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/ |
| worker.deployment.distContainer.resources | object | `{}` | Requests describes the minimum amount of compute resources required. If Requests is omitted for a container, it defaults to Limits if that is explicitly specified, otherwise to an implementation-defined value. Requests cannot exceed Limits. More info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| worker.deployment.runtimeContainer.securityContext | object | `{}` | SecurityContext defines the security options the container should be run with. If set, the fields of SecurityContext override the equivalent fields of PodSecurityContext. More info: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/ |
| worker.deployment.runtimeContainer.readinessProbe.tcpSocket.port | string | `"worker-service"` |  |
| worker.deployment.runtimeContainer.readinessProbe.initialDelaySeconds | int | `1` | Number of seconds after the container has started before liveness probes are initiated. More info: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle#container-probes |
| worker.deployment.runtimeContainer.readinessProbe.periodSeconds | int | `10` | How often (in seconds) to perform the probe. |
| worker.deployment.runtimeContainer.readinessProbe.failureThreshold | int | `25` | Minimum consecutive failures for the probe to be considered failed after having succeeded. |
| worker.deployment.runtimeContainer.env | list | `[]` | List of environment variables to set in the container. |
| worker.deployment.runtimeContainer.lifecycleHooks | object | `{}` | Actions that the management system should take in response to container lifecycle events. |
| worker.deployment.runtimeContainer.resources | object | `{}` | Requests describes the minimum amount of compute resources required. If Requests is omitted for a container, it defaults to Limits if that is explicitly specified, otherwise to an implementation-defined value. Requests cannot exceed Limits. More info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| worker.deployment.runtimeContainer.volumeMounts | list | `[]` | Pod volumes to mount into the container's filesystem. |
| worker.deployment.priorityClassName | string | `""` | If specified, indicates the pod's priority. "system-node-critical" and "system-cluster-critical" are two special keywords which indicate the highest priorities with the former being the highest priority. Any other name must be defined by creating a PriorityClass object with that name. If not specified, the pod priority will be default or zero if there is no default. More info: https://kubernetes.io/docs/concepts/configuration/pod-priority-preemption/#priorityclass |
| worker.deployment.runtimeClassName | string | `""` | RuntimeClassName refers to a RuntimeClass object in the node.k8s.io group, which should be used to run this pod. If no RuntimeClass resource matches the named class, the pod will not be run. If unset or empty, the "legacy" RuntimeClass will be used, which is an implicit class with an empty definition that uses the default runtime handler. More info: https://kubernetes.io/docs/concepts/containers/runtime-class/ |
| worker.deployment.volumes | list | `[]` | List of volumes that can be mounted by containers belonging to the pod. More info: https://kubernetes.io/docs/concepts/storage/volumes |
| worker.deployment.nodeSelector | object | `{}` | NodeSelector is a selector which must be true for the pod to fit on a node. Selector which must match a node's labels for the pod to be scheduled on that node. More info: https://kubernetes.io/docs/concepts/configuration/assign-pod-node/ |
| worker.deployment.affinity | object | `{}` | If specified, the pod's scheduling constraints |
| worker.deployment.tolerations | list | `[]` | If specified, the pod's tolerations. |
| worker.deployment.topologySpreadConstraints | list | `[]` | TopologySpreadConstraints describes how a group of pods ought to spread across topology domains. Scheduler will schedule pods in a way which abides by the constraints. All topologySpreadConstraints are ANDed. |
| worker.deployment.hostNetwork | bool | `false` | Host networking requested for this pod. Use the host's network namespace. If this option is set, the ports that will be used must be specified. Default to false. |
| scheduler.services.internal.type | string | `"ClusterIP"` | type determines how the Service is exposed. Defaults to ClusterIP. Valid options are ClusterIP, NodePort, and LoadBalancer. "ClusterIP" allocates a cluster-internal IP address for load-balancing to endpoints. Endpoints are determined by the selector or if that is not specified, by manual construction of an Endpoints object or EndpointSlice objects. If clusterIP is "None", no virtual IP is allocated and the endpoints are published as a set of endpoints rather than a virtual IP. "NodePort" builds on ClusterIP and allocates a port on every node which routes to the same endpoints as the clusterIP. "LoadBalancer" builds on NodePort and creates an external load-balancer (if supported in the current cloud) which routes to the same endpoints as the clusterIP. "ExternalName" aliases this service to the specified externalName. Several other fields do not apply to ExternalName services. More info: https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types |
| scheduler.services.internal.annotations | object | `{}` | Additional annotations on the service object. Used by some controllers to setup TLS termination or load balancers. |
| scheduler.services.scheduler.type | string | `"ClusterIP"` | type determines how the Service is exposed. Defaults to ClusterIP. Valid options are ClusterIP, NodePort, and LoadBalancer. "ClusterIP" allocates a cluster-internal IP address for load-balancing to endpoints. Endpoints are determined by the selector or if that is not specified, by manual construction of an Endpoints object or EndpointSlice objects. If clusterIP is "None", no virtual IP is allocated and the endpoints are published as a set of endpoints rather than a virtual IP. "NodePort" builds on ClusterIP and allocates a port on every node which routes to the same endpoints as the clusterIP. "LoadBalancer" builds on NodePort and creates an external load-balancer (if supported in the current cloud) which routes to the same endpoints as the clusterIP. "ExternalName" aliases this service to the specified externalName. Several other fields do not apply to ExternalName services. More info: https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types |
| scheduler.services.scheduler.annotations | object | `{}` | Additional annotations on the service object. Used by some controllers to setup TLS termination or load balancers. |
| scheduler.services.observatory.type | string | `"ClusterIP"` | type determines how the Service is exposed. Defaults to ClusterIP. Valid options are ClusterIP, NodePort, and LoadBalancer. "ClusterIP" allocates a cluster-internal IP address for load-balancing to endpoints. Endpoints are determined by the selector or if that is not specified, by manual construction of an Endpoints object or EndpointSlice objects. If clusterIP is "None", no virtual IP is allocated and the endpoints are published as a set of endpoints rather than a virtual IP. "NodePort" builds on ClusterIP and allocates a port on every node which routes to the same endpoints as the clusterIP. "LoadBalancer" builds on NodePort and creates an external load-balancer (if supported in the current cloud) which routes to the same endpoints as the clusterIP. "ExternalName" aliases this service to the specified externalName. Several other fields do not apply to ExternalName services. More info: https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types |
| scheduler.services.observatory.annotations | object | `{}` | Additional annotations on the service object. Used by some controllers to setup TLS termination or load balancers. |
| scheduler.serviceAccount.create | bool | `false` | Whether to create a service account for the scheduler. |
| scheduler.serviceAccount.name | string | `""` | The name of the service account to bind the leader election role binding to when create is false. Ignored if create is true. Defaults to "default" if not set. |
| scheduler.serviceAccount.automount | bool | `true` | AutomountServiceAccountToken indicates whether pods running as this service account should have an API token automatically mounted. Can be overridden at the pod level. |
| scheduler.deployment.revisionHistoryLimit | int | `10` | revisionHistoryLimit is the maximum number of revisions that will be maintained in the Deployment's revision history. The default value is 10. |
| scheduler.deployment.rollout | object | `{"rollingUpdate":{"maxUnavailable":1},"strategy":"RollingUpdate"}` | Rollout strategy for the scheduler deployment. One of RollingUpdate or Recreate. |
| scheduler.deployment.podAnnotations | object | `{}` | Additional annotations to add to the scheduler pod. |
| scheduler.deployment.podLabels | object | `{}` | Additional labels to add to the scheduler pod. |
| scheduler.deployment.dnsPolicy | string | `""` | Set DNS policy for the pod. Defaults to "ClusterFirst". Valid values are 'ClusterFirstWithHostNet', 'ClusterFirst', 'Default' or 'None'. DNS parameters given in DNSConfig will be merged with the policy selected with DNSPolicy. To have DNS options set along with hostNetwork, you have to specify DNS policy explicitly to 'ClusterFirstWithHostNet'. More info: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/#pod-s-dns-policy |
| scheduler.deployment.dnsConfig | object | `{}` | Specifies the DNS parameters of a pod. Parameters specified here will be merged to the generated DNS configuration based on DNSPolicy. More info: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/#pod-dns-config |
| scheduler.deployment.schedulerName | string | `""` | If specified, the pod will be dispatched by specified scheduler. If not specified, the pod will be dispatched by default scheduler. |
| scheduler.deployment.automountServiceAccountToken | bool | `true` | AutomountServiceAccountToken indicates whether a service account token should be automatically mounted. |
| scheduler.deployment.podSecurityContext | object | `{}` | SecurityContext holds pod-level security attributes and common container settings. |
| scheduler.deployment.hostAliases | list | `[]` | List of host aliases to add to the pod's /etc/hosts file. More info: https://kubernetes.io/docs/concepts/services-networking/add-entries-to-pod-etc-hosts-with-host-aliases/ |
| scheduler.deployment.distContainer.securityContext | object | `{}` | SecurityContext defines the security options the container should be run with. If set, the fields of SecurityContext override the equivalent fields of PodSecurityContext. More info: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/ |
| scheduler.deployment.distContainer.resources | object | `{}` | Requests describes the minimum amount of compute resources required. If Requests is omitted for a container, it defaults to Limits if that is explicitly specified, otherwise to an implementation-defined value. Requests cannot exceed Limits. More info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| scheduler.deployment.runtimeContainer.securityContext | object | `{}` | SecurityContext defines the security options the container should be run with. If set, the fields of SecurityContext override the equivalent fields of PodSecurityContext. More info: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/ |
| scheduler.deployment.runtimeContainer.readinessProbe.tcpSocket.port | string | `"sched"` |  |
| scheduler.deployment.runtimeContainer.readinessProbe.initialDelaySeconds | int | `1` | Number of seconds after the container has started before liveness probes are initiated. More info: https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle#container-probes |
| scheduler.deployment.runtimeContainer.readinessProbe.periodSeconds | int | `10` | How often (in seconds) to perform the probe. |
| scheduler.deployment.runtimeContainer.readinessProbe.failureThreshold | int | `25` | Minimum consecutive failures for the probe to be considered failed after having succeeded. |
| scheduler.deployment.runtimeContainer.env | list | `[]` | List of environment variables to set in the container. |
| scheduler.deployment.runtimeContainer.lifecycleHooks | object | `{}` | Actions that the management system should take in response to container lifecycle events. |
| scheduler.deployment.runtimeContainer.resources | object | `{}` | Requests describes the minimum amount of compute resources required. If Requests is omitted for a container, it defaults to Limits if that is explicitly specified, otherwise to an implementation-defined value. Requests cannot exceed Limits. More info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| scheduler.deployment.runtimeContainer.volumeMounts | list | `[]` | Pod volumes to mount into the container's filesystem. |
| scheduler.deployment.priorityClassName | string | `""` | If specified, indicates the pod's priority. "system-node-critical" and "system-cluster-critical" are two special keywords which indicate the highest priorities with the former being the highest priority. Any other name must be defined by creating a PriorityClass object with that name. If not specified, the pod priority will be default or zero if there is no default. More info: https://kubernetes.io/docs/concepts/configuration/pod-priority-preemption/#priorityclass |
| scheduler.deployment.runtimeClassName | string | `""` | RuntimeClassName refers to a RuntimeClass object in the node.k8s.io group, which should be used to run this pod. If no RuntimeClass resource matches the named class, the pod will not be run. If unset or empty, the "legacy" RuntimeClass will be used, which is an implicit class with an empty definition that uses the default runtime handler. More info: https://kubernetes.io/docs/concepts/containers/runtime-class/ |
| scheduler.deployment.volumes | list | `[]` | List of volumes that can be mounted by containers belonging to the pod. More info: https://kubernetes.io/docs/concepts/storage/volumes |
| scheduler.deployment.nodeSelector | object | `{}` | NodeSelector is a selector which must be true for the pod to fit on a node. Selector which must match a node's labels for the pod to be scheduled on that node. More info: https://kubernetes.io/docs/concepts/configuration/assign-pod-node/ |
| scheduler.deployment.affinity | object | `{}` | If specified, the pod's scheduling constraints |
| scheduler.deployment.tolerations | list | `[]` | If specified, the pod's tolerations. |
| scheduler.deployment.topologySpreadConstraints | list | `[]` | TopologySpreadConstraints describes how a group of pods ought to spread across topology domains. Scheduler will schedule pods in a way which abides by the constraints. All topologySpreadConstraints are ANDed. |
| scheduler.deployment.hostNetwork | bool | `false` | Host networking requested for this pod. Use the host's network namespace. If this option is set, the ports that will be used must be specified. Default to false. |
| tests.images | list | `[]` |  |
| tests.serviceAccount.create | bool | `false` | Whether to create a service account. |
| tests.serviceAccount.name | string | `""` | The name of the service account to bind the leader election role binding to when create is false. Ignored if create is true. Defaults to "default" if not set. |
| tests.serviceAccount.automount | bool | `true` | AutomountServiceAccountToken indicates whether pods running as this service account should have an API token automatically mounted. Can be overridden at the pod level. |
| tests.pod.dnsPolicy | string | `""` | Set DNS policy for the pod. Defaults to "ClusterFirst". Valid values are 'ClusterFirstWithHostNet', 'ClusterFirst', 'Default' or 'None'. DNS parameters given in DNSConfig will be merged with the policy selected with DNSPolicy. To have DNS options set along with hostNetwork, you have to specify DNS policy explicitly to 'ClusterFirstWithHostNet'. More info: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/#pod-s-dns-policy |
| tests.pod.dnsConfig | object | `{}` | Specifies the DNS parameters of a pod. Parameters specified here will be merged to the generated DNS configuration based on DNSPolicy. More info: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/#pod-dns-config |
| tests.pod.schedulerName | string | `""` | If specified, the pod will be dispatched by specified scheduler. If not specified, the pod will be dispatched by default scheduler. |
| tests.pod.automountServiceAccountToken | bool | `true` | AutomountServiceAccountToken indicates whether a service account token should be automatically mounted. |
| tests.pod.podSecurityContext | object | `{}` | SecurityContext holds pod-level security attributes and common container settings. |
| tests.pod.hostAliases | list | `[]` | List of host aliases to add to the pod's /etc/hosts file. More info: https://kubernetes.io/docs/concepts/services-networking/add-entries-to-pod-etc-hosts-with-host-aliases/ |
| tests.pod.distContainer.securityContext | object | `{}` | SecurityContext defines the security options the container should be run with. If set, the fields of SecurityContext override the equivalent fields of PodSecurityContext. More info: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/ |
| tests.pod.distContainer.resources | object | `{}` | Requests describes the minimum amount of compute resources required. If Requests is omitted for a container, it defaults to Limits if that is explicitly specified, otherwise to an implementation-defined value. Requests cannot exceed Limits. More info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| tests.pod.runtimeContainer.securityContext | object | `{}` | SecurityContext defines the security options the container should be run with. If set, the fields of SecurityContext override the equivalent fields of PodSecurityContext. More info: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/ |
| tests.pod.runtimeContainer.env | list | `[]` | List of environment variables to set in the container. |
| tests.pod.runtimeContainer.lifecycleHooks | object | `{}` | Actions that the management system should take in response to container lifecycle events. |
| tests.pod.runtimeContainer.resources | object | `{}` | Requests describes the minimum amount of compute resources required. If Requests is omitted for a container, it defaults to Limits if that is explicitly specified, otherwise to an implementation-defined value. Requests cannot exceed Limits. More info: https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| tests.pod.runtimeContainer.volumeMounts | list | `[]` | Pod volumes to mount into the container's filesystem. |
| tests.pod.priorityClassName | string | `""` | If specified, indicates the pod's priority. "system-node-critical" and "system-cluster-critical" are two special keywords which indicate the highest priorities with the former being the highest priority. Any other name must be defined by creating a PriorityClass object with that name. If not specified, the pod priority will be default or zero if there is no default. More info: https://kubernetes.io/docs/concepts/configuration/pod-priority-preemption/#priorityclass |
| tests.pod.runtimeClassName | string | `""` | RuntimeClassName refers to a RuntimeClass object in the node.k8s.io group, which should be used to run this pod. If no RuntimeClass resource matches the named class, the pod will not be run. If unset or empty, the "legacy" RuntimeClass will be used, which is an implicit class with an empty definition that uses the default runtime handler. More info: https://kubernetes.io/docs/concepts/containers/runtime-class/ |
| tests.pod.volumes | list | `[]` | List of volumes that can be mounted by containers belonging to the pod. More info: https://kubernetes.io/docs/concepts/storage/volumes |
| tests.pod.nodeSelector | object | `{}` | NodeSelector is a selector which must be true for the pod to fit on a node. Selector which must match a node's labels for the pod to be scheduled on that node. More info: https://kubernetes.io/docs/concepts/configuration/assign-pod-node/ |
| tests.pod.affinity | object | `{}` | If specified, the pod's scheduling constraints |
| tests.pod.tolerations | list | `[]` | If specified, the pod's tolerations. |
| tests.pod.topologySpreadConstraints | list | `[]` | TopologySpreadConstraints describes how a group of pods ought to spread across topology domains. Scheduler will schedule pods in a way which abides by the constraints. All topologySpreadConstraints are ANDed. |
| tests.pod.hostNetwork | bool | `false` | Host networking requested for this pod. Use the host's network namespace. If this option is set, the ports that will be used must be specified. Default to false. |

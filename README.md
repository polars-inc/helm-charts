<h1 align="center">
  <a href="https://pola.rs">
    <img src="https://raw.githubusercontent.com/pola-rs/polars-static/master/banner/polars_github_banner.svg" alt="Polars logo">
  </a>
</h1>

# Polars Helm Charts

![Release Charts](https://github.com/polars-inc/helm-charts/actions/workflows/release.yaml/badge.svg?branch=main) [![Releases downloads](https://img.shields.io/github/downloads/polars-inc/helm-charts/total.svg)](https://github.com/polars-inc/helm-charts/releases) ![Docker Pulls](https://img.shields.io/docker/pulls/polarscloud/polars-on-premises)

Interested in running Polars on-premises? [Sign up here](https://cloud.pola.rs/api/redirects/register) and get started for free. Select Kubernetes as your deployment target during onboarding.

Looking for an air-gapped deployment? [Contact the team here](https://w0lzyfh2w8o.typeform.com/to/f37L1SRx#form_name=enterprise&form_origin=helm-charts-repo) to discuss your setup.

## Usage

[Helm](https://helm.sh) must be installed to use the charts.
Please refer to Helm's [documentation](https://helm.sh/docs/) to get started.

Once Helm is set up properly, add the repository as follows:

```console
helm repo add polars-inc https://polars-inc.github.io/helm-charts
```

You can then run `helm search repo polars-inc` to see the charts.

# helm-envoy

> Environment-aware value file management for Helm.

Stop copy-pasting `-f values-staging.yaml` flags. `helm-envoy` is a Helm plugin that
automatically resolves and applies the right value files for your environment, so your
deploy commands stay clean and consistent across every environment you ship to.

---

## The problem

Most teams end up with charts that look like this:

```
my-chart/
  values.yaml
  values-dev.yaml
  values-staging.yaml
  values-production.yaml
```

And deploy commands that look like this:

```sh
# staging
helm upgrade my-app ./my-chart -f my-chart/values.yaml -f my-chart/values-staging.yaml --atomic

# production
helm upgrade my-app ./my-chart -f my-chart/values.yaml -f my-chart/values-production.yaml --atomic
```

This is error-prone. The wrong `-f` flag in the wrong pipeline means staging values go to
production, or a deploy silently uses defaults because someone forgot the flag entirely.

## The solution

`helm-envoy` resolves value files from the chart directory automatically. You tell it which
environment, it figures out the files:

```sh
helm envoy upgrade my-app ./my-chart --environment staging -- --atomic
helm envoy upgrade my-app ./my-chart --environment production -- --atomic
```

One flag. No file path juggling. No copy-paste errors.

---

## Installation

```sh
helm plugin install https://github.com/leeroya/helm-envoy
```

**Requirements:** Helm 3.x, Bash (Linux/macOS) or PowerShell (Windows).

### Upgrading

```sh
helm plugin update envoy
```

### Uninstalling

```sh
helm plugin uninstall envoy
```

---

## Usage

### Install a release

```sh
helm envoy install <release> <chart> --environment <env> [-- <helm flags>]
```

### Upgrade a release

```sh
helm envoy upgrade <release> <chart> --environment <env> [-- <helm flags>]
```

### List available environments

```sh
helm envoy list-environments <chart-path>
```

---

## Value file resolution

For a given `--environment <env>`, envoy looks for these files inside the chart directory
and applies all that exist, in this order (later files take priority):

| File                          | Purpose                                      | Required |
|-------------------------------|----------------------------------------------|----------|
| `values.yaml`                 | Base defaults shared across all environments | No       |
| `values-<env>.yaml`           | Environment-specific overrides               | Yes      |
| `values-<env>.local.yaml`     | Local machine overrides (gitignored)         | No       |

If `values-<env>.yaml` does not exist, the command fails immediately and lists the
environments that are available.

---

## Examples

### Basic deploy

```sh
helm envoy install my-app ./my-chart --environment dev
```

Equivalent to:
```sh
helm install my-app ./my-chart \
  -f my-chart/values.yaml \
  -f my-chart/values-dev.yaml
```

### Upgrade with extra Helm flags

Pass additional Helm flags after `--`:

```sh
helm envoy upgrade my-app ./my-chart --environment production -- \
  --atomic \
  --timeout 10m \
  --set image.tag=v2.3.1
```

### Discover what environments a chart supports

```sh
$ helm envoy list-environments ./my-chart

Environments found in './my-chart':
  - dev        (./my-chart/values-dev.yaml)
  - production (./my-chart/values-production.yaml)
  - staging    (./my-chart/values-staging.yaml)
```

### Local overrides (per-developer, never committed)

Create `values-<env>.local.yaml` alongside your environment file for values that should
only apply on your machine — credentials, local endpoints, debug flags. These are
automatically picked up when present and should be added to `.gitignore`.

```
my-chart/
  values.yaml
  values-dev.yaml
  values-dev.local.yaml   ← gitignored, picked up automatically
```

---

## Chart layout convention

`helm-envoy` expects environment value files to follow this naming pattern:

```
values-<environment>.yaml
```

Where `<environment>` is any string you choose — `dev`, `staging`, `production`,
`uat`, `eu-prod`, etc. No configuration required; the plugin discovers them by scanning
the chart directory.

A typical chart layout:

```
my-chart/
  Chart.yaml
  templates/
  values.yaml              ← base defaults
  values-dev.yaml          ← dev overrides
  values-staging.yaml      ← staging overrides
  values-production.yaml   ← production overrides
```

---

## CI/CD integration

`helm-envoy` is a thin wrapper around `helm install` / `helm upgrade` — it works anywhere
Helm does. In a pipeline, replace your existing deploy step:

```yaml
# Before
- run: helm upgrade my-app ./chart -f chart/values.yaml -f chart/values-$ENV.yaml --atomic

# After
- run: helm envoy upgrade my-app ./chart --environment $ENV -- --atomic
```

---

## Platform support

| Platform       | Script              |
|----------------|---------------------|
| Linux / macOS  | `scripts/envoy.sh`  |
| Windows        | `scripts/envoy.ps1` |

The correct script is selected automatically by Helm via `plugin.yaml`.

---

## Contributing

Issues and pull requests are welcome at [github.com/leeroya/helm-envoy](https://github.com/leeroya/helm-envoy).

---

## License

MIT

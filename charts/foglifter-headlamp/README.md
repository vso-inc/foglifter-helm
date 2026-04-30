# foglifter-headlamp

Wrapper Helm chart that installs [Headlamp](https://headlamp.dev) plus a
minimal `kube-prometheus-stack` (no Grafana, no Alertmanager, no PVC) into
a FogLifter cluster, fronted by either a Gateway API `HTTPRoute` (default
— with a native `RequestRedirect` filter for the slash redirect) or a
standard `Ingress` (with a Traefik slash-redirect `Middleware`).

The chart's defaults align with the `charts/foglifter` umbrella's
`gatewayAPI` defaults, so installing this chart into a cluster that
already runs `charts/foglifter` joins the existing `foglifter-gateway`
with no extra configuration beyond the public hostname.

## Scope guardrail

This chart is intended for **private / internal** clusters whose ingress
is not directly reachable from the open internet. Headlamp's bearer-token
login is the only auth gate; there is no edge auth in the chart. Do **not**
install on a cluster whose ingress is reachable by untrusted networks
without first adding an edge auth layer (basic auth, OIDC forward-auth,
mTLS, etc.).

## Install

```sh
helm dependency update charts/foglifter-headlamp
helm upgrade --install foglifter-headlamp ./charts/foglifter-headlamp \
  -n headlamp --create-namespace \
  --set host=example.com
```

`host` is the only required value when the foglifter chart is installed
with its default Gateway configuration. Override `gatewayAPI.gateway.*`
to point at a different Gateway, or switch to the standard Ingress
profile (see below).

## Profiles

The chart ships two ingress profiles, mirroring the `charts/foglifter`
umbrella.

### Gateway API HTTPRoute (default)

Renders a `gateway.networking.k8s.io/v1 HTTPRoute` that attaches to the
`foglifter-gateway` `Gateway` in the `foglifter` namespace. The slash
redirect (`<path>` → `<path>/`) uses the native `RequestRedirect`
filter — no `Middleware` CRD is rendered.

```yaml
gatewayAPI:
  enabled: true
  gateway:
    name: foglifter-gateway
    namespace: foglifter
  httpRoute:
    enabled: true
ingress:
  enabled: false
```

Requires the cluster to have the `gateway.networking.k8s.io` CRDs
installed and a matching `Gateway` resource (the foglifter chart creates
one when `gatewayAPI.enabled: true`).

### Standard Ingress

Renders a `networking.k8s.io/v1 Ingress` plus a Traefik
`traefik.io/v1alpha1 Middleware` for the `/headlamp` → `/headlamp/`
slash redirect, which is not expressible in stock Ingress.

```yaml
gatewayAPI:
  enabled: false
ingress:
  enabled: true
  className: traefik
  traefikMiddleware:
    enabled: true
```

On non-Traefik ingress controllers, set
`ingress.traefikMiddleware.enabled: false`. The slashless URL will then
404 on Headlamp; users must type the trailing slash.

## Auth

The chart creates (via the Headlamp sub-chart) a `ServiceAccount` named
`headlamp-viewer` and binds it to a custom **read-only** `ClusterRole`
(`get/list/watch` on `*`, plus `pods/log`). The default rule set is
intentionally wide so Headlamp's UI populates without 403s; narrow it
via `rbac.rules` for tighter postures.

The upstream Headlamp chart's default `cluster-admin` `ClusterRoleBinding`
is disabled (`headlamp.clusterRoleBinding.create: false`) so the SA
holds only the read-only role.

A long-lived `kubernetes.io/service-account-token` Secret named
`headlamp-viewer-token` is created by default. To use short-lived tokens
minted on demand (`kubectl create token …`) instead, set
`serviceAccount.tokenSecret.create: false`.

## Values reference

| Key                                 | Default             | Notes                                                                                 |
| ----------------------------------- | ------------------- | ------------------------------------------------------------------------------------- |
| `host`                              | `""`                | Public hostname for the ingress/route. Required when ingress or httpRoute is enabled. |
| `path`                              | `/headlamp`         | URL prefix Headlamp serves at. Must match `headlamp.config.baseURL`.                  |
| `tls.enabled`                       | `true`              | Render the TLS block on the Ingress.                                                  |
| `tls.secretName`                    | `foglifter-tls`     | Existing TLS Secret used by the foglifter Gateway / Ingress.                          |
| `gatewayAPI.enabled`                | `true`              | Gateway API profile.                                                                  |
| `gatewayAPI.gateway.name`           | `foglifter-gateway` | Gateway to attach the HTTPRoute to.                                                   |
| `gatewayAPI.gateway.namespace`      | `foglifter`         | Gateway namespace.                                                                    |
| `gatewayAPI.httpRoute.enabled`      | `true`              | Render the HTTPRoute resource.                                                        |
| `ingress.enabled`                   | `false`             | Standard Ingress profile (mutually exclusive with the gatewayAPI profile).            |
| `ingress.className`                 | `traefik`           | `ingressClassName`.                                                                   |
| `ingress.traefikMiddleware.enabled` | `true`              | Render the slash-redirect Middleware + annotation. Disable on non-Traefik clusters.   |
| `rbac.create`                       | `true`              | Render the ClusterRole + ClusterRoleBinding.                                          |
| `rbac.rules`                        | `[]`                | Override the default read-only rule set.                                              |
| `serviceAccount.tokenSecret.create` | `true`              | Render the long-lived SA token Secret.                                                |
| `headlamp.*`                        | various             | Forwarded to the Headlamp sub-chart.                                                  |
| `kube-prometheus-stack.*`           | various             | Forwarded to the kube-prometheus-stack sub-chart.                                     |

## Gotchas

- **`fullnameOverride` is load-bearing.** `kube-prometheus-stack` is
  installed as a dependency, so by default its resources are prefixed
  with the parent release name
  (`<release>-kube-prometheus-stack-prometheus`). The chart pins
  `kube-prometheus-stack.fullnameOverride: kube-prometheus-stack` so the
  in-cluster Prometheus URL is stable at
  `http://kube-prometheus-stack-prometheus.<namespace>.svc.cluster.local:9090`
  regardless of release name.

- **Ephemeral Prometheus data.** No `storageSpec` is set, so Prometheus
  uses an `emptyDir` and loses metrics on every pod restart. Retention
  is 24h to match. Add a `storageSpec` if longer history matters.

- **kube-prometheus-stack CRDs survive `helm uninstall`.** Helm 3 does
  not remove CRDs on chart uninstall by design. To clean them up:

  ```sh
  kubectl get crd -o name | grep -E '(monitoring\.coreos\.com)$' \
    | xargs -r kubectl delete
  ```

  Only run this if no other component on the cluster uses the
  `monitoring.coreos.com` CRDs.

# FogLifter® Helm Chart

## Prerequisites

- Kubernetes cluster (version 1.30+)
  - The cluster must have a default storage class configured for dynamic
    persistent volume provisioning
  - The cluster should optionally be configured to provision load balancers
    for LoadBalancer type services to enable external access to the FogLifter® UI
- Helm 3.0+
- Access to a container registry for FogLifter® images (credentials required)
  - This will typically be shared as a file named `foglifter-pullsecret.yaml`
- `kubectl` configured to access the target cluster

## Installation Guide

### Step 1: Add the FogLifter® Helm Repository

Add the FogLifter® Helm chart repository:

```bash
helm repo add foglifter https://vso-inc.github.io/foglifter-helm
helm repo update
```

### Step 2: Install the required Kubernetes secrets

Create the `foglifter` namespace:

```bash
kubectl create namespace foglifter
```

Apply the FogLifter® image-pull secret:

```bash
kubectl apply -f foglifter-pullsecret.yaml
```

Generate required authentication secrets:

```bash
helm template foglifter foglifter/foglifter \
  --namespace foglifter \
  --set apiSecret.create=true \
  --set createMongoSecret=true \
  --show-only templates/apisecret.yaml \
  --show-only templates/mongosecret.yaml
| kubectl apply -f -
```

### Step 3: Install FogLifter®

Install the FogLifter® Helm chart:

```bash
helm upgrade --install foglifter foglifter/foglifter \
  --namespace foglifter
```

(Optional) To customize the installation, download and modify the values file:

```bash
helm show values foglifter/foglifter > values.yaml
# Edit values.yaml as needed
helm upgrade --install foglifter foglifter/foglifter \
  --namespace foglifter \
  --create-namespace \
  --values values.yaml
```

### Step 4: Verify Installation

Check the deployment status:

```bash
kubectl get pods -n foglifter
kubectl get services -n foglifter
```

(Optional) the deployment status can be monitored with `watch`:

```bash
watch kubectl get pods -n foglifter
```

Wait for all pods to reach `Running` state.

## Accessing FogLifter®

Retrieve the service endpoint:

```bash
kubectl get svc -n foglifter foglifter-traefik
```

If the cluster is configured to provision load balancers for LoadBalancer type
services, the external IP/DNS will be shown in the output.

Navigate to this address in a web browser to access the FogLifter® UI.

## Troubleshooting

View logs for a specific pod:

```bash
kubectl get pods -n foglifter
kubectl logs <pod-name> -n foglifter
```

Check Helm release status:

```bash
helm status foglifter -n foglifter
```

## Uninstalling

To uninstall FogLifter®:

```bash
helm uninstall foglifter -n foglifter
```

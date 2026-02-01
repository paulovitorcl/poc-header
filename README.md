# Header Route POC

[![Kind](https://img.shields.io/badge/Kind-v0.20+-blue.svg)](https://kind.sigs.k8s.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.28+-blue.svg)](https://kubernetes.io/)

Complete proof-of-concept for header-based routing in Kubernetes using a custom controller and Envoy proxy.

## 🎯 What This POC Demonstrates

This POC shows how to route HTTP requests to different microservices based on custom headers:

```
┌─────────────┐    X-App: A     ┌─────────────┐
│   Client    │ ───────────────▶│   App A     │
└─────────────┘                 └─────────────┘
       │
       │         X-App: B       ┌─────────────┐
       │ ───────────────────────▶│   App B     │
       │                        └─────────────┘
       │
       │       X-Tenant: acme   ┌─────────────┐
       │ ───────────────────────▶│   App A     │
       │                        └─────────────┘
       │
       │        (no header)     ┌─────────────┐
       └───────────────────────▶│  Default    │
                                │  Backend    │
                                │   (404)     │
                                └─────────────┘
```

## 📦 Repository Structure

```
header-route-poc/
├── README.md                    # This file
├── cluster/
│   └── kind.yaml                # Kind cluster configuration
├── manifests/
│   ├── namespace.yaml           # POC namespace
│   ├── apps/
│   │   ├── app-a.yaml           # Backend microservice A
│   │   ├── app-b.yaml           # Backend microservice B
│   │   ├── app-c.yaml           # Backend microservice C
│   │   └── default-backend.yaml # Fallback service (404)
│   ├── envoy/
│   │   ├── envoy-config.yaml    # Initial Envoy configuration
│   │   └── envoy-deployment.yaml# Envoy proxy deployment
│   ├── controller/
│   │   ├── crd.yaml             # HeaderRoute CRD
│   │   ├── rbac.yaml            # Controller RBAC
│   │   └── deployment.yaml      # Controller deployment
│   └── routes/
│       ├── route-app-a.yaml     # Route for X-App: A
│       ├── route-app-b.yaml     # Route for X-App: B
│       └── route-tenants.yaml   # Multi-tenant routes
├── scripts/
│   ├── setup.sh                 # Automated setup
│   ├── cleanup.sh               # Cleanup script
│   └── build-local.sh           # Build controller locally
└── test/
    └── test.sh                  # Automated tests
```

## 🚀 Quick Start

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

### Option 1: Automated Setup (Recommended)

```bash
# Clone this repository
git clone https://github.com/seu-user/header-route-poc.git
cd header-route-poc

# Make scripts executable
chmod +x scripts/*.sh test/*.sh

# Run setup
./scripts/setup.sh
```

### Option 2: Manual Setup

#### 1. Create Kind Cluster

```bash
kind create cluster --config cluster/kind.yaml
```

#### 2. Deploy Namespace and CRD

```bash
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/controller/crd.yaml
kubectl apply -f manifests/controller/rbac.yaml
```

#### 3. Deploy Backend Applications

```bash
kubectl apply -f manifests/apps/

# Wait for apps to be ready
kubectl wait --for=condition=available --timeout=120s \
    deployment/app-a deployment/app-b deployment/app-c deployment/default-backend \
    -n poc
```

#### 4. Deploy Envoy

```bash
kubectl apply -f manifests/envoy/

# Wait for Envoy
kubectl wait --for=condition=available --timeout=120s deployment/envoy -n poc
```

#### 5. Deploy Controller

```bash
kubectl apply -f manifests/controller/deployment.yaml

# Wait for controller
kubectl wait --for=condition=available --timeout=120s \
    deployment/header-route-controller -n poc
```

#### 6. Create Routes

```bash
kubectl apply -f manifests/routes/

# Verify routes
kubectl get headerroutes -n poc
```

#### 7. Restart Envoy to Apply Config

```bash
kubectl rollout restart deployment/envoy -n poc
```

## 🧪 Testing

### Start Port Forward

```bash
kubectl port-forward -n poc svc/envoy 8080:8080
```

### Test Routes

```bash
# Route to App A
curl -H "X-App: A" http://localhost:8080
# Response: {"app": "A", "message": "Hello from App A!", ...}

# Route to App B
curl -H "X-App: B" http://localhost:8080
# Response: {"app": "B", "message": "Hello from App B!", ...}

# Route to App C (via tenant header)
curl -H "X-Tenant: initech" http://localhost:8080
# Response: {"app": "C", "message": "Hello from App C!", ...}

# Default backend (no matching header)
curl http://localhost:8080
# Response: {"error": "not_found", "message": "No matching route found...", ...}

# Default backend (unknown header value)
curl -H "X-App: UNKNOWN" http://localhost:8080
# Response: {"error": "not_found", ...}
```

### Run Automated Tests

```bash
./test/test.sh
```

## 📋 Available Routes

| Header | Value | Backend | Priority |
|--------|-------|---------|----------|
| X-App | A | app-a | 100 |
| X-App | B | app-b | 100 |
| X-Tenant | acme | app-a | 50 |
| X-Tenant | globex | app-b | 50 |
| X-Tenant | initech | app-c | 50 |
| (none) | - | default-backend | - |

## 🔧 Create New Routes

```yaml
apiVersion: routing.example.com/v1alpha1
kind: HeaderRoute
metadata:
  name: route-my-app
  namespace: poc
spec:
  headerName: X-App
  headerValue: MyApp
  backend:
    name: my-service
    port: 80
  priority: 100
```

Apply with:
```bash
kubectl apply -f my-route.yaml

# Restart Envoy to apply
kubectl rollout restart deployment/envoy -n poc
```

## 🐛 Debugging

### Check Controller Logs

```bash
kubectl logs -f deployment/header-route-controller -n poc
```

### Check Envoy Config

```bash
# View current configuration
kubectl get configmap envoy-config -n poc -o jsonpath='{.data.envoy\.json}' | jq .

# Check Envoy admin
kubectl port-forward -n poc svc/envoy 9901:9901
curl http://localhost:9901/config_dump
```

### Check Route Status

```bash
kubectl get headerroutes -n poc
kubectl describe headerroute route-app-a -n poc
```

### Common Issues

**Controller not starting:**
- Check image is accessible: `kubectl describe deployment/header-route-controller -n poc`
- Check RBAC: `kubectl auth can-i list headerroutes --as=system:serviceaccount:poc:header-route-controller`

**Routes not working:**
- Verify ConfigMap updated: `kubectl get configmap envoy-config -n poc -o yaml`
- Restart Envoy: `kubectl rollout restart deployment/envoy -n poc`
- Check Envoy logs: `kubectl logs deployment/envoy -n poc`

## 🧹 Cleanup

```bash
# Remove just the routes
kubectl delete -f manifests/routes/

# Delete entire cluster
./scripts/cleanup.sh
# or
kind delete cluster --name header-route-poc
```

## 🔗 Related

- [header-route-controller](https://github.com/seu-user/header-route-controller) - The controller source code
- [Envoy Proxy](https://www.envoyproxy.io/) - The proxy used for routing
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) - Standard API for similar functionality

## 📈 Next Steps

After validating this POC, consider:

1. **Production Readiness**
   - Add webhook validation
   - Implement leader election
   - Add metrics/monitoring

2. **Feature Enhancements**
   - Multiple header matching (AND/OR)
   - Regex header matching
   - Path-based routing
   - Weight-based routing

3. **Gateway API Integration**
   - Migrate to HTTPRoute
   - Use standard Gateway API resources

## 📄 License

Apache License 2.0

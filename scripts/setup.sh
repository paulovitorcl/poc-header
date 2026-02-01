#!/bin/bash

# Header Route POC - Setup Script
# This script sets up the complete POC environment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLUSTER_NAME="header-route-poc"
CONTROLLER_IMAGE="${CONTROLLER_IMAGE:-ghcr.io/seu-user/header-route-controller:latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(dirname "$SCRIPT_DIR")"

print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Step $1: $2${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_step "0" "Checking Prerequisites"
    
    local missing=()
    
    if ! command -v kind &> /dev/null; then
        missing+=("kind")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing+=("kubectl")
    fi
    
    if ! command -v docker &> /dev/null; then
        missing+=("docker")
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing[*]}"
        echo "Please install the missing tools and try again."
        exit 1
    fi
    
    print_success "All prerequisites are installed"
}

# Create Kind cluster
create_cluster() {
    print_step "1" "Creating Kind Cluster"
    
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        print_warning "Cluster '$CLUSTER_NAME' already exists"
        read -p "Delete and recreate? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kind delete cluster --name "$CLUSTER_NAME"
        else
            print_success "Using existing cluster"
            return
        fi
    fi
    
    kind create cluster --config "$POC_DIR/cluster/kind.yaml"
    print_success "Cluster created successfully"
}

# Deploy namespace
deploy_namespace() {
    print_step "2" "Creating Namespace"
    kubectl apply -f "$POC_DIR/manifests/namespace.yaml"
    print_success "Namespace 'poc' created"
}

# Deploy CRD and RBAC
deploy_controller_prereqs() {
    print_step "3" "Deploying CRD and RBAC"
    
    kubectl apply -f "$POC_DIR/manifests/controller/crd.yaml"
    print_success "CRD deployed"
    
    kubectl apply -f "$POC_DIR/manifests/controller/rbac.yaml"
    print_success "RBAC deployed"
}

# Deploy applications
deploy_apps() {
    print_step "4" "Deploying Backend Applications"
    
    kubectl apply -f "$POC_DIR/manifests/apps/"
    
    echo "Waiting for apps to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/app-a -n poc
    kubectl wait --for=condition=available --timeout=120s deployment/app-b -n poc
    kubectl wait --for=condition=available --timeout=120s deployment/app-c -n poc
    kubectl wait --for=condition=available --timeout=120s deployment/default-backend -n poc
    
    print_success "All backend applications deployed and ready"
}

# Deploy Envoy
deploy_envoy() {
    print_step "5" "Deploying Envoy Proxy"
    
    kubectl apply -f "$POC_DIR/manifests/envoy/"
    
    echo "Waiting for Envoy to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/envoy -n poc
    
    print_success "Envoy deployed and ready"
}

# Deploy controller
deploy_controller() {
    print_step "6" "Deploying Header Route Controller"
    
    # Update image in deployment if specified
    if [ -n "$CONTROLLER_IMAGE" ]; then
        sed "s|image: ghcr.io/seu-user/header-route-controller:latest|image: $CONTROLLER_IMAGE|g" \
            "$POC_DIR/manifests/controller/deployment.yaml" | kubectl apply -f -
    else
        kubectl apply -f "$POC_DIR/manifests/controller/deployment.yaml"
    fi
    
    echo "Waiting for controller to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/header-route-controller -n poc || {
        print_warning "Controller not ready yet. Check logs with:"
        echo "  kubectl logs -f deployment/header-route-controller -n poc"
    }
    
    print_success "Controller deployed"
}

# Create routes
create_routes() {
    print_step "7" "Creating HeaderRoutes"
    
    kubectl apply -f "$POC_DIR/manifests/routes/"
    
    echo "Waiting for routes to be processed..."
    sleep 5
    
    kubectl get headerroutes -n poc
    
    print_success "Routes created"
}

# Restart Envoy to pick up new config
restart_envoy() {
    print_step "8" "Restarting Envoy to Apply Config"
    
    kubectl rollout restart deployment/envoy -n poc
    kubectl wait --for=condition=available --timeout=120s deployment/envoy -n poc
    
    print_success "Envoy restarted with new configuration"
}

# Print final instructions
print_instructions() {
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Setup Complete! 🎉                               ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${BLUE}Quick Test Commands:${NC}"
    echo ""
    echo "# Start port-forward (run in separate terminal):"
    echo "  kubectl port-forward -n poc svc/envoy 8080:8080"
    echo ""
    echo "# Or use NodePort (already exposed on localhost:8080 via Kind):"
    echo "  curl http://localhost:8080"
    echo ""
    echo "# Test routes:"
    echo "  curl -H 'X-App: A' http://localhost:8080"
    echo "  curl -H 'X-App: B' http://localhost:8080"
    echo "  curl -H 'X-Tenant: acme' http://localhost:8080"
    echo "  curl -H 'X-Tenant: globex' http://localhost:8080"
    echo "  curl -H 'X-Tenant: initech' http://localhost:8080"
    echo "  curl http://localhost:8080  # Default backend (404)"
    echo ""
    echo "# Run automated tests:"
    echo "  $POC_DIR/test/test.sh"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "  kubectl get headerroutes -n poc"
    echo "  kubectl describe headerroute route-app-a -n poc"
    echo "  kubectl logs -f deployment/header-route-controller -n poc"
    echo "  kubectl get configmap envoy-config -n poc -o yaml"
    echo ""
    echo -e "${BLUE}Cleanup:${NC}"
    echo "  kind delete cluster --name $CLUSTER_NAME"
}

# Main
main() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         Header Route POC - Setup Script                   ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_prerequisites
    create_cluster
    deploy_namespace
    deploy_controller_prereqs
    deploy_apps
    deploy_envoy
    deploy_controller
    create_routes
    restart_envoy
    print_instructions
}

main "$@"

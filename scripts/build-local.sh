#!/bin/bash

# Build the controller locally and load into Kind
# Useful for development and testing

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CLUSTER_NAME="header-route-poc"
IMAGE_NAME="header-route-controller:local"
CONTROLLER_REPO="${CONTROLLER_REPO:-../header-route-controller}"

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║      Build and Load Controller to Kind                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if controller repo exists
if [ ! -d "$CONTROLLER_REPO" ]; then
    echo -e "${RED}Controller repository not found at: $CONTROLLER_REPO${NC}"
    echo "Please clone the header-route-controller repository first:"
    echo "  git clone https://github.com/seu-user/header-route-controller.git $CONTROLLER_REPO"
    exit 1
fi

# Check if Kind cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${RED}Kind cluster '$CLUSTER_NAME' not found.${NC}"
    echo "Please run setup.sh first."
    exit 1
fi

# Build the image
echo -e "\n${BLUE}Building controller image...${NC}"
cd "$CONTROLLER_REPO"
docker build -t "$IMAGE_NAME" .

# Load into Kind
echo -e "\n${BLUE}Loading image into Kind cluster...${NC}"
kind load docker-image "$IMAGE_NAME" --name "$CLUSTER_NAME"

# Update deployment to use local image
echo -e "\n${BLUE}Updating deployment...${NC}"
kubectl set image deployment/header-route-controller \
    controller="$IMAGE_NAME" \
    -n poc

# Restart the deployment
kubectl rollout restart deployment/header-route-controller -n poc
kubectl rollout status deployment/header-route-controller -n poc

echo -e "\n${GREEN}✓ Controller built and deployed successfully!${NC}"
echo ""
echo "View logs with:"
echo "  kubectl logs -f deployment/header-route-controller -n poc"

#!/bin/bash

# Header Route POC - Cleanup Script
# This script removes the POC environment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CLUSTER_NAME="header-route-poc"

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         Header Route POC - Cleanup Script                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${YELLOW}Cluster '$CLUSTER_NAME' does not exist.${NC}"
    exit 0
fi

# Confirm deletion
echo -e "${YELLOW}This will delete the Kind cluster '$CLUSTER_NAME' and all its resources.${NC}"
read -p "Are you sure? (y/N) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Delete cluster
echo -e "\n${BLUE}Deleting cluster...${NC}"
kind delete cluster --name "$CLUSTER_NAME"

echo -e "\n${GREEN}✓ Cleanup complete!${NC}"

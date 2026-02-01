#!/bin/bash

# Header Route POC - Test Script
# This script tests the header-based routing functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVOY_URL="${ENVOY_URL:-http://localhost:8080}"
TIMEOUT=5

# Counters
PASSED=0
FAILED=0

# Print functions
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

print_test() {
    echo -e "${YELLOW}▶ TEST: $1${NC}"
}

print_pass() {
    echo -e "${GREEN}✓ PASS: $1${NC}"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}✗ FAIL: $1${NC}"
    echo -e "${RED}  Expected: $2${NC}"
    echo -e "${RED}  Got: $3${NC}"
    ((FAILED++))
}

# Test function
test_route() {
    local description="$1"
    local header="$2"
    local expected_app="$3"
    
    print_test "$description"
    
    if [ -n "$header" ]; then
        response=$(curl -s -m $TIMEOUT -H "$header" "$ENVOY_URL" 2>/dev/null || echo "CURL_ERROR")
    else
        response=$(curl -s -m $TIMEOUT "$ENVOY_URL" 2>/dev/null || echo "CURL_ERROR")
    fi
    
    if [ "$response" = "CURL_ERROR" ]; then
        print_fail "$description" "$expected_app" "Connection failed"
        return
    fi
    
    # Extract app name from JSON response
    actual_app=$(echo "$response" | grep -o '"app"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    
    # For default backend, check for error
    if [ "$expected_app" = "default-backend" ]; then
        if echo "$response" | grep -q '"error"'; then
            print_pass "$description"
            echo "  Response: $(echo "$response" | head -c 100)..."
        else
            print_fail "$description" "error response from default-backend" "$response"
        fi
    elif [ "$actual_app" = "$expected_app" ]; then
        print_pass "$description"
        echo "  Response: $(echo "$response" | head -c 100)..."
    else
        print_fail "$description" "$expected_app" "$actual_app (full: $response)"
    fi
}

# Check if Envoy is accessible
check_envoy() {
    print_header "Checking Envoy Connectivity"
    
    if curl -s -m $TIMEOUT "$ENVOY_URL" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Envoy is accessible at $ENVOY_URL${NC}"
        return 0
    else
        echo -e "${RED}✗ Cannot connect to Envoy at $ENVOY_URL${NC}"
        echo -e "${YELLOW}Hint: Make sure you have port-forwarding running:${NC}"
        echo -e "${YELLOW}  kubectl port-forward -n poc svc/envoy 8080:8080${NC}"
        return 1
    fi
}

# Run tests
run_tests() {
    print_header "Running Header Route Tests"
    
    # X-App header tests
    echo -e "\n${BLUE}── X-App Header Tests ──${NC}\n"
    
    test_route "Route to App A with X-App: A" "X-App: A" "A"
    test_route "Route to App B with X-App: B" "X-App: B" "B"
    
    # X-Tenant header tests
    echo -e "\n${BLUE}── X-Tenant Header Tests ──${NC}\n"
    
    test_route "Route to App A with X-Tenant: acme" "X-Tenant: acme" "A"
    test_route "Route to App B with X-Tenant: globex" "X-Tenant: globex" "B"
    test_route "Route to App C with X-Tenant: initech" "X-Tenant: initech" "C"
    
    # Default backend tests
    echo -e "\n${BLUE}── Default Backend Tests ──${NC}\n"
    
    test_route "Route to default backend (no header)" "" "default-backend"
    test_route "Route to default backend (unknown header value)" "X-App: UNKNOWN" "default-backend"
    test_route "Route to default backend (wrong header name)" "X-Wrong: A" "default-backend"
}

# Print summary
print_summary() {
    print_header "Test Summary"
    
    echo -e "Total tests: $((PASSED + FAILED))"
    echo -e "${GREEN}Passed: $PASSED${NC}"
    echo -e "${RED}Failed: $FAILED${NC}"
    
    if [ $FAILED -eq 0 ]; then
        echo -e "\n${GREEN}🎉 All tests passed!${NC}"
        return 0
    else
        echo -e "\n${RED}❌ Some tests failed${NC}"
        return 1
    fi
}

# Main
main() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║           Header Route POC - Test Suite                   ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    if ! check_envoy; then
        exit 1
    fi
    
    run_tests
    print_summary
}

main "$@"

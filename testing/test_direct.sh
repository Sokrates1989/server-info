#!/bin/bash

echo "=== Testing current system_info.sh directly ==="

echo "Current directory: $(pwd)"
echo "Script location: $(which server-info)"
echo "Script path: $(readlink -f $(which server-info))"

echo "Testing the actual update detection from the script..."
# Extract just the update detection part
sudo apt-get update -qq
upgradable_count=$(apt list --upgradable 2>/dev/null | grep -c '/upgradable' || echo "0")
echo "Direct command result: '$upgradable_count'"

# Test if the issue is with the variable assignment
echo "Testing variable assignment..."
test_var=$(apt list --upgradable 2>/dev/null | grep -c '/upgradable' || echo "0")
echo "Variable test_var: '$test_var'"

# Test the cleanup step
clean_var=$(echo "$test_var" | tr -d '\n\r' | grep -o '[0-9]*' | head -1)
echo "After cleanup: '$clean_var'"

echo "=== END DIRECT TEST ==="

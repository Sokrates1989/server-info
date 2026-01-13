#!/bin/bash

echo "=== Testing system_info.sh update logic ==="

# Simulate the exact logic from system_info.sh
echo "1. Running sudo apt-get update -qq..."
sudo apt-get update -qq

echo "2. Running: upgradable_count=\$(apt list --upgradable 2>/dev/null | grep -c '/upgradable' || echo \"0\")"
upgradable_count=$(apt list --upgradable 2>/dev/null | grep -c '/upgradable' || echo "0")
echo "Raw result: '$upgradable_count'"

echo "3. Running: upgradable_count=\$(echo \"\$upgradable_count\" | tr -d '\n\r' | grep -o '[0-9]*' | head -1)"
upgradable_count=$(echo "$upgradable_count" | tr -d '\n\r' | grep -o '[0-9]*' | head -1)
echo "Cleaned result: '$upgradable_count'"

echo "4. Testing condition: [ -n \"\$upgradable_count\" ] && [ \"\$upgradable_count\" -gt 0 ]"
if [ -n "$upgradable_count" ] && [ "$upgradable_count" -gt 0 ]; then
    echo "Condition: TRUE - Updates available"
    amount_of_available_updates=$upgradable_count
    updates_available_output="~$amount_of_available_updates updates available"
else
    echo "Condition: FALSE - No updates"
    updates_available_output="no updates available"
    amount_of_available_updates=0
fi

echo "Final result:"
echo "amount_of_available_updates: $amount_of_available_updates"
echo "updates_available_output: $updates_available_output"

echo "=== END TEST ==="

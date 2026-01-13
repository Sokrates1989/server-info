#!/bin/bash

echo "=== DEBUG: Testing update detection ==="

echo "1. Running apt-get update..."
sudo apt-get update -qq

echo "2. Running apt list --upgradable directly:"
apt list --upgradable 2>/dev/null | head -5

echo "3. Counting with grep -c '/upgradable':"
count1=$(apt list --upgradable 2>/dev/null | grep -c '/upgradable' || echo "0")
echo "Result: $count1"

echo "4. Alternative counting method:"
count2=$(apt list --upgradable 2>/dev/null | grep '/upgradable' | wc -l)
echo "Result: $count2"

echo "5. Another method - counting lines that don't start with 'Listing':"
count3=$(apt list --upgradable 2>/dev/null | grep -v '^Listing' | grep '/upgradable' | wc -l)
echo "Result: $count3"

echo "6. Raw output of apt list --upgradable (first 10 lines):"
apt list --upgradable 2>/dev/null | head -10

echo "=== END DEBUG ==="

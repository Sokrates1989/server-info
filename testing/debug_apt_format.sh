#!/bin/bash

echo "=== DEBUG: Checking actual apt output format ==="

echo "1. Raw apt list --upgradable output (first 5 lines):"
apt list --upgradable 2>/dev/null | head -5

echo ""
echo "2. Looking for '/upgradable' pattern:"
apt list --upgradable 2>/dev/null | grep '/upgradable' | head -3

echo ""
echo "3. Looking for 'upgradable from' pattern:"
apt list --upgradable 2>/dev/null | grep 'upgradable from' | head -3

echo ""
echo "4. Looking for any line with 'upgradable':"
apt list --upgradable 2>/dev/null | grep 'upgradable' | head -3

echo ""
echo "5. Counting total lines (excluding 'Listing...'):"
apt list --upgradable 2>/dev/null | grep -v '^Listing' | wc -l

echo ""
echo "6. Counting lines with 'upgradable from':"
apt list --upgradable 2>/dev/null | grep 'upgradable from' | wc -l

echo "=== END DEBUG ==="

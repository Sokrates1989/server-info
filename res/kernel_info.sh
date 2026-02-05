#!/bin/bash

# Kernel information script for server-info
# Usage: kernel_info.sh [-t tab_space]

# Default tab space
output_tab_space=28

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -t)
            shift
            output_tab_space="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-t tab_space]"
            exit 1
            ;;
    esac
done

# Function to check kernel version and available updates
check_kernel_info() {
    local output_tab_space=${1:-28}
    
    # Get current kernel version
    local current_kernel=$(uname -r)
    local current_kernel_full=$(uname -sr)
    
    # Get available kernel packages
    local available_kernels=$(apt-cache policy linux-image-generic 2>/dev/null | grep -A 3 "linux-image-generic:")
    local latest_generic=""
    
    if [ -n "$available_kernels" ]; then
        latest_generic=$(echo "$available_kernels" | grep -E "^\s*\*\*\*" -A 1 | tail -1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+-[0-9]+" | head -1)
    fi
    
    # Check for kernel-specific updates
    local kernel_updates=$(apt list --upgradable 2>/dev/null | grep -E "linux-(image|headers|generic)" | wc -l)
    
    # Display current kernel info
    printf "%-${output_tab_space}s: %s\n" "Current Kernel" "$current_kernel_full"
    
    if [ -n "$latest_generic" ] && [ "$latest_generic" != "$(echo $current_kernel | grep -oE "[0-9]+\.[0-9]+\.[0-9]+-[0-9]+")" ]; then
        printf "%-${output_tab_space}s: %s\n" "Latest Available" "$latest_generic"
        
        # Check if current kernel is significantly outdated
        local current_version=$(echo $current_kernel | grep -oE "[0-9]+\.[0-9]+\.[0-9]+-[0-9]+" | head -1)
        local latest_version=$(echo $latest_generic | grep -oE "[0-9]+\.[0-9]+\.[0-9]+-[0-9]+" | head -1)
        
        if [ "$kernel_updates" -gt 0 ]; then
            printf "%-${output_tab_space}s: %s\n" "Kernel Updates" "Yes ($kernel_updates packages available)"
            printf "%-${output_tab_space}s: %s\n" "Update Command" "sudo apt upgrade linux-image-generic linux-headers-generic linux-generic"
        else
            printf "%-${output_tab_space}s: %s\n" "Kernel Updates" "No kernel-specific updates"
        fi
        
        # Version comparison logic
        if [ -n "$current_version" ] && [ -n "$latest_version" ]; then
            local current_major=$(echo $current_version | cut -d. -f1)
            local current_minor=$(echo $current_version | cut -d. -f2)
            local latest_major=$(echo $latest_version | cut -d. -f1)
            local latest_minor=$(echo $latest_version | cut -d. -f2)
            
            if [ "$current_major" -lt "$latest_major" ] || ([ "$current_major" -eq "$latest_major" ] && [ "$current_minor" -lt "$latest_minor" ]); then
                printf "%-${output_tab_space}s: %s\n" "Status" "⚠️  Major kernel update available"
            else
                printf "%-${output_tab_space}s: %s\n" "Status" "✅ Minor/security update available"
            fi
        fi
    else
        printf "%-${output_tab_space}s: %s\n" "Kernel Status" "✅ Up to date"
    fi
    
    # Show kernel security info if available
    local security_info=$(apt-cache show linux-image-generic 2>/dev/null | grep -i "security\|cve" | wc -l)
    if [ "$security_info" -gt 0 ]; then
        printf "%-${output_tab_space}s: %s\n" "Security Notes" "Check changelog for security fixes"
    fi
}

# Run the function
check_kernel_info $output_tab_space

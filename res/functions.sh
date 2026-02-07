#!/bin/bash

## Global functions ##

# Function to print formatted output.
print_info() {
    while [ "$#" -gt 0 ]; do
        local text=$1
        local output_tab_space=$2
        printf "%-${output_tab_space}s" "$text"
        shift 2
        if [ "$#" -gt 0 ]; then
            printf "  | "
        fi
    done
    echo ""  # Print a newline at the end
}

# Loading animation.
loading_animation() {

    # Speed parameter with default value.
    local speed="normal"
    if [ -n "$1" ]; then
        speed=$1
    fi

    # Prepare default values based on speed.
    local duration=3
    local delay=0.1
    if [ "$speed" == "fast" ]; then
        delay=0.05
        duration=0
    elif [ "$speed" == "normal" ]; then
        delay=0.2
        duration=3
    elif [ "$speed" == "slow" ]; then
        delay=0.4
        duration=5
    fi

    # Show animation.
    local spinstr='|/-\'
    local temp
    SECONDS=0
    while (( SECONDS < duration )); do
        temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}


# Function to show a loading dots animation.
show_loading_dots() {

    # Speed parameter with default value.
    local speed="normal"
    if [ -n "$1" ]; then
        speed=$1
    fi

    # Prepare default values based on speed.
    local duration=3
    local delay=0.5
    if [ "$speed" == "fast" ]; then
        delay=0.05
        duration=0
    elif [ "$speed" == "normal" ]; then
        delay=0.2
        duration=3
    elif [ "$speed" == "slow" ]; then
        delay=0.4
        duration=5
    fi

    # Show animation.
    SECONDS=0
    while (( SECONDS < duration )); do
        printf "."
        sleep $delay
        printf "\b\b  \b\b"
        sleep $delay
        printf ".."
        sleep $delay
        printf "\b\b\b   \b\b\b"
        sleep $delay
        printf "..."
        sleep $delay
        printf "\b\b\b    \b\b\b\b"
        sleep $delay
    done
    printf "    \b\b\b\b"
}




# Function to convert seconds to a human-readable format.
convert_seconds_to_human_readable() {
    # Parameters of this function.
    local seconds="$1"

    # Conversion.
    local days=$((seconds / 86400))
    local hours=$(( (seconds % 86400) / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    local seconds=$((seconds % 60))

    # Concatenate result.
    local result=""
    if [ "$days" -gt 0 ]; then
        result="${days}d "
    fi
    result="${result}${hours}h ${minutes}m ${seconds}s"

    # Return result.
    echo -e "$result"
}


# Function to find the location of swarm-info/get_info.sh
find_swarm_info_script() {
    local search_paths=("/tools" "/usr/local")
    for path in "${search_paths[@]}"; do
        if [ -f "$path/swarm-info/get_info.sh" ]; then
            echo "$path/swarm-info/get_info.sh"
            return 0
        fi
        found_script=$(find "$path" -type f -name "get_info.sh" -path "*/swarm-info/*" 2>/dev/null)
        if [ -n "$found_script" ]; then
            echo "$found_script"
            return 0
        fi
    done

    # If not found in /tools or /usr/local, search the entire filesystem
    found_script=$(find / -type f -name "get_info.sh" -path "*/swarm-info/*" 2>/dev/null)
    if [ -n "$found_script" ]; then
        echo "$found_script"
        return 0
    fi

    return 1
}


# Get the number of nodes in the Docker Swarm.
#
# Returns:
#     Number of nodes (echoed to stdout), or 0 if not in swarm
get_swarm_node_count() {
    if command -v docker &> /dev/null && docker info 2>/dev/null | grep -q "Swarm: active"; then
        docker node ls --format '{{.ID}}' 2>/dev/null | wc -l | tr -d ' '
    else
        echo "0"
    fi
}

# Check if this is a single-node Docker Swarm.
#
# Returns:
#     0 if single-node swarm, 1 otherwise
is_single_node_swarm() {
    local node_count
    node_count=$(get_swarm_node_count)
    [ "$node_count" -eq 1 ]
}

# Function to check kernel version and available updates.
#
# Uses apt-cache policy to compare Installed vs Candidate versions of
# linux-image-generic. Displays current vs available version and
# points the user to the safe reboot workflow for Docker Swarm
# or full-upgrade for non-swarm systems.
#
# Args:
#     $1 (int, optional): Tab space for printf alignment. Default: 28.
check_kernel_info() {
    local output_tab_space=${1:-28}

    # Get running kernel version
    local current_kernel=$(uname -r)
    local current_kernel_full=$(uname -sr)

    # Extract Installed and Candidate versions from apt-cache policy
    local policy_output=$(apt-cache policy linux-image-generic 2>/dev/null)
    local installed_version=""
    local candidate_version=""

    if [ -n "$policy_output" ]; then
        installed_version=$(echo "$policy_output" | grep "Installed:" | awk '{print $2}')
        candidate_version=$(echo "$policy_output" | grep "Candidate:" | awk '{print $2}')
    fi

    # Display current kernel info
    printf "%-${output_tab_space}s: %s\n" "Current Kernel" "$current_kernel_full"

    # Determine if an update is available AND installable
    local has_update=false
    if [ -n "$installed_version" ] && [ -n "$candidate_version" ] && [ "$installed_version" != "$candidate_version" ]; then
        # Verify the candidate version is actually installable
        if apt-get install --dry-run linux-generic 2>/dev/null | grep -q "Inst linux-generic"; then
            has_update=true
        fi
    fi

    if [ "$has_update" = true ]; then
        printf "%-${output_tab_space}s: %s\n" "Kernel Update" "⚠️  $installed_version → $candidate_version"

        # Detect if Docker Swarm is active to show appropriate guidance
        if docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
            printf "%-${output_tab_space}s: %s\n" "Upgrade via" "server-info --safe-reboot"
        else
            printf "%-${output_tab_space}s: %s\n" "Upgrade via" "sudo apt update && sudo apt full-upgrade && sudo reboot"
        fi
    else
        printf "%-${output_tab_space}s: %s\n" "Kernel Status" "✅ Up to date"
    fi
}

# Check if a kernel update is available.
#
# Compares Installed vs Candidate version of linux-image-generic.
#
# Returns:
#     0 if update available, 1 if up to date or unable to determine.
is_kernel_update_available() {
    local policy_output=$(apt-cache policy linux-image-generic 2>/dev/null)
    if [ -z "$policy_output" ]; then
        return 1
    fi
    local installed=$(echo "$policy_output" | grep "Installed:" | awk '{print $2}')
    local candidate=$(echo "$policy_output" | grep "Candidate:" | awk '{print $2}')
    if [ -n "$installed" ] && [ -n "$candidate" ] && [ "$installed" != "$candidate" ]; then
        # Verify the candidate version is actually installable
        if apt-get install --dry-run linux-generic 2>/dev/null | grep -q "Inst linux-generic"; then
            return 0
        fi
    fi
    return 1
}

# Get the installed kernel package version string.
#
# Returns:
#     Prints the version string to stdout (e.g. "6.8.0-94.96").
get_kernel_installed_version() {
    apt-cache policy linux-image-generic 2>/dev/null | grep "Installed:" | awk '{print $2}'
}

# Get the candidate (available) kernel package version string.
#
# Returns:
#     Prints the version string to stdout (e.g. "6.8.0-100.100").
get_kernel_candidate_version() {
    apt-cache policy linux-image-generic 2>/dev/null | grep "Candidate:" | awk '{print $2}'
}

# Calculate a weighted score for how far behind the installed kernel is.
#
# Uses a weighted formula based on semantic version components:
#   Major version diff × 100 (e.g., 6.x → 7.x = 100)
#   Minor version diff × 10  (e.g., 6.8 → 6.9 = 10)
#   ABI diff (only when major.minor match, e.g., 6.8.0-94 → 6.8.0-100 = 6)
#
# Version format: MAJOR.MINOR.PATCH-ABI.UPLOAD (e.g., "6.8.0-94.96")
#
# Examples:
#   6.8.0-94.96 → 6.8.0-100.100 = 6   (ABI diff only)
#   6.8.0-94.96 → 6.9.0-10.10   = 10  (minor version jump)
#   6.8.0-94.96 → 7.0.0-5.5     = 100 (major version jump)
#
# Returns:
#     Prints the weighted score to stdout (e.g. "6"). Returns 0 if up to date.
get_kernel_versions_behind() {
    local policy_output=$(apt-cache policy linux-image-generic 2>/dev/null)
    if [ -z "$policy_output" ]; then
        echo "0"
        return
    fi
    local installed=$(echo "$policy_output" | grep "Installed:" | awk '{print $2}')
    local candidate=$(echo "$policy_output" | grep "Candidate:" | awk '{print $2}')
    if [ -z "$installed" ] || [ -z "$candidate" ] || [ "$installed" = "$candidate" ]; then
        echo "0"
        return
    fi

    # Extract version components: "6.8.0-94.96" → major=6, minor=8, abi=94
    local inst_major=$(echo "$installed" | cut -d'.' -f1)
    local inst_minor=$(echo "$installed" | cut -d'.' -f2)
    local inst_abi=$(echo "$installed" | sed 's/.*-\([0-9]*\)\..*/\1/')

    local cand_major=$(echo "$candidate" | cut -d'.' -f1)
    local cand_minor=$(echo "$candidate" | cut -d'.' -f2)
    local cand_abi=$(echo "$candidate" | sed 's/.*-\([0-9]*\)\..*/\1/')

    # Validate all components are numeric
    for val in "$inst_major" "$inst_minor" "$inst_abi" "$cand_major" "$cand_minor" "$cand_abi"; do
        if ! [ "$val" -eq "$val" ] 2>/dev/null; then
            echo "0"
            return
        fi
    done

    # Calculate weighted score
    local major_diff=$((cand_major - inst_major))
    local minor_diff=$((cand_minor - inst_minor))
    local score=0

    if [ $major_diff -gt 0 ]; then
        # Major version jump: weight × 100 per major + 10 per minor
        score=$((major_diff * 100))
        if [ $minor_diff -gt 0 ]; then
            score=$((score + minor_diff * 10))
        fi
    elif [ $minor_diff -gt 0 ]; then
        # Minor version jump: weight × 10 per minor
        score=$((minor_diff * 10))
    else
        # Same major.minor: use ABI difference
        local abi_diff=$((cand_abi - inst_abi))
        if [ $abi_diff -gt 0 ]; then
            score=$abi_diff
        fi
    fi

    if [ $score -lt 0 ]; then
        score=0
    fi
    echo "$score"
}

# Main function to get restart information and provide instructions if necessary.
get_restart_information() {
    # Function parameter: output option how to format user ouput.
    local output_options=${1:-"long"} # Default value for output_options is "long" if not provided.
    local output_tab_space=${2:-28}  # Default value for output_tab_space is 28 if not provided.

    # Variable declarations and initializations.
    local timestamp=$(date +%s)
    local restart_required_timestamp=""
    local is_swarm_active=false
    local is_single_node=false
    local node_count=0

    # Check swarm status once
    if command -v docker &> /dev/null && docker info 2>/dev/null | grep -q "Swarm: active"; then
        is_swarm_active=true
        node_count=$(get_swarm_node_count)
        if [ "$node_count" -eq 1 ]; then
            is_single_node=true
        fi
    fi

    # Is a system restart required?
    if [ -f /var/run/reboot-required ]; then
        # Determine duration since when restart has been required by the system already, to give user possible insight of urgency of restart.
        restart_required_timestamp=$(stat -c %Y /var/run/reboot-required)
        local time_elapsed=$((timestamp - restart_required_timestamp))
        local time_elapsed_human_readable=$(convert_seconds_to_human_readable "$time_elapsed")

        # Print user info: System needs to be restarted.
        if [ "$output_options" == "short" ]; then
            printf "%-${output_tab_space}s: %s\n" "Restart required" "Yes, since $time_elapsed_human_readable" 
        else
            echo -e "System restart required since $time_elapsed_human_readable"
        fi

        # Check if the server is part of a Docker Swarm.
        if [ "$is_swarm_active" = true ]; then
            local node_name=$(hostname)
            
            # Different instructions based on single-node vs multi-node swarm
            if [ "$is_single_node" = true ]; then
                # Single-node swarm: use safe-reboot workflow
                echo -e "\n🔄 Single-node Swarm detected - Use safe reboot workflow:"
                echo "DO NOT simply reboot. Instead, use the safe reboot command:"
                echo ""
                echo "   server-info --safe-reboot"
                echo ""
                echo "This will:"
                echo "  1. Create a snapshot of all service replica counts"
                echo "  2. Scale down services safely (apps → databases → ingress)"
                if is_kernel_update_available; then
                echo "  3. Offer to install kernel update (recommended)"
                echo "  4. Prompt you to reboot"
                else
                echo "  3. Prompt you to reboot"
                fi
                echo ""
                echo "After reboot, restore services with:"
                echo "   server-info --maintenance-exit"
                echo ""
                echo "For more details: server-info --maintenance-help"
            else
                # Multi-node swarm: use drain approach
                echo -e "\nRestart instructions/advice to decrease downtime of containers and prevent write errors:"
                echo "DO NOT simply reboot. Instead, follow these steps:"
                echo ""
                echo "1. Drain the node (all services/containers will be redeployed onto different nodes):"
                echo "   docker node update --availability drain $node_name"
                echo ""
                echo "2. Watch progress to ensure the host no longer runs any services:"
                echo "   watch docker service ls"

                # Find the location of the swarm-info/get_info.sh script
                local swarm_info_script_location=$(find_swarm_info_script)
                if [ -n "$swarm_info_script_location" ]; then
                    echo "   watch swarm-info --node-services"
                else
                    echo "   To easily view service distribution across nodes, please install swarm-info from https://github.com/Sokrates1989/swarm-info"
                fi

                echo ""
                echo "3. Reboot the server:"
                echo "   reboot"
                echo ""
                echo "4. Make the node available again:"
                echo "   docker node update --availability active $node_name"
                echo ""
                echo "5. Ensure equal distribution of services:"

                if [ -n "$swarm_info_script_location" ]; then
                    echo "   watch bash $swarm_info_script_location --node-services"
                else
                    echo "   To easily view service distribution across nodes, please install swarm-info from https://github.com/Sokrates1989/swarm-info"
                fi

                echo "   docker service update --force <service_name>"
            fi
        fi
    else
        # Print user info: System does not need to be restarted.
        if [ "$output_options" == "short" ]; then
            printf "%-${output_tab_space}s: %s\n" "Restart required" "No"
        else
            echo -e "No restart required"
        fi
        
        # Even if no restart required, show safe reboot option for single-node swarm
        if [ "$is_single_node" = true ]; then
            echo ""
            echo "💡 If you want to reboot this single-node Swarm anyway:"
            echo "   server-info --safe-reboot"
            echo ""
            echo "   This safely scales down services before reboot and restores them after."
        fi
    fi

    # Check if Docker Swarm is active and node is drained (for post-reboot reactivation)
    if [ "$is_swarm_active" = true ]; then
        local node_name=$(hostname)
        local node_availability=$(docker node inspect "$node_name" --format '{{.Spec.Availability}}' 2>/dev/null)
        
        if [ "$node_availability" = "drain" ]; then
            echo -e "\n⚠️  Docker Swarm Node Status: DRAINED"
            echo "This node is currently drained and not accepting new services."
            echo ""
            echo "To reactivate this node and make it available for services again:"
            echo "   docker node update --availability active $node_name"
            echo ""
            echo "To verify the node is active:"
            echo "   docker node ls"
            echo ""
            
            # Find the location of the swarm-info/get_info.sh script
            local swarm_info_script_location=$(find_swarm_info_script)
            if [ -n "$swarm_info_script_location" ]; then
                echo "To monitor service distribution across nodes:"
                echo "   watch bash $swarm_info_script_location --node-services"
            else
                echo "To easily view service distribution across nodes, please install swarm-info from https://github.com/Sokrates1989/swarm-info"
            fi
        fi
    fi
    
    # Check if maintenance mode is active (snapshot exists)
    local maintenance_snapshot="/var/lib/server-info/swarm-maintenance/current_snapshot.sh"
    if [ -f "$maintenance_snapshot" ]; then
        echo -e "\n⚠️  Swarm Maintenance Mode: ACTIVE"
        echo "A service snapshot exists - services may need to be restored."
        echo ""
        echo "To restore services from the snapshot:"
        echo "   server-info --maintenance-exit"
        echo ""
        echo "To check maintenance status:"
        echo "   server-info --maintenance-status"
    fi
}

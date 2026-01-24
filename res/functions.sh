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
                echo "  3. Prompt you to reboot"
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

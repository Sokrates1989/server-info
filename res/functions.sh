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
    
    }

# Check if maintenance mode is active and prompt to exit it.
#
# This function should be called at the end of system information display
# to ensure users see the full system status before being asked about maintenance mode.
check_and_prompt_maintenance_exit() {
    local maintenance_snapshot="/var/lib/server-info/swarm-maintenance/current_snapshot.sh"
    if [ -f "$maintenance_snapshot" ]; then
        echo -e "\n⚠️  Swarm Maintenance Mode: ACTIVE"
        echo "A service snapshot exists - services may need to be restored."
        echo ""
        echo "⚠️  IMPORTANT: Server is not performing its main purpose while in maintenance mode!"
        echo "   If no maintenance work is in progress, you should exit maintenance mode ASAP."
        echo ""
        
        # Interactive prompt to exit maintenance mode
        echo -n "Do you want to exit maintenance mode now? (Y/n): "
        read -r response
        echo ""
        
        # Default to Yes if user just presses Enter or answers Y/y
        if [[ -z "$response" || "$response" =~ ^[Yy]$ ]]; then
            echo "🔄 Exiting maintenance mode..."
            if command -v server-info >/dev/null 2>&1; then
                exec server-info --maintenance-exit
            else
                # Fallback: call maintenance_exit directly
                maintenance_exit
            fi
        else
            echo "Maintenance mode remains active."
            echo ""
            echo "To restore services manually:"
            echo "   server-info --maintenance-exit"
            echo ""
            echo "To check maintenance status:"
            echo "   server-info --maintenance-status"
        fi
    fi
}

# =============================================================================
# Hardware and Advanced Metrics Collection Functions
# =============================================================================

# Get a temperature from a hwmon device name pattern.
#
# Args:
#     $1: Extended regular expression matching the hwmon device name.
#
# Returns:
#     Temperature in Celsius (echoed to stdout), or nothing if unavailable.
get_hwmon_temperature() {
    local name_pattern="$1"
    local hwmon_dir

    for hwmon_dir in /sys/class/hwmon/hwmon*; do
        [ -d "$hwmon_dir" ] || continue

        local hwmon_name=$(cat "$hwmon_dir/name" 2>/dev/null)
        [ -n "$hwmon_name" ] || continue

        if [[ "$hwmon_name" =~ $name_pattern ]]; then
            local input_file=""
            local label_file

            for label_file in "$hwmon_dir"/temp*_label; do
                [ -f "$label_file" ] || continue
                local label=$(cat "$label_file" 2>/dev/null)

                if [[ "$label" =~ ^(Tctl|Tdie|edge|Composite|Package\ id\ .*)$ ]]; then
                    input_file="${label_file%_label}_input"
                    break
                fi
            done

            if [ -z "$input_file" ]; then
                local candidate_file
                for candidate_file in "$hwmon_dir"/temp*_input; do
                    [ -f "$candidate_file" ] || continue
                    input_file="$candidate_file"
                    break
                done
            fi

            if [ -n "$input_file" ] && [ -f "$input_file" ]; then
                local raw_temp=$(cat "$input_file" 2>/dev/null)

                if [[ "$raw_temp" =~ ^[0-9]+$ ]] && [ "$raw_temp" -gt 0 ]; then
                    echo $((raw_temp / 1000))
                    return 0
                fi
            fi
        fi
    done

    return 1
}

# Get the first fan speed exposed through hwmon.
#
# Returns:
#     Fan speed in RPM (echoed to stdout), or nothing if unavailable.
get_hwmon_fan_speed() {
    local hwmon_dir

    for hwmon_dir in /sys/class/hwmon/hwmon*; do
        [ -d "$hwmon_dir" ] || continue

        local fan_file
        for fan_file in "$hwmon_dir"/fan*_input; do
            [ -f "$fan_file" ] || continue

            local raw_speed=$(cat "$fan_file" 2>/dev/null)
            if [[ "$raw_speed" =~ ^[0-9]+$ ]] && [ "$raw_speed" -gt 0 ]; then
                echo "$raw_speed"
                return 0
            fi
        done
    done

    return 1
}

# Get CPU temperature from lm-sensors.
#
# Attempts to read CPU temperature using sensors command with fallback
# to alternative methods if lm-sensors is not available or fails.
#
# Returns:
#     Temperature in Celsius (echoed to stdout), or "N/A" if unavailable.
get_cpu_temperature() {
    local temp="N/A"
    
    # Try lm-sensors first
    if command -v sensors &> /dev/null; then
        # Try JSON output first (sensors -j requires lm-sensors 3.4.0+)
        if sensors -j &> /dev/null 2>&1; then
            # Parse JSON for CPU/package temperature
            temp=$(sensors -j 2>/dev/null | jq -r 'to_entries | map(select(.key | test("core|Package|CPU"; "i"))) | .[0].value | to_entries[] | select(.key | test("input"; "i")) | .value' 2>/dev/null | head -1)
        fi
        
        # Fallback to text parsing if JSON failed or returned empty
        if [ "$temp" = "N/A" ] || [ -z "$temp" ]; then
            temp=$(sensors 2>/dev/null | grep -E "Core|Package|CPU" | head -1 | awk '{print $3}' | tr -d '+°C' 2>/dev/null)
        fi
    fi
    
    # Fallback to CPU-related hwmon devices
    if [ "$temp" = "N/A" ] || [ -z "$temp" ]; then
        temp=$(get_hwmon_temperature 'k10temp|coretemp|zenpower|cpu_thermal|soc_thermal|fam15h_power' 2>/dev/null)
    fi
    
    # Fallback to thermal zone reading (Linux sysfs)
    if [ "$temp" = "N/A" ] || [ -z "$temp" ]; then
        if [ -d "/sys/class/thermal" ]; then
            # Find the highest temperature among all thermal zones
            local max_temp=0
            for zone in /sys/class/thermal/thermal_zone*/temp; do
                if [ -f "$zone" ]; then
                    local zone_temp=$(cat "$zone" 2>/dev/null)
                    if [ -n "$zone_temp" ] && [ "$zone_temp" -gt "$max_temp" ]; then
                        max_temp=$zone_temp
                    fi
                fi
            done
            if [ "$max_temp" -gt 0 ]; then
                # Convert millidegrees to degrees
                temp=$((max_temp / 1000))
            fi
        fi
    fi
    
    # Validate result is numeric
    if [ "$temp" != "N/A" ] && [ -n "$temp" ]; then
        if ! [[ "$temp" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            temp="N/A"
        fi
    fi
    
    echo "${temp:-N/A}"
}

# Get fan speed from lm-sensors.
#
# Returns:
#     Fan speed in RPM (echoed to stdout), or "N/A" if unavailable.
get_fan_speed() {
    local fan_speed="N/A"
    
    if command -v sensors &> /dev/null; then
        # Try to get fan speed from sensors output
        fan_speed=$(sensors 2>/dev/null | grep -E "fan[0-9]" | head -1 | awk '{print $2,$3}' | tr -d ' RPM' 2>/dev/null)
    fi
    
    # Fallback to hwmon fan sysfs
    if [ "$fan_speed" = "N/A" ] || [ -z "$fan_speed" ]; then
        fan_speed=$(get_hwmon_fan_speed 2>/dev/null)
    fi
    
    # Validate result is numeric
    if [ "$fan_speed" != "N/A" ] && [ -n "$fan_speed" ]; then
        if ! [[ "$fan_speed" =~ ^[0-9]+$ ]]; then
            fan_speed="N/A"
        fi
    fi
    
    echo "${fan_speed:-N/A}"
}

# Get disk SMART health status.
#
# Returns:
#     JSON string with SMART status (echoed to stdout), or "N/A" if unavailable.
get_disk_smart_health() {
    local smart_status='{"status": "N/A", "devices": []}'
    
    if command -v smartctl &> /dev/null; then
        # Get list of devices
        local devices=$(lsblk -d -o NAME -n 2>/dev/null | grep -E "^sd|^nvme|^vd" 2>/dev/null)
        
        if [ -n "$devices" ]; then
            local device_info="["
            local first=true
            
            while IFS= read -r device; do
                [ -z "$device" ] && continue
                
                local device_path="/dev/$device"
                local health="unknown"
                local temp="N/A"
                
                # Try to get SMART health
                local smart_output=$(smartctl -H "$device_path" 2>/dev/null)
                if [ $? -eq 0 ]; then
                    if echo "$smart_output" | grep -q "SMART overall-health self-assessment test result: PASSED"; then
                        health="passed"
                    elif echo "$smart_output" | grep -q "SMART overall-health self-assessment test result: FAILED"; then
                        health="failed"
                    fi
                    
                    # Try to get temperature
                    temp=$(smartctl -A "$device_path" 2>/dev/null | grep -E "Temperature.*" | head -1 | awk '{print $10}' 2>/dev/null)
                fi
                
                if [ "$first" = true ]; then
                    first=false
                else
                    device_info+=","
                fi
                
                device_info+="{\"device\": \"$device\", \"health\": \"$health\", \"temperature\": \"$temp\"}"
            done <<< "$devices"
            
            device_info+="]"
            smart_status="{\"status\": \"available\", \"devices\": $device_info}"
        else
            smart_status='{"status": "no_devices", "devices": []}'
        fi
    else
        smart_status='{"status": "smartctl_not_installed", "devices": []}'
    fi
    
    echo "$smart_status"
}

# Get I/O wait percentage.
#
# Returns:
#     I/O wait percentage (echoed to stdout), or "N/A" if unavailable.
get_io_wait() {
    local io_wait="N/A"
    
    if command -v vmstat &> /dev/null; then
        # Get I/O wait from vmstat (wa column, typically column 5)
        io_wait=$(vmstat 1 2 2>/dev/null | tail -1 | awk '{print $16}' 2>/dev/null)
    elif command -v iostat &> /dev/null; then
        # Alternative using iostat
        io_wait=$(iostat -x 1 1 2>/dev/null | tail -1 | awk '{print $4}' 2>/dev/null)
    fi
    
    # Validate result is numeric
    if [ "$io_wait" != "N/A" ] && [ -n "$io_wait" ]; then
        if ! [[ "$io_wait" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            io_wait="N/A"
        fi
    fi
    
    echo "${io_wait:-N/A}"
}

# Get system load averages.
#
# Returns:
#     JSON string with 1min, 5min, 15min load averages (echoed to stdout).
get_system_load() {
    local load_1min="N/A"
    local load_5min="N/A"
    local load_15min="N/A"
    local cpu_cores="N/A"
    local normalized_1min_percent="N/A"
    local normalized_5min_percent="N/A"
    local normalized_15min_percent="N/A"
    
    # Prefer /proc/loadavg (always available on Linux)
    if [ -r "/proc/loadavg" ]; then
        load_1min=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
        load_5min=$(awk '{print $2}' /proc/loadavg 2>/dev/null)
        load_15min=$(awk '{print $3}' /proc/loadavg 2>/dev/null)
    else
        local uptime_output=$(uptime 2>/dev/null)
        if [ -n "$uptime_output" ]; then
            load_1min=$(echo "$uptime_output" | awk -F'average:' '{print $2}' | awk '{print $1}' | tr -d ',' 2>/dev/null)
            load_5min=$(echo "$uptime_output" | awk -F'average:' '{print $2}' | awk '{print $2}' | tr -d ',' 2>/dev/null)
            load_15min=$(echo "$uptime_output" | awk -F'average:' '{print $2}' | awk '{print $3}' 2>/dev/null)
        fi
    fi
    
    # Compute normalized load percentages (load / cores * 100)
    cpu_cores=$(nproc 2>/dev/null)
    if [[ "$cpu_cores" =~ ^[0-9]+$ ]] && [ "$cpu_cores" -gt 0 ] && command -v bc &> /dev/null; then
        if [[ "$load_1min" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            normalized_1min_percent=$(echo "scale=2; $load_1min / $cpu_cores * 100" | bc 2>/dev/null)
        fi
        if [[ "$load_5min" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            normalized_5min_percent=$(echo "scale=2; $load_5min / $cpu_cores * 100" | bc 2>/dev/null)
        fi
        if [[ "$load_15min" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            normalized_15min_percent=$(echo "scale=2; $load_15min / $cpu_cores * 100" | bc 2>/dev/null)
        fi
    fi
    
    echo "{\"load_1min\": \"$load_1min\", \"load_5min\": \"$load_5min\", \"load_15min\": \"$load_15min\", \"cpu_cores\": \"$cpu_cores\", \"normalized_1min_percent\": \"$normalized_1min_percent\", \"normalized_5min_percent\": \"$normalized_5min_percent\", \"normalized_15min_percent\": \"$normalized_15min_percent\"}"
}

# Get file descriptor usage.
#
# Returns:
#     JSON string with FD usage statistics (echoed to stdout).
get_file_descriptor_usage() {
    local allocated="0"
    local maximum="0"
    local usage_percent="N/A"
    
    if [ -f "/proc/sys/fs/file-nr" ]; then
        local fd_info=$(cat /proc/sys/fs/file-nr 2>/dev/null)
        if [ -n "$fd_info" ]; then
            allocated=$(echo "$fd_info" | awk '{print $1}' 2>/dev/null)
            maximum=$(echo "$fd_info" | awk '{print $3}' 2>/dev/null)
            
            if [ "$maximum" -gt 0 ] 2>/dev/null && [ "$maximum" -lt 1000000000000 ] 2>/dev/null; then
                usage_percent=$(echo "scale=2; $allocated / $maximum * 100" | bc 2>/dev/null)
            else
                usage_percent="N/A"
            fi
        fi
    fi
    
    echo "{\"allocated\": \"$allocated\", \"maximum\": \"$maximum\", \"usage_percent\": \"$usage_percent\"}"
}

# Get network interface error statistics.
#
# Returns:
#     JSON string with network error statistics (echoed to stdout).
get_network_errors() {
    local errors='{"status": "N/A", "interfaces": []}'
    
    if [ -f "/proc/net/dev" ]; then
        local interfaces="["
        local first=true
        
        # Skip header lines, process each interface
        while IFS=: read -r interface stats; do
            [ -z "$interface" ] && continue
            # Skip header lines
            [[ "$interface" =~ ^(Inter|face|lo) ]] && continue
            
            interface=$(echo "$interface" | tr -d ' ')
            
            # Parse stats: receive bytes, packets, errs, drop, fifo, frame, compressed, multicast | transmit bytes, packets, errs, drop, fifo, colls, carrier, compressed
            local rx_err=$(echo "$stats" | awk '{print $3}' 2>/dev/null)
            local rx_drop=$(echo "$stats" | awk '{print $4}' 2>/dev/null)
            local tx_err=$(echo "$stats" | awk '{print $11}' 2>/dev/null)
            local tx_drop=$(echo "$stats" | awk '{print $12}' 2>/dev/null)
            
            if [ "$first" = true ]; then
                first=false
            else
                interfaces+=","
            fi
            
            interfaces+="{\"interface\": \"$interface\", \"rx_errors\": \"$rx_err\", \"rx_dropped\": \"$rx_drop\", \"tx_errors\": \"$tx_err\", \"tx_dropped\": \"$tx_drop\"}"
        done < <(tail -n +3 /proc/net/dev 2>/dev/null)
        
        interfaces+="]"
        errors="{\"status\": \"available\", \"interfaces\": $interfaces}"
    fi
    
    echo "$errors"
}

# Get ZFS pool health status.
#
# Returns:
#     JSON string with ZFS pool status (echoed to stdout).
get_zfs_status() {
    local zfs_status='{"status": "not_installed", "pools": []}'
    
    if command -v zpool &> /dev/null; then
        local pools=$(zpool list -H -o name 2>/dev/null)
        
        if [ -n "$pools" ]; then
            local pool_info="["
            local first=true
            
            while IFS= read -r pool; do
                [ -z "$pool" ] && continue
                
                local health=$(zpool list -H -o health "$pool" 2>/dev/null)
                local capacity=$(zpool list -H -o capacity "$pool" 2>/dev/null)
                
                if [ "$first" = true ]; then
                    first=false
                else
                    pool_info+=","
                fi
                
                pool_info+="{\"pool\": \"$pool\", \"health\": \"$health\", \"capacity\": \"$capacity\"}"
            done <<< "$pools"
            
            pool_info+="]"
            zfs_status="{\"status\": \"available\", \"pools\": $pool_info}"
        else
            zfs_status='{"status": "no_pools", "pools": []}'
        fi
    fi
    
    echo "$zfs_status"
}

# Get RAID array status (mdadm).
#
# Returns:
#     JSON string with RAID array status (echoed to stdout).
get_raid_status() {
    local raid_status='{"status": "not_installed", "arrays": []}'
    
    if command -v mdadm &> /dev/null; then
        local arrays=$(mdadm --detail --scan 2>/dev/null | grep ARRAY | awk '{print $2}')
        
        if [ -n "$arrays" ]; then
            local array_info="["
            local first=true
            
            while IFS= read -r array; do
                [ -z "$array" ] && continue
                
                local detail=$(mdadm --detail "$array" 2>/dev/null)
                local state=$(echo "$detail" | awk -F': ' '/State :/ {print $2; exit}' 2>/dev/null)
                local raid_level=$(echo "$detail" | awk -F': ' '/Raid Level :/ {print $2; exit}' 2>/dev/null)
                
                if [ "$first" = true ]; then
                    first=false
                else
                    array_info+=","
                fi
                
                array_info+="{\"array\": \"$array\", \"state\": \"$state\", \"raid_level\": \"$raid_level\"}"
            done <<< "$arrays"
            
            array_info+="]"
            raid_status="{\"status\": \"available\", \"arrays\": $array_info}"
        else
            raid_status='{"status": "no_arrays", "arrays": []}'
        fi
    fi
    
    echo "$raid_status"
}

# Get GPU temperature (NVIDIA or AMD).
#
# Returns:
#     GPU temperature in Celsius (echoed to stdout), or "N/A" if unavailable.
get_gpu_temperature() {
    local gpu_temp="N/A"
    
    # Try NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1)
    fi
    
    # Try AMD GPU (ROCm)
    if [ "$gpu_temp" = "N/A" ] || [ -z "$gpu_temp" ]; then
        if command -v rocm-smi &> /dev/null; then
            gpu_temp=$(rocm-smi --showtemp --showuse -u 2>/dev/null | grep -E "GPU Temp" | head -1 | awk '{print $4}' | tr -d 'C' 2>/dev/null)
        fi
    fi
    
    # Fallback to amdgpu hwmon device
    if [ "$gpu_temp" = "N/A" ] || [ -z "$gpu_temp" ]; then
        gpu_temp=$(get_hwmon_temperature 'amdgpu' 2>/dev/null)
    fi
    
    # Validate result is numeric
    if [ "$gpu_temp" != "N/A" ] && [ -n "$gpu_temp" ]; then
        if ! [[ "$gpu_temp" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            gpu_temp="N/A"
        fi
    fi
    
    echo "${gpu_temp:-N/A}"
}

# Get NTP time sync status.
#
# Returns:
#     JSON string with NTP sync information (echoed to stdout).
get_ntp_sync_status() {
    local ntp_status='{"status": "N/A", "offset_ms": "N/A", "synced": false}'
    
    # Try timedatectl
    if command -v timedatectl &> /dev/null; then
        local timedate_output=$(timedatectl 2>/dev/null)
        local system_clock_synced=$(echo "$timedate_output" | grep "System clock synchronized:" | awk '{print $4}' 2>/dev/null)
        
        if [ "$system_clock_synced" = "yes" ]; then
            ntp_status='{"status": "synced", "offset_ms": "N/A", "synced": true}'
        else
            ntp_status='{"status": "not_synced", "offset_ms": "N/A", "synced": false}'
        fi
    fi
    
    # Try ntpq for offset if available
    if command -v ntpq &> /dev/null; then
        local offset=$(ntpq -p 2>/dev/null | grep "*" | awk '{print $9}' 2>/dev/null)
        if [ -n "$offset" ]; then
            # Convert to milliseconds
            offset_ms=$(echo "$offset * 1000" | bc 2>/dev/null)
            ntp_status="{\"status\": \"available\", \"offset_ms\": \"${offset_ms:-N/A}\", \"synced\": true}"
        fi
    fi
    
    # Try chrony for offset if ntpq did not provide one
    if [ "$ntp_status" = '{"status": "synced", "offset_ms": "N/A", "synced": true}' ] || [ "$ntp_status" = '{"status": "not_synced", "offset_ms": "N/A", "synced": false}' ]; then
        if command -v chronyc &> /dev/null; then
            local chrony_offset=$(chronyc tracking 2>/dev/null | awk -F': +' '/Last offset/ {print $2}' | awk '{print $1}' 2>/dev/null)
            if [ -n "$chrony_offset" ]; then
                offset_ms=$(echo "$chrony_offset * 1000" | bc 2>/dev/null)
                ntp_status="{\"status\": \"available\", \"offset_ms\": \"${offset_ms:-N/A}\", \"synced\": true}"
            fi
        fi
    fi
    
    echo "$ntp_status"
}

#!/bin/bash

# 🔧 Resolve actual script directory, even if called via symlink
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
MAIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Global functions.
source "$SCRIPT_DIR/functions.sh"

# Function to display available system updates.
display_update_info() {
    bash "$SCRIPT_DIR/update_info.sh"
}

# Function to display cpu usage.
display_cpu_info() {
    bash "$SCRIPT_DIR/cpu_info.sh" -l  # To display long info.
}

# Function to display network usage.
display_network_info() {
    bash "$SCRIPT_DIR/network_info.sh" -l  # To display long info.
}

# Function to display long gluster info.
display_gluster_info() {
    bash "$SCRIPT_DIR/gluster_info.sh" -l  # To display long info.
}


# Output system info.
echo -e "\nSystem Information:"
hostname=$(hostname)
echo -e "Hostname: $hostname" 
uname -a

echo -e "\n\nKernel Information:"
check_kernel_info 28

echo -e "\n\nCpu Usage:"
display_cpu_info

echo -e "\n\nHardware Metrics:"
# CPU Temperature
cpu_temp=$(get_cpu_temperature)
if [ "$cpu_temp" != "N/A" ]; then
    echo -e "CPU Temperature: $cpu_temp°C"
else
    echo -e "CPU Temperature: N/A (sensors not available)"
fi

# Fan Speed
fan_speed=$(get_fan_speed)
if [ "$fan_speed" != "N/A" ]; then
    echo -e "Fan Speed: $fan_speed RPM"
else
    echo -e "Fan Speed: N/A (sensors not available)"
fi

# GPU Temperature
gpu_temp=$(get_gpu_temperature)
if [ "$gpu_temp" != "N/A" ]; then
    echo -e "GPU Temperature: $gpu_temp°C"
else
    echo -e "GPU Temperature: N/A (no GPU or nvidia-smi/rocm-smi not available)"
fi

# Disk SMART Health
smart_json=$(get_disk_smart_health)
smart_status=$(echo "$smart_json" | jq -r '.status' 2>/dev/null)
echo -e "Disk SMART Health: $smart_status"
if [ "$smart_status" = "available" ]; then
    echo "$smart_json" | jq -r '.devices[] | "  - \(.device): \(.health) (\(.temperature)°C)"' 2>/dev/null || echo "  Unable to parse SMART data"
fi

echo -e "\n\nDisk Usage:"
df -h /

echo -e "\n\nMemory Usage:"
free -h
# Calculate percentage of memory usage.
total_memory=$(free -m | awk '/Mem:/ {print $2}')
used_memory=$(free -m | awk '/Mem:/ {print $3}')
memory_usage_percentage=$(echo "scale=2; $used_memory / $total_memory * 100" | bc)
echo -e "Use%: $memory_usage_percentage%" 

echo -e "\n\nSwap Usage:"
swapon --show

echo -e "\n\nProcesses:"
ps aux | wc -l

echo -e "\n\nLogged-in Users:"
who

echo -e "\n\nAdvanced Metrics:"
# I/O Wait
io_wait=$(get_io_wait)
if [ "$io_wait" != "N/A" ]; then
    echo -e "I/O Wait: $io_wait%"
else
    echo -e "I/O Wait: N/A (vmstat not available)"
fi

# System Load
load_json=$(get_system_load)
load_1min=$(echo "$load_json" | jq -r '.load_1min' 2>/dev/null)
load_5min=$(echo "$load_json" | jq -r '.load_5min' 2>/dev/null)
load_15min=$(echo "$load_json" | jq -r '.load_15min' 2>/dev/null)
if [ "$load_1min" != "N/A" ]; then
    echo -e "System Load Averages: 1min=$load_1min, 5min=$load_5min, 15min=$load_15min"
fi

# File Descriptors
fd_json=$(get_file_descriptor_usage)
fd_allocated=$(echo "$fd_json" | jq -r '.allocated' 2>/dev/null)
fd_maximum=$(echo "$fd_json" | jq -r '.maximum' 2>/dev/null)
fd_usage=$(echo "$fd_json" | jq -r '.usage_percent' 2>/dev/null)
if [ "$fd_usage" != "N/A" ]; then
    echo -e "File Descriptors: $fd_allocated allocated of $fd_maximum ($fd_usage%)"
fi

# Network Errors
net_errors_json=$(get_network_errors)
net_status=$(echo "$net_errors_json" | jq -r '.status' 2>/dev/null)
echo -e "Network Errors Status: $net_status"

# ZFS Status
zfs_json=$(get_zfs_status)
zfs_status=$(echo "$zfs_json" | jq -r '.status' 2>/dev/null)
if [ "$zfs_status" = "available" ]; then
    echo -e "ZFS Pools:"
    echo "$zfs_json" | jq -r '.pools[] | "  - \(.pool): \(.health) (\(.capacity))"' 2>/dev/null || echo "  Unable to parse ZFS data"
else
    echo -e "ZFS Status: $zfs_status"
fi

# RAID Status
raid_json=$(get_raid_status)
raid_status=$(echo "$raid_json" | jq -r '.status' 2>/dev/null)
if [ "$raid_status" = "available" ]; then
    echo -e "RAID Arrays:"
    echo "$raid_json" | jq -r '.arrays[] | "  - \(.array): \(.state) (\(.raid_level))"' 2>/dev/null || echo "  Unable to parse RAID data"
else
    echo -e "RAID Status: $raid_status"
fi

# NTP Sync
ntp_json=$(get_ntp_sync_status)
ntp_status=$(echo "$ntp_json" | jq -r '.status' 2>/dev/null)
ntp_offset=$(echo "$ntp_json" | jq -r '.offset_ms' 2>/dev/null)
if [ "$ntp_offset" != "N/A" ]; then
    echo -e "NTP Sync: $ntp_status (offset: ${ntp_offset}ms)"
else
    echo -e "NTP Sync: $ntp_status"
fi

echo -e "\n\nLast Login Information:"
last

echo -e "\n\nIp addresses:"
ip a

echo -e "\n\nNetwork:"
display_network_info

# Gluster info.
echo -e "\n\n"
display_gluster_info

# Update info.
echo -e "\n\n"
display_update_info



# Print user info, if a restart is required including possible restart instructions.
echo -e "\n\n"
get_restart_information


# Is the repo of this project itself up to date?
echo -e "\n\n"

# Save the current directory to be able to revert back again to it later.
current_dir=$(pwd)
# Change to the Git repository directory to make git commands work.
cd $MAIN_DIR

# Check remote connection.
repo_url=https://github.com/Sokrates1989/linux-server-status.git
if git ls-remote --exit-code $repo_url >/dev/null 2>&1; then
    echo -e "Remote repository $repo_url is accessible."

    # Check local changes.
    if [ -n "$(git status --porcelain)" ]; then
        echo -e "There are local changes. Please commit or stabash your changes before pulling."
    fi

    # Check for upstream changes.
    git fetch -q
    behind_count=$(git rev-list HEAD..origin/main --count)
    if [ "$behind_count" -gt 0 ]; then
        echo -e "The local repository is $behind_count commits behind the remote repository. Pull is recommended."
        
        # Print user info how to update repo.
        echo -e "\nTo Update repo do this:"
        echo -e "cd $MAIN_DIR"
        echo -e "git pull\n"
        
    else
        echo -e "No changes in the remote repository."
    fi
else
    echo -e "Error: Remote repository $repo_url is not accessible."
fi

# Revert back to the original directory.
cd "$current_dir"

# Check for maintenance mode and prompt to exit if active
check_and_prompt_maintenance_exit


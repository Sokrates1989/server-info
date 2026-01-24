#!/bin/bash

# Output format like this:
# sampleText1               : sampleText2
# Can be achieved using this:
# printf '%-30s: %s\n' "sampleText1" "sampleText2"
# https://unix.stackexchange.com/questions/396223/bash-shell-script-output-alignment
output_tab_space=28 # The space until the colon to align all output info to
networking_tab_space=28 # The space until the colon to align all output info to
# printf "%-${output_tab_space}s: %s\n" "sampletext1" "sampleText2"


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

# Function to display cpu usage.
display_cpu_info() {
    bash "$SCRIPT_DIR/cpu_info.sh" -s -t $output_tab_space # To display short info with tab space
}

# Function to display network usage.
display_network_info() {
    bash "$SCRIPT_DIR/network_info.sh" -s -t $output_tab_space # To display short info with tab space
}

# Function to display short gluster info.
display_gluster_info() {
    bash "$SCRIPT_DIR/gluster_info.sh" -s -t $output_tab_space # To display short info with tab space
}



# System name information.
echo -e "\nSystem information\n"
hostname=$(hostname)
dist_name=$(lsb_release -ds)
kernel_ver=$(uname -sr)
sys_info_from_vars="${dist_name} (${kernel_ver})"
sys_info="$(lsb_release -ds) ($(uname -sr))"

# Print system name information.
printf "%-${output_tab_space}s: %s\n" "Hostname" "$hostname (sudo hostnamectl set-hostname newhostname)" 
printf "%-${output_tab_space}s: %s\n" "System name" "$sys_info"

# Spacer.
echo -e ""

# CPU Usage.
display_cpu_info

# Disk usage.
mount_point="/"
df_output=$(df -h "$mount_point" | awk -v mp="$mount_point" 'NR==2 {printf "%s of %s (%s)", $5, $2, $3}')
printf "%-${output_tab_space}s: %s\n" "Disk Usage of $mount_point" "$df_output"


# Memory Usage.
total_memory=$(free -m | awk '/Mem:/ {print $2}')
total_memory_human=$(free -h | awk '/Mem:/ {print $2}')
used_memory=$(free -m | awk '/Mem:/ {print $3}')
used_memory_human=$(free -h | awk '/Mem:/ {print $3}')
memory_usage_percentage=$(echo "scale=2; $used_memory / $total_memory * 100" | bc)
printf "%-${output_tab_space}s: %s\n" "Memory Usage" "$memory_usage_percentage% of $total_memory_human ($used_memory_human)"

# Swap Usage.
swap_info=$(swapon --show)
if [ -n "$swap_info" ]; then
    printf "%-${output_tab_space}s: %s\n" "Swap Usage" "Swap is in use"
    printf "%-${output_tab_space}s: %s\n" "Turn swap off" "sudo swapoff -a"
    printf "%-${output_tab_space}s: %s\n" "Prevent restarting" "sudo vi /etc/fstab (comment out lines with swap or swapfile)"
    echo -e "$swap_info"
else
    printf "%-${output_tab_space}s: %s\n" "Swap Usage" "No active swap"
fi


# Spacer.
echo -e ""

# Processes.
amount_processes=$(ps aux | wc -l)
printf "%-${output_tab_space}s: %s\n" "Processes" "$amount_processes"

# Logged in users.
logged_in_users=$(who | wc -l)
printf "%-${output_tab_space}s: %s\n" "Users logged in" "$logged_in_users"


# Spacer.
echo -e ""

# Ipv4 Adresses.
ip -4 a | awk -v tab_space="$networking_tab_space" '/inet/ {printf "%-"tab_space"s: %s\n", "IPv4 of "$NF, $2}'


# Spacer.
echo -e ""

# Network Usage.
display_network_info

# Spacer.
echo -e ""

# Gluster info.
display_gluster_info

# Spacer.
echo -e ""


# Update APT repository.
echo -e "Fetching available updates..."
sudo apt-get update -qq
# Available updates.
updates=$(apt list --upgradable 2>/dev/null)
if [ "${#updates}" -gt 10 ]; # Checks length of updates var, because also a fully updated system returns the string "Listing..."
then
    printf "%-${output_tab_space}s: %s\n" "Updates Available" "Yes (use -u option to view all available updates -> server-info -u )"
else
    printf "%-${output_tab_space}s: %s\n" "Updates Available" "No"
fi


# Print user info, if a restart is required including possible restart instructions.
get_restart_information "short" $output_tab_space




# Spacer.
echo -e "\n"

# Save the current directory to be able to revert back again to it later.
current_dir=$(pwd)
# Change to the Git repository directory to make git commands work.
cd $MAIN_DIR


# This tool's state.
echo -e "Fetching state of linux-server-status (this tool) ..."
repo_url=https://github.com/Sokrates1989/linux-server-status.git
is_healthy=true
repo_issue=false
local_changes=false
available_updates=false

# Check remote connection.
if git ls-remote --exit-code "$repo_url" >/dev/null 2>&1; then

    # Check local changes.
    if [ -n "$(git status --porcelain)" ]; then
        local_changes=true
        is_healthy=false
    fi

    # Check for upstream changes.
    git fetch -q
    behind_count=$(git rev-list HEAD..origin/main --count)
    if [ "$behind_count" -gt 0 ]; then
        available_updates=true
        is_healthy=false
    fi
else
    is_healthy=false
    repo_issue=true
fi


if [ "$is_healthy" = true ]; then
    echo -e "This tool (linux server status) is healthy and up to date"
else
    # print detailed information.
    echo -e "This tool (linux server status) is NOT healthy:"
    
    if [ "$repo_issue" = true ]; then
        echo -e "Remote repository $repo_url is not accessible"
    else
        if [ "$local_changes" = true ]; then
            echo -e "Local repo has uncommitted changes"
        fi 

        if [ "$available_updates" = true ]; then
            echo -e "Remote Repo updateable! $behind_count commits behind. Pull is recommended."

            # Print user info how to update repo.
            echo -e "\nTo Update repo do this:"
            echo -e "cd $MAIN_DIR"
            echo -e "git pull"
            echo -e "cd $current_dir\n"
            
        fi
    fi         
fi


# Revert back to the original directory.
cd "$current_dir"


# Spacer.
echo -e "\n"
echo -e "To view full system report use -f option -> server-info -f  "
echo -e "To view all available options use --help -> server-info --help  "
echo -e ""



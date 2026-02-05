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


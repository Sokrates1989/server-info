#!/bin/bash

# 🔧 Robust: Resolve actual script directory, even if called via symlink
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

# Function to display short system information.
display_short_info() {
    bash "$SCRIPT_DIR/res/short_info.sh"
}

# Function to display full system information.
display_full_info() {
    bash "$SCRIPT_DIR/res/long_info.sh"
}

# Function to display available system updates.
display_update_info() {
    echo -e ""
    bash "$SCRIPT_DIR/res/update_info.sh"
    echo -e ""
}

# Function to display cpu info.
display_cpu_info() {
    echo -e ""
    bash "$SCRIPT_DIR/res/cpu_info.sh" -l  # To display long info.
    echo -e ""
}

# Function to display full gluster info.
display_gluster_info() {
    echo -e ""
    bash "$SCRIPT_DIR/res/gluster_info.sh" -l  # To display long info.
    echo -e ""
}

# Source swarm maintenance module.
source "$SCRIPT_DIR/res/swarm_maintenance.sh"

# Function to display and save system information as json.
CUSTOM_OUTPUT_FILE="NONE"
server_states_dir="$SCRIPT_DIR/server-states"
server_states_json_file="$server_states_dir/system_info.json"
system_info_json() {
    # Check if CUSTOM_OUTPUT_FILE is still in its default value
    if [ "$CUSTOM_OUTPUT_FILE" = "NONE" ]; then
        bash "$SCRIPT_DIR/res/system_info.sh" --json --output-file "$server_states_json_file"
    else
        bash "$SCRIPT_DIR/res/system_info.sh" --json --output-file "$CUSTOM_OUTPUT_FILE"
    fi
}

# Function to display help information.
display_help() {
    echo -e "Usage: $0 [OPTIONS]"
    echo -e "Options:"
    echo -e "  -f, --full              Display full system information"
    echo -e "  -l                      Alias for --full"
    echo -e "  -u                      Display available system updates"
    echo -e "  -s                      Display short system information"
    echo -e "  --cpu                   Display CPU information"
    echo -e "  -g, --gluster           Display full glusterfs info"
    echo -e "  --help                  Display this help message"
    echo -e "  --json                  Save and display info in json format"
    echo -e "  --output-file           Where to save the system info output (only in combination with --json)"
    echo -e "  -o                      Alias for --output-file"
    echo -e ""
    echo -e "Swarm Maintenance (single-node safe reboot):"
    echo -e "  --maintenance-enter     Enter maintenance mode (snapshot + scale down services)"
    echo -e "  --maintenance-exit      Exit maintenance mode (restore services from snapshot)"
    echo -e "  --safe-reboot           Full safe reboot workflow (enter + reboot prompt)"
    echo -e "  --maintenance-status    Show current maintenance status"
    echo -e "  --maintenance-help      Show detailed maintenance help"
}


# Default values.
use_file_output="false"
file_output_type="json"

# Check for command-line options.
while [ $# -gt 0 ]; do
    case "$1" in
        -f)
            display_full_info
            exit 0
            ;;
        -l)
            display_full_info
            exit 0
            ;;
        -u)
            display_update_info
            exit 0
            ;;
        -s)
            display_short_info
            exit 0
            ;;
        --cpu)
            display_cpu_info
            exit 0
            ;;
        --gluster)
            display_gluster_info
            exit 0
            ;;
        -g)
            display_gluster_info
            exit 0
            ;;
        --maintenance-enter)
            shift
            maintenance_enter "$@"
            exit $?
            ;;
        --maintenance-exit)
            shift
            maintenance_exit "$@"
            exit $?
            ;;
        --safe-reboot)
            shift
            safe_reboot "$@"
            exit $?
            ;;
        --maintenance-status)
            maintenance_status
            exit $?
            ;;
        --maintenance-help)
            maintenance_help
            exit 0
            ;;
        --help)
            display_help
            exit 0
            ;;
        --json)
            use_file_output="true"
            file_output_type="json"
            shift
            ;;
        --output-file)
            shift
            CUSTOM_OUTPUT_FILE="$1"
            shift
            ;;
        -o)
            shift
            CUSTOM_OUTPUT_FILE="$1"
            shift
            ;;
        *)
            echo -e "Invalid option: $1" >&2
            exit 1
            ;;
    esac
done

# Use file output?
if [ "$use_file_output" = "true" ]; then
    if [ "$file_output_type" = "json" ]; then
        system_info_json
    else
        # If no option is specified or an invalid option is provided, display short info.
        echo -e "invalid file_output_type: $file_output_type"
    fi
else
    # If no option is specified or an invalid option is provided, display short info.
    display_short_info
fi


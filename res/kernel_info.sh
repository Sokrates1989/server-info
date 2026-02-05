#!/bin/bash

# Kernel information script for server-info (standalone).
#
# Displays running kernel version and checks for available kernel
# package updates using apt-cache policy Installed vs Candidate comparison.
#
# Usage: kernel_info.sh [-t tab_space]

# 🔧 Resolve actual script directory, even if called via symlink
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

# Global functions (provides check_kernel_info).
source "$SCRIPT_DIR/functions.sh"

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

# Run the function from functions.sh
check_kernel_info $output_tab_space

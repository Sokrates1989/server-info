#!/bin/bash

# =============================================================================
# Module: swarm_maintenance.sh
# Description: Safe maintenance mode for single-node Docker Swarm clusters.
#              Provides snapshot, scale-down, restore, and safe reboot workflows.
# =============================================================================

# 🔧 Resolve actual script directory, even if called via symlink
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
MAINTENANCE_SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
MAINTENANCE_MAIN_DIR="$(cd "$MAINTENANCE_SCRIPT_DIR/.." && pwd)"

# Configuration
MAINTENANCE_DIR="/var/lib/server-info/swarm-maintenance"
SNAPSHOT_FILE="$MAINTENANCE_DIR/current_snapshot.sh"
SNAPSHOT_INFO="$MAINTENANCE_DIR/current_snapshot.info"

# Service classification patterns (lowercase for matching)
DB_PATTERNS="postgres|mysql|mariadb|mongo|redis|neo4j|elasticsearch|memcached"
INGRESS_PATTERNS="traefik|nginx|haproxy|caddy"

# =============================================================================
# Helper Functions
# =============================================================================

# Check if Docker Swarm is active and node is manager.
#
# Returns:
#     0 if swarm is active and node is manager, 1 otherwise
check_swarm_active() {
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed." >&2
        return 1
    fi
    
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        echo "Error: Docker Swarm is not active." >&2
        return 1
    fi
    
    if ! docker info 2>/dev/null | grep -q "Is Manager: true"; then
        echo "Error: This node is not a Swarm manager." >&2
        return 1
    fi
    
    return 0
}

# Get the number of nodes in the swarm.
#
# Returns:
#     Number of nodes (echoed to stdout)
get_swarm_node_count() {
    docker node ls --format '{{.ID}}' 2>/dev/null | wc -l | tr -d ' '
}

# Check if this is a single-node swarm.
#
# Returns:
#     0 if single-node, 1 otherwise
is_single_node_swarm() {
    local node_count
    node_count=$(get_swarm_node_count)
    [ "$node_count" -eq 1 ]
}

# Classify a service based on its image/name.
#
# Args:
#     service_name: Name of the service
#     image: Image name of the service
#
# Returns:
#     Category string: "app", "db", or "ingress"
classify_service() {
    local service_name="$1"
    local image="$2"
    local combined
    combined=$(echo "${service_name}_${image}" | tr '[:upper:]' '[:lower:]')
    
    if echo "$combined" | grep -qE "$INGRESS_PATTERNS"; then
        echo "ingress"
    elif echo "$combined" | grep -qE "$DB_PATTERNS"; then
        echo "db"
    else
        echo "app"
    fi
}

# Ensure maintenance directory exists.
ensure_maintenance_dir() {
    if [ ! -d "$MAINTENANCE_DIR" ]; then
        sudo mkdir -p "$MAINTENANCE_DIR"
        sudo chmod 755 "$MAINTENANCE_DIR"
    fi
}

# =============================================================================
# Core Functions
# =============================================================================

# Check if maintenance mode is currently active.
#
# Returns:
#     0 if in maintenance mode (snapshot exists), 1 otherwise
is_maintenance_mode_active() {
    [ -f "$SNAPSHOT_FILE" ]
}

# Create a snapshot of current service replica counts.
#
# Args:
#     --force: Overwrite existing snapshot if present
#
# Returns:
#     0 on success, 1 on failure
create_snapshot() {
    local force=false
    
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --force) force=true ;;
        esac
        shift
    done
    
    if ! check_swarm_active; then
        return 1
    fi
    
    ensure_maintenance_dir
    
    if [ -f "$SNAPSHOT_FILE" ] && [ "$force" != "true" ]; then
        echo "Error: Snapshot already exists. Use --force to overwrite or run 'maintenance-exit' first." >&2
        echo "Existing snapshot created: $(cat "$SNAPSHOT_INFO" 2>/dev/null | grep 'Created:' | cut -d: -f2-)" >&2
        return 1
    fi
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname_val
    hostname_val=$(hostname)
    
    echo "Creating service snapshot..."
    
    # Create restore script header
    cat > "$SNAPSHOT_FILE" << 'EOF'
#!/bin/bash
# Auto-generated restore script for Docker Swarm services
# DO NOT EDIT - This file is managed by server-info swarm maintenance

EOF
    
    # Track counts for summary
    local app_count=0
    local db_count=0
    local ingress_count=0
    local total_count=0
    
    # Get all services and their replica counts
    while IFS= read -r line; do
        local name mode replicas image
        name=$(echo "$line" | awk '{print $1}')
        mode=$(echo "$line" | awk '{print $2}')
        replicas=$(echo "$line" | awk '{print $3}')
        image=$(echo "$line" | awk '{print $4}')
        
        [ -z "$name" ] && continue
        
        if [ "$mode" = "replicated" ]; then
            local category
            category=$(classify_service "$name" "$image")
            
            echo "# Category: $category | Image: $image" >> "$SNAPSHOT_FILE"
            echo "docker service scale \"$name=$replicas\"" >> "$SNAPSHOT_FILE"
            echo "" >> "$SNAPSHOT_FILE"
            
            case "$category" in
                app) ((app_count++)) ;;
                db) ((db_count++)) ;;
                ingress) ((ingress_count++)) ;;
            esac
            ((total_count++))
        elif [ "$mode" = "global" ]; then
            # Global services - store info but handle differently on restore
            echo "# GLOBAL SERVICE - will be restored by ensuring service is running" >> "$SNAPSHOT_FILE"
            echo "# docker service update \"$name\" --force  # Uncomment if needed" >> "$SNAPSHOT_FILE"
            echo "" >> "$SNAPSHOT_FILE"
        fi
    done < <(docker service ls --format '{{.Name}} {{.Mode}} {{.Replicas}} {{.Image}}' 2>/dev/null | while read -r sname smode sreplicas simage; do
        # Extract desired replica count from "X/Y" format
        local desired
        desired=$(echo "$sreplicas" | cut -d'/' -f2)
        echo "$sname $smode $desired $simage"
    done)
    
    chmod +x "$SNAPSHOT_FILE"
    
    # Create info file
    cat > "$SNAPSHOT_INFO" << EOF
Created: $timestamp
Hostname: $hostname_val
Total Services: $total_count
Application Services: $app_count
Database Services: $db_count
Ingress Services: $ingress_count
Node Count: $(get_swarm_node_count)
EOF
    
    echo ""
    echo "✅ Snapshot created successfully"
    echo "   Location: $SNAPSHOT_FILE"
    echo "   Services captured: $total_count (Apps: $app_count, DBs: $db_count, Ingress: $ingress_count)"
    echo ""
    
    return 0
}

# Scale down all services in safe order.
#
# Order: Applications -> Databases -> Ingress
#
# Returns:
#     0 on success, 1 on failure
scale_down_services() {
    if ! check_swarm_active; then
        return 1
    fi
    
    echo "Scaling down services in safe order..."
    echo ""
    
    # Collect services by category
    local app_services=()
    local db_services=()
    local ingress_services=()
    
    while IFS= read -r line; do
        local name mode image
        name=$(echo "$line" | awk '{print $1}')
        mode=$(echo "$line" | awk '{print $2}')
        image=$(echo "$line" | awk '{print $3}')
        
        [ -z "$name" ] && continue
        [ "$mode" != "replicated" ] && continue
        
        local category
        category=$(classify_service "$name" "$image")
        
        case "$category" in
            app) app_services+=("$name") ;;
            db) db_services+=("$name") ;;
            ingress) ingress_services+=("$name") ;;
        esac
    done < <(docker service ls --format '{{.Name}} {{.Mode}} {{.Image}}' 2>/dev/null)
    
    # Scale down applications first
    if [ ${#app_services[@]} -gt 0 ]; then
        echo "📦 Scaling down application services (${#app_services[@]})..."
        local scale_args=""
        for svc in "${app_services[@]}"; do
            scale_args="$scale_args $svc=0"
        done
        docker service scale $scale_args 2>/dev/null
        echo ""
    fi
    
    # Scale down databases next
    if [ ${#db_services[@]} -gt 0 ]; then
        echo "🗄️  Scaling down database services (${#db_services[@]})..."
        local scale_args=""
        for svc in "${db_services[@]}"; do
            scale_args="$scale_args $svc=0"
        done
        docker service scale $scale_args 2>/dev/null
        echo ""
    fi
    
    # Scale down ingress last
    if [ ${#ingress_services[@]} -gt 0 ]; then
        echo "🌐 Scaling down ingress services (${#ingress_services[@]})..."
        local scale_args=""
        for svc in "${ingress_services[@]}"; do
            scale_args="$scale_args $svc=0"
        done
        docker service scale $scale_args 2>/dev/null
        echo ""
    fi
    
    # Handle global services (like traefik in global mode)
    local global_services
    global_services=$(docker service ls --format '{{.Name}} {{.Mode}}' 2>/dev/null | awk '$2=="global"{print $1}')
    if [ -n "$global_services" ]; then
        echo "🌍 Scaling down global services..."
        for svc in $global_services; do
            # Global services can't be scaled to 0, so we update with replicas constraint
            docker service update --replicas-max-per-node 0 "$svc" 2>/dev/null || true
        done
        echo ""
    fi
    
    echo "✅ All services scaled down"
    echo ""
    
    return 0
}

# Restore services from snapshot.
#
# Returns:
#     0 on success, 1 on failure
restore_services() {
    if ! check_swarm_active; then
        return 1
    fi
    
    if [ ! -f "$SNAPSHOT_FILE" ]; then
        echo "Error: No snapshot found at $SNAPSHOT_FILE" >&2
        echo "Cannot restore without a snapshot. Did you run 'maintenance-enter' before rebooting?" >&2
        return 1
    fi
    
    echo "Restoring services from snapshot..."
    echo ""
    
    if [ -f "$SNAPSHOT_INFO" ]; then
        echo "Snapshot info:"
        cat "$SNAPSHOT_INFO"
        echo ""
    fi
    
    # Restore global services first (reverse of shutdown order)
    local global_services
    global_services=$(docker service ls --format '{{.Name}} {{.Mode}}' 2>/dev/null | awk '$2=="global"{print $1}')
    if [ -n "$global_services" ]; then
        echo "🌍 Restoring global services..."
        for svc in $global_services; do
            docker service update --replicas-max-per-node 1000000 "$svc" 2>/dev/null || true
        done
        echo ""
    fi
    
    # Restore replicated services in reverse order of shutdown: ingress -> databases -> apps
    local ingress_commands=()
    local db_commands=()
    local app_commands=()
    local current_category=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^#\ Category:\ ([a-z]+)\ \| ]]; then
            current_category="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^docker\ service\ scale\  ]]; then
            case "$current_category" in
                ingress) ingress_commands+=("$line") ;;
                db) db_commands+=("$line") ;;
                app) app_commands+=("$line") ;;
            esac
        fi
    done < "$SNAPSHOT_FILE"
    
    if [ ${#ingress_commands[@]} -gt 0 ]; then
        echo "🌐 Restoring ingress services..."
        for cmd in "${ingress_commands[@]}"; do
            eval "$cmd"
        done
        echo ""
    fi
    
    if [ ${#db_commands[@]} -gt 0 ]; then
        echo "�️  Restoring database services..."
        for cmd in "${db_commands[@]}"; do
            eval "$cmd"
        done
        echo ""
    fi
    
    if [ ${#app_commands[@]} -gt 0 ]; then
        echo "📦 Restoring application services..."
        for cmd in "${app_commands[@]}"; do
            eval "$cmd"
        done
        echo ""
    fi
    
    echo "✅ Services restored"
    echo ""
    
    # Verify services are coming up
    echo "Current service status:"
    docker service ls
    echo ""
    
    return 0
}

# Archive and remove current snapshot after successful restore.
cleanup_snapshot() {
    if [ -f "$SNAPSHOT_FILE" ]; then
        local archive_dir="$MAINTENANCE_DIR/archive"
        local timestamp
        timestamp=$(date '+%Y%m%d_%H%M%S')
        
        sudo mkdir -p "$archive_dir"
        sudo mv "$SNAPSHOT_FILE" "$archive_dir/snapshot_$timestamp.sh"
        [ -f "$SNAPSHOT_INFO" ] && sudo mv "$SNAPSHOT_INFO" "$archive_dir/snapshot_$timestamp.info"
        
        echo "Snapshot archived to: $archive_dir/snapshot_$timestamp.sh"
    fi
}

# =============================================================================
# Main Command Functions
# =============================================================================

# Enter maintenance mode: create snapshot and scale down services.
#
# Args:
#     --force: Overwrite existing snapshot
#     --dry-run: Show what would be done without making changes
#
# Returns:
#     0 on success, 1 on failure
maintenance_enter() {
    local force=false
    local dry_run=false
    
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --force) force=true ;;
            --dry-run) dry_run=true ;;
        esac
        shift
    done
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           ENTERING SWARM MAINTENANCE MODE                      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    if ! check_swarm_active; then
        return 1
    fi
    
    local node_count
    node_count=$(get_swarm_node_count)
    echo "Swarm Status: Active ($node_count node(s))"
    echo ""
    
    if [ "$dry_run" = "true" ]; then
        echo "🔍 DRY RUN MODE - No changes will be made"
        echo ""
        echo "Would create snapshot at: $SNAPSHOT_FILE"
        echo ""
        echo "Services that would be scaled down:"
        docker service ls --format 'table {{.Name}}\t{{.Mode}}\t{{.Replicas}}\t{{.Image}}'
        return 0
    fi
    
    # Create snapshot
    if [ "$force" = "true" ]; then
        create_snapshot --force || return 1
    else
        create_snapshot || return 1
    fi
    
    # Scale down services
    scale_down_services || return 1
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           MAINTENANCE MODE ACTIVE                              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "All services have been scaled down safely."
    echo ""
    echo "You can now:"
    echo "  • Reboot the server:     reboot"
    echo "  • Exit maintenance mode: server-info --maintenance-exit"
    echo ""
    
    return 0
}

# Exit maintenance mode: restore services from snapshot.
#
# Args:
#     --keep-snapshot: Don't archive the snapshot after restore
#
# Returns:
#     0 on success, 1 on failure
maintenance_exit() {
    local keep_snapshot=false
    
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --keep-snapshot) keep_snapshot=true ;;
        esac
        shift
    done
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           EXITING SWARM MAINTENANCE MODE                       ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    if ! check_swarm_active; then
        return 1
    fi
    
    if ! is_maintenance_mode_active; then
        echo "⚠️  No active maintenance mode detected (no snapshot found)."
        echo ""
        echo "If services are already running, no action is needed."
        echo "Current service status:"
        docker service ls
        return 0
    fi
    
    # Restore services
    restore_services || return 1
    
    # Cleanup snapshot
    if [ "$keep_snapshot" != "true" ]; then
        cleanup_snapshot
    fi
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           MAINTENANCE MODE EXITED                              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Services have been restored to their previous state."
    echo ""
    echo "Monitor service health with:"
    echo "  docker service ls"
    echo "  docker service ps <service_name>"
    echo ""
    
    return 0
}

# Safe reboot workflow: enter maintenance, prompt for reboot.
#
# Returns:
#     0 on success, 1 on failure
safe_reboot() {
    local force=false
    local auto_reboot=false
    
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --force) force=true ;;
            --yes|-y) auto_reboot=true ;;
        esac
        shift
    done
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           SAFE SWARM REBOOT                                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    if ! check_swarm_active; then
        return 1
    fi
    
    local node_count
    node_count=$(get_swarm_node_count)
    
    if [ "$node_count" -gt 1 ]; then
        echo "⚠️  Multi-node swarm detected ($node_count nodes)."
        echo ""
        echo "For multi-node swarms, consider using the drain approach instead:"
        echo "  docker node update --availability drain $(hostname)"
        echo ""
        read -p "Continue with safe-reboot anyway? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            return 1
        fi
    fi
    
    # Enter maintenance mode
    if [ "$force" = "true" ]; then
        maintenance_enter --force || return 1
    else
        maintenance_enter || return 1
    fi
    
    # Verify all services are down
    echo "Verifying services are stopped..."
    sleep 2
    
    local running
    running=$(docker service ls --format '{{.Replicas}}' 2>/dev/null | grep -v '^0/' | grep -v '^0/0' | wc -l)
    if [ "$running" -gt 0 ]; then
        echo "⚠️  Some services may still be running. Check with: docker service ls"
    fi
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           READY TO REBOOT                                      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "The server is ready for a safe reboot."
    echo ""
    echo "After reboot, run this command to restore services:"
    echo "  server-info --maintenance-exit"
    echo ""
    
    if [ "$auto_reboot" = "true" ]; then
        echo "Rebooting in 5 seconds... (Ctrl+C to cancel)"
        sleep 5
        sudo reboot
    else
        read -p "Reboot now? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "Rebooting..."
            sudo reboot
        else
            echo ""
            echo "Reboot cancelled. To reboot manually, run: reboot"
            echo "To restore services without rebooting: server-info --maintenance-exit"
        fi
    fi
    
    return 0
}

# Show current maintenance status.
maintenance_status() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           SWARM MAINTENANCE STATUS                             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    if ! check_swarm_active; then
        return 1
    fi
    
    local node_count
    node_count=$(get_swarm_node_count)
    echo "Swarm Status: Active ($node_count node(s))"
    
    if is_single_node_swarm; then
        echo "Swarm Type: Single-node"
    else
        echo "Swarm Type: Multi-node"
    fi
    echo ""
    
    if is_maintenance_mode_active; then
        echo "Maintenance Mode: ACTIVE"
        echo ""
        if [ -f "$SNAPSHOT_INFO" ]; then
            echo "Snapshot Info:"
            cat "$SNAPSHOT_INFO" | sed 's/^/  /'
        fi
        echo ""
        echo "To restore services: server-info --maintenance-exit"
    else
        echo "Maintenance Mode: Not active"
        echo ""
        echo "To enter maintenance mode: server-info --maintenance-enter"
        echo "To perform safe reboot:    server-info --safe-reboot"
    fi
    echo ""
    
    echo "Current Service Status:"
    docker service ls
    echo ""
    
    return 0
}

# Display help for maintenance commands.
maintenance_help() {
    echo ""
    echo "Swarm Maintenance Commands"
    echo "=========================="
    echo ""
    echo "These commands help you safely reboot a single-node Docker Swarm"
    echo "by scaling down services before reboot and restoring them after."
    echo ""
    echo "Commands:"
    echo "  --maintenance-enter    Enter maintenance mode (snapshot + scale down)"
    echo "  --maintenance-exit     Exit maintenance mode (restore services)"
    echo "  --safe-reboot          Full safe reboot workflow"
    echo "  --maintenance-status   Show current maintenance status"
    echo ""
    echo "Options:"
    echo "  --force                Overwrite existing snapshot"
    echo "  --dry-run              Show what would be done (enter only)"
    echo "  --keep-snapshot        Don't archive snapshot after restore"
    echo "  -y, --yes              Auto-confirm reboot (safe-reboot only)"
    echo ""
    echo "Typical Workflow:"
    echo "  1. server-info --safe-reboot     # Enter maintenance + reboot"
    echo "  2. (system reboots)"
    echo "  3. server-info --maintenance-exit  # Restore services"
    echo ""
    echo "Or manually:"
    echo "  1. server-info --maintenance-enter"
    echo "  2. reboot"
    echo "  3. server-info --maintenance-exit"
    echo ""
}

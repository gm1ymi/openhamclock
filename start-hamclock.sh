#!/bin/bash
#
# OpenHamClock - Linux Startup Script
# Starts the server in the background and manages the process
#
# Usage:
#   ./start-hamclock.sh           # Start server
#   ./start-hamclock.sh stop      # Stop server
#   ./start-hamclock.sh restart   # Restart server
#   ./start-hamclock.sh status    # Check status
#   ./start-hamclock.sh logs      # View logs
#

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/hamclock.pid"
LOG_FILE="$SCRIPT_DIR/hamclock.log"
NODE_SCRIPT="$SCRIPT_DIR/server.js"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if Node.js is installed
check_node() {
    if ! command -v node &> /dev/null; then
        print_error "Node.js is not installed!"
        echo ""
        echo "Install Node.js 14+ from https://nodejs.org"
        echo ""
        echo "Quick install commands:"
        echo "  Ubuntu/Debian:  sudo apt update && sudo apt install nodejs npm"
        echo "  Fedora:         sudo dnf install nodejs"
        echo "  Arch:           sudo pacman -S nodejs npm"
        echo ""
        exit 1
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 14 ]; then
        print_warning "Node.js version is old (v$NODE_VERSION). Version 14+ recommended."
    fi
}

# Check if dependencies are installed
check_dependencies() {
    if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
        print_warning "Dependencies not installed. Running npm install..."
        cd "$SCRIPT_DIR"
        npm install
        if [ $? -eq 0 ]; then
            print_success "Dependencies installed successfully"
        else
            print_error "Failed to install dependencies"
            exit 1
        fi
    fi
}

# Get the PID of the running server
get_pid() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        # Check if process is actually running
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "$PID"
            return 0
        else
            # Stale PID file
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1
}

# Start the server
start_server() {
    print_status "Starting OpenHamClock server..."
    
    # Check if already running
    if get_pid > /dev/null 2>&1; then
        PID=$(get_pid)
        print_warning "Server is already running (PID: $PID)"
        return 0
    fi
    
    # Check prerequisites
    check_node
    check_dependencies
    
    # Check if server.js exists
    if [ ! -f "$NODE_SCRIPT" ]; then
        print_error "server.js not found at $NODE_SCRIPT"
        exit 1
    fi
    
    # Create/rotate log file
    if [ -f "$LOG_FILE" ]; then
        # Rotate if log is larger than 10MB
        if [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]; then
            mv "$LOG_FILE" "$LOG_FILE.old"
        fi
    fi
    
    # Start the server in background with nohup
    cd "$SCRIPT_DIR"
    nohup node "$NODE_SCRIPT" >> "$LOG_FILE" 2>&1 &
    PID=$!
    
    # Save PID
    echo $PID > "$PID_FILE"
    
    # Wait a moment and check if it's running
    sleep 2
    if ps -p "$PID" > /dev/null 2>&1; then
        print_success "Server started successfully (PID: $PID)"
        echo ""
        print_status "Access the dashboard at: http://localhost:3000"
        print_status "View logs: $LOG_FILE"
        print_status "Stop server: ./start-hamclock.sh stop"
        echo ""
    else
        print_error "Server failed to start. Check logs: $LOG_FILE"
        rm -f "$PID_FILE"
        exit 1
    fi
}

# Stop the server
stop_server() {
    print_status "Stopping OpenHamClock server..."
    
    PID=$(get_pid 2>/dev/null)
    if [ -z "$PID" ]; then
        print_warning "Server is not running"
        return 0
    fi
    
    # Send SIGTERM for graceful shutdown
    kill -TERM "$PID" 2>/dev/null || true
    
    # Wait up to 10 seconds for graceful shutdown
    for i in {1..10}; do
        if ! ps -p "$PID" > /dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    
    # Force kill if still running
    if ps -p "$PID" > /dev/null 2>&1; then
        print_warning "Server did not stop gracefully, forcing shutdown..."
        kill -KILL "$PID" 2>/dev/null || true
        sleep 1
    fi
    
    # Clean up PID file
    rm -f "$PID_FILE"
    
    print_success "Server stopped"
}

# Restart the server
restart_server() {
    stop_server
    sleep 1
    start_server
}

# Show server status
show_status() {
    PID=$(get_pid 2>/dev/null)
    
    echo ""
    echo "═══════════════════════════════════════"
    echo "  OpenHamClock Server Status"
    echo "═══════════════════════════════════════"
    echo ""
    
    if [ -n "$PID" ]; then
        print_success "Server is RUNNING"
        echo "  PID:       $PID"
        
        # Get uptime
        if command -v ps &> /dev/null; then
            UPTIME=$(ps -p "$PID" -o etime= 2>/dev/null | xargs || echo "unknown")
            echo "  Uptime:    $UPTIME"
        fi
        
        # Get memory usage
        if command -v ps &> /dev/null; then
            MEM=$(ps -p "$PID" -o rss= 2>/dev/null | xargs || echo "unknown")
            if [ "$MEM" != "unknown" ]; then
                MEM_MB=$((MEM / 1024))
                echo "  Memory:    ${MEM_MB} MB"
            fi
        fi
        
        # Get CPU usage
        if command -v ps &> /dev/null; then
            CPU=$(ps -p "$PID" -o %cpu= 2>/dev/null | xargs || echo "unknown")
            if [ "$CPU" != "unknown" ]; then
                echo "  CPU:       ${CPU}%"
            fi
        fi
        
        echo ""
        echo "  Dashboard: http://localhost:3000"
        echo "  Log file:  $LOG_FILE"
        echo ""
        
        # Show last few log lines
        if [ -f "$LOG_FILE" ]; then
            echo "Recent log entries:"
            echo "───────────────────────────────────────"
            tail -n 5 "$LOG_FILE" | sed 's/^/  /'
            echo ""
        fi
    else
        print_error "Server is NOT running"
        echo ""
        
        # Check for recent crashes
        if [ -f "$LOG_FILE" ]; then
            echo "Last log entries (server may have crashed):"
            echo "───────────────────────────────────────"
            tail -n 10 "$LOG_FILE" | sed 's/^/  /'
            echo ""
        fi
    fi
    
    echo "═══════════════════════════════════════"
    echo ""
}

# View logs
view_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        print_warning "No log file found at $LOG_FILE"
        return
    fi
    
    echo ""
    print_status "Viewing OpenHamClock logs (Ctrl+C to exit)"
    echo ""
    
    # Use 'less' if available, otherwise 'tail -f'
    if command -v less &> /dev/null; then
        less +G "$LOG_FILE"
    else
        tail -f "$LOG_FILE"
    fi
}

# Main command handler
case "${1:-start}" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        restart_server
        ;;
    status)
        show_status
        ;;
    logs)
        view_logs
        ;;
    *)
        echo ""
        echo "OpenHamClock - Background Server Manager"
        echo ""
        echo "Usage: $0 {start|stop|restart|status|logs}"
        echo ""
        echo "Commands:"
        echo "  start     - Start the server in background"
        echo "  stop      - Stop the running server"
        echo "  restart   - Restart the server"
        echo "  status    - Show server status"
        echo "  logs      - View server logs"
        echo ""
        exit 1
        ;;
esac

exit 0

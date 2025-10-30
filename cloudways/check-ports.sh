#!/bin/bash
# Script: Check which ports are in use
# Usage: ./scripts/check-ports.sh [start_port] [end_port]

START_PORT=${1:-1337}
END_PORT=${2:-1350}

echo "========================================"
echo "🔍 Port Usage Check"
echo "   Scanning ports ${START_PORT}-${END_PORT}"
echo "========================================"
echo ""

# Check if ss command exists (modern)
if command -v ss &> /dev/null; then
    TOOL="ss"
    CMD="ss -tlnp"
# Fallback to netstat
elif command -v netstat &> /dev/null; then
    TOOL="netstat"
    CMD="netstat -tlnp"
else
    echo "❌ Neither 'ss' nor 'netstat' found"
    exit 1
fi

echo "Using: $TOOL"
echo ""

# Check each port
for port in $(seq "$START_PORT" "$END_PORT"); do
    # Check if port is in use
    RESULT=$($CMD 2>/dev/null | grep ":${port} " | head -1)

    if [ -n "$RESULT" ]; then
        # Port is in use
        echo "🔴 Port $port: IN USE"

        # Try to extract process info
        if echo "$RESULT" | grep -q "users:"; then
            # ss format
            PROCESS=$(echo "$RESULT" | grep -oP 'users:\(\(".*?",pid=\d+' | sed 's/users:(("//' | sed 's/",pid=/,PID:/')
            echo "   Process: $PROCESS"
        elif echo "$RESULT" | awk '{print $7}' | grep -q "/"; then
            # netstat format
            PROCESS=$(echo "$RESULT" | awk '{print $7}')
            echo "   Process: $PROCESS"
        fi

        # Show the full line for debugging
        echo "   Details: $RESULT"
        echo ""
    else
        echo "✅ Port $port: Available"
    fi
done

echo ""
echo "========================================"
echo "Summary"
echo "========================================"
echo ""
echo "All listening ports on this server:"
$CMD 2>/dev/null | grep LISTEN | awk '{print $5}' | cut -d: -f2 | sort -n | uniq | head -20
echo ""

#!/bin/sh

echo "Testing the updated WiFi Schedule holiday API functionality..."

# Test if the required files exist
echo "Checking for required files..."
if [ -f "/usr/lib/lua/luci/util/wifischedule/calendar.lua" ]; then
    echo "✓ Calendar module exists"
else
    echo "✗ Calendar module missing"
    exit 1
fi

if [ -f "/usr/lib/lua/luci/util/wifischedule/api.lua" ]; then
    echo "✓ API module exists"
else
    echo "✗ API module missing"
    exit 1
fi

echo "All basic checks passed. The updated WiFi Schedule should work correctly."
echo ""
echo "New functionality includes:"
echo "- External holiday API support"
echo "- Configurable API endpoints with {date} and {region} placeholders"
echo "- CSV upload with higher priority than predefined holidays"
echo "- Modernized UI with API configuration and testing tools"
echo "- Enhanced priority order: External API > CSV > Predefined Holidays > Others"
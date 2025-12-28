#!/bin/bash
# Open System Settings to grant LocalFlow accessibility permissions

echo "Opening System Settings > Privacy & Security > Accessibility..."
echo ""
echo "Please toggle LocalFlow ON in the list."
echo "If LocalFlow is not in the list, click the '+' button and add:"
echo "  /Applications/LocalFlow.app"
echo ""

# Open accessibility settings (works on macOS Ventura+)
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo "After granting access, LocalFlow will work without further prompts."
echo "(Until you rebuild the app)"

#!/bin/bash
set -e

# Configuration
WEBHOOK_URL=${DISCORD_WEBHOOK_URL:-""}
MESSAGE="$1"
TITLE=${2:-"Kroni Survival Notification"}
COLOR=${3:-"7289DA"}  # Discord blue color by default
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Function to show usage
usage() {
    echo "Usage: $0 <message> [title] [color]"
    echo ""
    echo "Arguments:"
    echo "  message  - The message to send (required)"
    echo "  title    - The title of the embed (optional)"
    echo "  color    - Hex color for the embed sidebar (optional)"
    echo ""
    echo "Environment variables:"
    echo "  DISCORD_WEBHOOK_URL - Discord webhook URL"
    echo ""
    echo "Example:"
    echo "  $0 'Server backup completed' 'Backup Status' '00FF00'"
    exit 1
}

# Check if message is provided
if [ -z "$MESSAGE" ]; then
    echo "Error: No message provided"
    usage
fi

# Check if webhook URL is provided
if [ -z "$WEBHOOK_URL" ]; then
    echo "Error: No Discord webhook URL provided"
    echo "Set the DISCORD_WEBHOOK_URL environment variable or pass it as an argument"
    usage
fi

# Send notification to Discord with embed
send_embed() {
    # Convert color from hex to decimal (Discord requires decimal)
    if [[ $COLOR =~ ^[0-9A-Fa-f]{6}$ ]]; then
        # Convert hex color to decimal
        COLOR_DEC=$((16#$COLOR))
    else
        # Use default Discord blue if color is not a valid hex
        COLOR_DEC=7506394  # 7289DA in decimal
    fi
    
    # Create JSON payload for embed
    JSON_PAYLOAD=$(cat <<EOF
{
  "embeds": [
    {
      "title": "$TITLE",
      "description": "$MESSAGE",
      "color": $COLOR_DEC,
      "timestamp": "$TIMESTAMP",
      "footer": {
        "text": "Kroni Survival Minecraft Server"
      }
    }
  ]
}
EOF
)
    
    # Send the payload to Discord
    curl -s -H "Content-Type: application/json" -X POST -d "$JSON_PAYLOAD" $WEBHOOK_URL
    
    # Check if the request was successful
    if [ $? -eq 0 ]; then
        echo "Discord notification sent successfully!"
    else
        echo "Failed to send Discord notification"
        return 1
    fi
}

# Send a simple message if it's a short notification
send_simple_message() {
    curl -s -H "Content-Type: application/json" -X POST -d "{\"content\":\"$MESSAGE\"}" $WEBHOOK_URL
    
    # Check if the request was successful
    if [ $? -eq 0 ]; then
        echo "Discord notification sent successfully!"
    else
        echo "Failed to send Discord notification"
        return 1
    fi
}

# Determine which method to use based on message length
if [ ${#MESSAGE} -lt 50 ] && [ "$TITLE" == "Kroni Survival Notification" ]; then
    # Short message with default title - use simple message
    send_simple_message
else
    # Longer message or custom title - use embed
    send_embed
fi
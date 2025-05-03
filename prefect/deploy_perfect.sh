#!/bin/bash
# deploy_prefect.sh

# Usage: ./deploy_prefect.sh [command]
# Commands:
#   deploy - Deploy Prefect using Docker Compose
#   status - Check status of Prefect services
#   logs   - View logs of Prefect services
#   update - Update Prefect images and restart services

COMMAND=${1:-status}

case $COMMAND in
  deploy)
    echo "Deploying Prefect services..."
    docker-compose up -d
    ;;
  status)
    echo "Checking Prefect services status..."
    docker-compose ps
    ;;
  logs)
    echo "Viewing Prefect logs..."
    docker-compose logs -f
    ;;
  update)
    echo "Updating Prefect services..."
    docker-compose pull
    docker-compose down
    docker-compose up -d
    ;;
  *)
    echo "Unknown command: $COMMAND"
    echo "Usage: $0 [deploy|status|logs|update]"
    exit 1
    ;;
esac
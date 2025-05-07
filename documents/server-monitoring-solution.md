# Server Monitoring Architecture Documentation

## Executive Summary

This document outlines a modernized approach to server monitoring architecture for the Minecraft server infrastructure. The proposal shifts from direct SSH-based monitoring to an API-driven approach, ensuring better security, scalability, and reliability in the monitoring system. This approach aligns with industry best practices and maintains separation of concerns while enhancing overall system resilience.

## Current Architecture Challenges

Based on the infrastructure code reviewed, the current monitoring approach relies heavily on direct SSH access to collect metrics and perform management tasks. This approach presents several challenges:

1. Security concerns with password/key management and persistent SSH connections
2. Reliance on network stability for monitoring operations
3. Limited scalability when monitoring multiple instances
4. Tight coupling between monitoring and server infrastructure
5. Authentication and authorization complexity

## Proposed Architecture

### Core Architecture Principles

1. **Separation of Concerns**: Decouple the monitoring from direct server access
2. **API-First Approach**: Expose server metrics through a secure REST API
3. **Zero-Trust Security**: Implement proper authentication and authorization
4. **Stateless Communication**: Eliminate persistent connections for resilience
5. **Observability**: Enhanced visibility into system health and performance

### Component Design

#### 1. Server-Side Metrics Collector

Deploy a lightweight agent on the Minecraft server that:

- Collects system metrics (CPU, memory, disk, network)
- Monitors Minecraft-specific metrics (TPS, connected players, etc.)
- Exposes metrics through a secure REST API endpoint
- Implements proper authentication via API keys

```
┌──────────────────────────────────┐
│        Minecraft Server          │
│                                  │
│  ┌──────────────────────────┐    │
│  │     Metrics Collector    │    │
│  │                          │    │
│  │  - System Metrics        │    │
│  │  - Minecraft Metrics     │    │
│  │  - Resource Utilization  │    │
│  └───────────┬──────────────┘    │
│              │                   │
│  ┌───────────▼──────────────┐    │
│  │      REST API Server     │    │
│  │                          │    │
│  │  - Authentication        │    │
│  │  - Rate Limiting         │    │
│  │  - Metrics Endpoints     │    │
│  └───────────┬──────────────┘    │
└──────────────┼──────────────────┘
               │
               ▼
      [Secure API Endpoint]
```

#### 2. Prefect Monitoring Flows

Update the Prefect orchestration to:

- Use API calls instead of SSH for data collection
- Implement scheduled polling of metrics endpoints
- Transform and analyze the collected data
- Send notifications through Discord webhooks
- Support thresholds and alerting logic

```
┌──────────────────────────────────┐
│      Prefect Orchestration       │
│                                  │
│  ┌──────────────────────────┐    │
│  │    Monitoring Flows      │    │
│  │                          │    │
│  │  - API Client            │    │
│  │  - Metrics Processing    │    │
│  │  - Alert Logic           │    │
│  └───────────┬──────────────┘    │
│              │                   │
│  ┌───────────▼──────────────┐    │
│  │   Notification Service   │    │
│  │                          │    │
│  │  - Discord Integration   │    │
│  │  - Alert Formatting      │    │
│  │  - Rate Limiting         │    │
│  └──────────────────────────┘    │
└──────────────────────────────────┘
```

## Implementation Plan

### Phase 1: API Server Deployment

1. **Develop the Metrics Collector Agent**:
   - Use a lightweight framework like Flask or FastAPI
   - Implement system and Minecraft metrics collection
   - Expose secure REST API endpoints with proper authentication

2. **Deployment on Minecraft Server**:
   - Deploy as a Docker container alongside Minecraft
   - Configure proper networking and firewall rules
   - Implement TLS for secure communication

### Phase 2: Prefect Flow Updates

1. **Create API Client for Prefect**:
   - Develop a Python client for the metrics API
   - Implement authentication and error handling
   - Create data models for metrics processing

2. **Update Monitoring Flows**:
   - Replace SSH-based scripts with API calls
   - Implement data transformation and analysis
   - Configure webhooks for notifications

### Phase 3: Testing and Migration

1. **Parallel Operation**:
   - Run both systems simultaneously for comparison
   - Validate metrics accuracy and performance
   - Test alerting and notification functionality

2. **Gradual Transition**:
   - Migrate monitoring functions one by one
   - Monitor for any discrepancies or issues
   - Phase out SSH-based monitoring gradually

## Detailed Technical Specifications

### Metrics API Endpoints

| Endpoint | Description | Authentication |
|----------|-------------|----------------|
| `/api/v1/system/metrics` | System metrics (CPU, memory, disk) | API Key |
| `/api/v1/minecraft/metrics` | Minecraft-specific metrics | API Key |
| `/api/v1/minecraft/players` | Player statistics and counts | API Key |
| `/api/v1/health` | API health status check | None |

### Metrics Collector Implementation

```python
# server_metrics.py - Example implementation for the metrics collector

from fastapi import FastAPI, Depends, HTTPException, Security
from fastapi.security.api_key import APIKeyHeader
import psutil
import subprocess
import json
import os
import logging
from typing import Dict, Any

app = FastAPI(title="Minecraft Server Metrics API")

# Configure API key authentication
API_KEY = os.getenv("API_KEY")
api_key_header = APIKeyHeader(name="X-API-Key")

def get_api_key(api_key: str = Security(api_key_header)):
    if api_key == API_KEY:
        return api_key
    raise HTTPException(status_code=403, detail="Invalid API Key")

# System metrics endpoint
@app.get("/api/v1/system/metrics", dependencies=[Depends(get_api_key)])
async def get_system_metrics():
    return {
        "cpu": {
            "usage_percent": psutil.cpu_percent(interval=1),
            "load_avg": os.getloadavg()
        },
        "memory": {
            "total": psutil.virtual_memory().total,
            "available": psutil.virtual_memory().available,
            "used_percent": psutil.virtual_memory().percent
        },
        "disk": {
            "total": psutil.disk_usage("/").total,
            "used": psutil.disk_usage("/").used,
            "used_percent": psutil.disk_usage("/").percent
        },
        "network": {
            "bytes_sent": psutil.net_io_counters().bytes_sent,
            "bytes_recv": psutil.net_io_counters().bytes_recv
        }
    }

# Minecraft metrics endpoint
@app.get("/api/v1/minecraft/metrics", dependencies=[Depends(get_api_key)])
async def get_minecraft_metrics():
    # Implement Minecraft-specific metrics collection
    # This is a simplified example - actual implementation would connect to Minecraft
    return {
        "tps": get_minecraft_tps(),
        "uptime": get_minecraft_uptime(),
        "world_size": get_world_size()
    }

# Health check endpoint (no auth required)
@app.get("/api/v1/health")
async def health_check():
    return {"status": "healthy"}

# Helper functions for Minecraft metrics
def get_minecraft_tps():
    # Implementation for getting TPS from Minecraft
    # Could use RCON, logs, or other methods
    return 20.0  # Example value

def get_minecraft_uptime():
    # Get container uptime or process uptime
    return 3600  # Example: 1 hour in seconds

def get_world_size():
    # Get world directory size
    world_path = os.getenv("MINECRAFT_WORLD_PATH", "/data/world")
    try:
        total_size = 0
        for dirpath, dirnames, filenames in os.walk(world_path):
            for f in filenames:
                fp = os.path.join(dirpath, f)
                total_size += os.path.getsize(fp)
        return total_size
    except Exception as e:
        logging.error(f"Error getting world size: {e}")
        return 0

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

### Prefect Monitoring Flow Implementation

```python
# monitoring_flow.py - Example implementation for the Prefect monitoring flow

from prefect import flow, task
import requests
import json
from datetime import datetime
import time

# API configuration
API_BASE_URL = "http://minecraft-server-ip:8000/api/v1"
API_KEY = "your-secure-api-key"
DISCORD_WEBHOOK_URL = "your-discord-webhook-url"

@task
def fetch_system_metrics():
    """Fetch system metrics from the API"""
    headers = {"X-API-Key": API_KEY}
    response = requests.get(f"{API_BASE_URL}/system/metrics", headers=headers)
    
    if response.status_code == 200:
        return response.json()
    else:
        raise Exception(f"Failed to fetch system metrics: {response.status_code}")

@task
def fetch_minecraft_metrics():
    """Fetch Minecraft-specific metrics from the API"""
    headers = {"X-API-Key": API_KEY}
    response = requests.get(f"{API_BASE_URL}/minecraft/metrics", headers=headers)
    
    if response.status_code == 200:
        return response.json()
    else:
        raise Exception(f"Failed to fetch Minecraft metrics: {response.status_code}")

@task
def analyze_metrics(system_metrics, minecraft_metrics):
    """Analyze the collected metrics and determine if alerts are needed"""
    alerts = []
    
    # CPU usage alert
    if system_metrics["cpu"]["usage_percent"] > 90:
        alerts.append({
            "level": "warning",
            "message": f"High CPU usage: {system_metrics['cpu']['usage_percent']}%"
        })
    
    # Memory usage alert
    if system_metrics["memory"]["used_percent"] > 85:
        alerts.append({
            "level": "warning",
            "message": f"High memory usage: {system_metrics['memory']['used_percent']}%"
        })
    
    # Disk usage alert
    if system_metrics["disk"]["used_percent"] > 90:
        alerts.append({
            "level": "critical",
            "message": f"Critical disk usage: {system_metrics['disk']['used_percent']}%"
        })
    
    # Minecraft TPS alert
    if minecraft_metrics["tps"] < 15:
        alerts.append({
            "level": "warning",
            "message": f"Low TPS: {minecraft_metrics['tps']}"
        })
    
    return {
        "timestamp": datetime.now().isoformat(),
        "system": system_metrics,
        "minecraft": minecraft_metrics,
        "alerts": alerts
    }

@task
def send_discord_notification(data):
    """Send notifications to Discord for alerts"""
    if not data["alerts"]:
        return  # No alerts to send
    
    # Format message for Discord
    message = {
        "content": f"Server Monitoring Alert - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "embeds": []
    }
    
    for alert in data["alerts"]:
        embed = {
            "title": f"{alert['level'].upper()} Alert",
            "description": alert["message"],
            "color": 16711680 if alert["level"] == "critical" else 16776960
        }
        message["embeds"].append(embed)
    
    # Add system metrics summary
    system_summary = {
        "title": "System Metrics",
        "fields": [
            {
                "name": "CPU Usage",
                "value": f"{data['system']['cpu']['usage_percent']}%",
                "inline": True
            },
            {
                "name": "Memory Usage",
                "value": f"{data['system']['memory']['used_percent']}%",
                "inline": True
            },
            {
                "name": "Disk Usage",
                "value": f"{data['system']['disk']['used_percent']}%",
                "inline": True
            }
        ],
        "color": 3447003
    }
    message["embeds"].append(system_summary)
    
    # Add Minecraft metrics summary
    minecraft_summary = {
        "title": "Minecraft Metrics",
        "fields": [
            {
                "name": "TPS",
                "value": str(data['minecraft']['tps']),
                "inline": True
            },
            {
                "name": "Uptime",
                "value": f"{data['minecraft']['uptime'] // 3600} hours",
                "inline": True
            },
            {
                "name": "World Size",
                "value": f"{data['minecraft']['world_size'] // (1024*1024)} MB",
                "inline": True
            }
        ],
        "color": 3447003
    }
    message["embeds"].append(minecraft_summary)
    
    # Send to Discord
    response = requests.post(
        DISCORD_WEBHOOK_URL,
        json=message,
        headers={"Content-Type": "application/json"}
    )
    
    if response.status_code != 204:
        raise Exception(f"Failed to send Discord notification: {response.status_code}")

@flow(name="server_monitoring_flow")
def server_monitoring_flow():
    """Main monitoring flow that orchestrates the metric collection and analysis"""
    # Fetch metrics from API
    system_metrics = fetch_system_metrics()
    minecraft_metrics = fetch_minecraft_metrics()
    
    # Analyze metrics and generate alerts
    analysis = analyze_metrics(system_metrics, minecraft_metrics)
    
    # Send notifications if there are alerts
    if analysis["alerts"]:
        send_discord_notification(analysis)
    
    return analysis

if __name__ == "__main__":
    # For testing or standalone execution
    server_monitoring_flow()
```

## Docker Implementation

### Docker Compose for Metrics API

```yaml
version: '3'

services:
  minecraft:
    image: ${MINECRAFT_DOCKER_IMAGE}
    container_name: minecraft-server
    ports:
      - "${MINECRAFT_SERVER_PORT}:25565"
    volumes:
      - ${MINECRAFT_WORLD_PATH}:/data
    environment:
      - EULA=TRUE
    restart: unless-stopped
  
  metrics-api:
    image: minecraft-metrics-api:latest
    build:
      context: ./metrics-api
      dockerfile: Dockerfile
    container_name: minecraft-metrics-api
    ports:
      - "8000:8000"
    environment:
      - API_KEY=${API_KEY}
      - MINECRAFT_WORLD_PATH=/data/world
    volumes:
      - ${MINECRAFT_WORLD_PATH}:/data:ro
    depends_on:
      - minecraft
    restart: unless-stopped
```

### Metrics API Dockerfile

```dockerfile
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "server_metrics:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Security Considerations

1. **API Authentication**:
   - Use API keys or JWT tokens for authentication
   - Implement rate limiting to prevent abuse
   - Consider IP whitelisting for additional security

2. **HTTPS Encryption**:
   - Use TLS for all API communications
   - Implement proper certificate management
   - Consider using Let's Encrypt for free certificates

3. **Least Privilege Principle**:
   - The metrics API should only have read-only access
   - Run the API container with minimal permissions
   - Implement proper user isolation in containers

4. **Secrets Management**:
   - Store API keys and credentials securely
   - Use environment variables for configuration
   - Consider AWS Secrets Manager for sensitive data

## Monitoring and Alerting Best Practices

1. **Alert Fatigue Prevention**:
   - Implement proper thresholds to avoid false positives
   - Use escalation policies for critical alerts
   - Implement alert suppression for known issues

2. **Data Retention**:
   - Store historical metrics for trend analysis
   - Implement proper data retention policies
   - Consider time-series databases for efficient storage

3. **Comprehensive Monitoring**:
   - Monitor both system and application metrics
   - Track user experience metrics (e.g., player counts)
   - Monitor infrastructure components (e.g., S3 backups)

## Conclusion

This API-based monitoring architecture provides a more scalable, secure, and reliable approach compared to the current SSH-based method. By implementing this design, you'll achieve:

1. Improved security through proper authentication and encryption
2. Better reliability with stateless communication
3. Enhanced scalability for monitoring multiple instances
4. Cleaner separation of concerns in the architecture
5. Industry-standard compliance with modern monitoring practices

The implementation can be phased in gradually, allowing for validation and comparison with the existing system before fully transitioning to the new approach.
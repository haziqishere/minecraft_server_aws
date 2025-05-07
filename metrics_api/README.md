# Minecraft Server Metrics API

A REST API server that exposes system and Minecraft server metrics for monitoring purposes without requiring direct SSH access.

## Overview

The Metrics API provides a secure and efficient way to collect monitoring data from the Minecraft server. It eliminates the need for SSH-based monitoring and follows modern API-driven architecture principles.

## Endpoints

The API provides the following endpoints:

### Health Check (no authentication required)

```
GET /api/v1/health
```

Returns the current health status of the API server.

### System Metrics (requires API key)

```
GET /api/v1/system/metrics
```

Returns detailed system metrics including CPU, memory, disk, and network usage.

### Minecraft Metrics (requires API key)

```
GET /api/v1/minecraft/metrics
```

Returns Minecraft server-specific metrics including container status, resource usage, and world size.

### Player Information (requires API key)

```
GET /api/v1/minecraft/players
```

Returns information about connected players and server status.

## Authentication

The API uses API key authentication. Include the API key in the request header:

```
X-API-Key: your-api-key
```

### API Key Management

The API key is dynamically generated in several ways:

1. **GitHub Workflow Deployment**: When deployed via the GitHub workflow, a secure random key is automatically generated, unless you provide a custom key through the workflow inputs.

2. **Environment Variable**: You can set the `METRICS_API_KEY` environment variable before starting the container.

3. **Auto-generation**: If no key is provided, the API server will generate a random key at startup and log it to the console.

### Retrieving the API Key

After deployment, the API key is stored in:

- The file `/opt/metrics-api/api_key.txt` on the Minecraft server
- Environment variables in the Prefect server (automatically configured by the deployment workflow)
- GitHub Actions workflow logs (first deployment only)

## Deployment

### Using the GitHub Workflow (Recommended)

The easiest way to deploy the API is using the included GitHub workflow:

1. Push changes to the `metrics_api` directory
2. The workflow automatically:
   - Builds and deploys the Docker container on the Minecraft server
   - Configures the API key and environment
   - Updates the Prefect server to use the API
   - Opens the necessary firewall ports

You can also manually trigger the workflow from GitHub Actions UI with an optional custom API key.

### Manual Deployment

#### Using Docker Compose

1. Copy the files in the `metrics_api` directory to the server
2. Configure the API key in `.env` file or environment variable
3. Run `docker-compose up -d` to start the API server

## Configuration

The API can be configured using environment variables:

- `METRICS_API_KEY`: API key for authentication (auto-generated if not provided)
- `METRICS_API_PORT`: Port to run the API server on (default: 8000)
- `MINECRAFT_WORLD_PATH`: Path to the Minecraft world directory (default: /data/world)

## Example Usage

```bash
# Health check
curl http://localhost:8000/api/v1/health

# Get system metrics with API key
curl -H "X-API-Key: your-api-key" http://localhost:8000/api/v1/system/metrics

# Get Minecraft metrics with API key
curl -H "X-API-Key: your-api-key" http://localhost:8000/api/v1/minecraft/metrics

# Get player information with API key
curl -H "X-API-Key: your-api-key" http://localhost:8000/api/v1/minecraft/players
```

## Benefits Over SSH-Based Monitoring

1. **Improved Security**: No need to manage SSH keys or expose SSH access
2. **Better Performance**: Lower overhead compared to establishing SSH connections
3. **Scalability**: Easier to monitor multiple instances or add more metrics
4. **Reliability**: Stateless communication is more robust
5. **Separation of Concerns**: Clean separation between monitoring and server infrastructure 
# API-Based Monitoring Implementation Plan

This document outlines the steps to transition from SSH-based monitoring to API-based monitoring for the Minecraft server infrastructure. This approach provides better security, scalability, and reliability as outlined in the server-monitoring-solution document.

## Implementation Steps

### Phase 1: Deploy API Server on Minecraft VM

1. **Prepare the Metrics API Server**
   - Copy `scripts/deploy_metrics_api.sh` to the Minecraft server
   - Make the script executable with `chmod +x deploy_metrics_api.sh`
   - Run the script to deploy the Metrics API: `./deploy_metrics_api.sh deploy`
   - Verify the API is running: `curl http://localhost:8000/api/v1/health`
   - Note the generated API key for future use

2. **Security Configuration**
   - Update the Lightsail firewall to allow inbound traffic on port 8000
   - Configure the API to use a strong API key
   - In production, restrict CORS to specific origins

### Phase 2: Update Prefect Flow to Use API

1. **Update Server Monitoring Flow**
   - Replace the SSH-based monitoring in `server_monitoring_flow.py` with API calls
   - Configure the flow to use the Metrics API URL and API key
   - Test the flow locally to ensure it can connect to the API

2. **Update Prefect Server Configuration**
   - Copy the updated `server_monitoring_flow.py` to the Prefect server
   - Configure environment variables for the API URL and API key
   - Restart the Prefect containers to pick up the new environment variables

### Phase 3: Testing and Validation

1. **Run Test Monitoring Flow**
   - Run the updated monitoring flow manually to verify it can collect metrics
   - Check Discord notifications to ensure they contain the correct metrics
   - Monitor the API server logs to ensure requests are being handled properly

2. **Verify API Performance**
   - Monitor API response times to ensure they are acceptable
   - Check for any errors or exceptions in the API logs
   - Verify the API can handle the expected request rate

### Phase 4: Full Deployment and Migration

1. **Schedule Regular Monitoring**
   - Deploy the updated flow to run on a regular schedule
   - Monitor for any issues during the first few runs
   - Verify metrics are consistent with previous SSH-based monitoring

2. **Remove SSH-Based Monitoring**
   - Once API-based monitoring is confirmed to be working properly, remove SSH-based monitoring code
   - Update any documentation to reflect the new monitoring approach
   - Consider removing unnecessary SSH access if no longer needed for monitoring

## Rollback Plan

If issues are encountered with the API-based monitoring, the following rollback steps should be taken:

1. **Revert to SSH-Based Monitoring**
   - Restore the previous version of `server_monitoring_flow.py`
   - Redeploy the flow to use SSH-based monitoring
   - Stop the Metrics API server

2. **Troubleshoot API Issues**
   - Check API logs for errors or exceptions
   - Verify API server resource usage
   - Check network connectivity between Prefect and the Minecraft server

## Execution Commands

### On the Minecraft Server:

```bash
# Copy the deployment script
scp -i ~/.ssh/kroni-survival-key.pem scripts/deploy_metrics_api.sh ec2-user@MINECRAFT_SERVER_IP:~/

# Connect to the server
ssh -i ~/.ssh/kroni-survival-key.pem ec2-user@MINECRAFT_SERVER_IP

# Deploy the Metrics API
chmod +x deploy_metrics_api.sh
./deploy_metrics_api.sh deploy

# Check API status
./deploy_metrics_api.sh status
```

### On the Prefect Server:

```bash
# Run the update script
./scripts/update_prefect_for_api.sh

# Or manually:
scp -i ~/.ssh/kroni-survival-key.pem prefect/flows/server_monitoring_flow.py ec2-user@PREFECT_SERVER_IP:~/prefect/flows/
ssh -i ~/.ssh/kroni-survival-key.pem ec2-user@PREFECT_SERVER_IP
cd ~/prefect
docker-compose down
docker-compose up -d
```

## Expected Outcomes

After implementing this plan, the following outcomes should be achieved:

1. The Metrics API is running on the Minecraft server VM
2. The Prefect server monitoring flow is using API calls instead of SSH
3. Monitoring metrics are being collected and sent to Discord
4. SSH is no longer required for monitoring operations

## Security Considerations

1. The API key must be kept secure and not exposed in public repositories
2. The API should only be accessible from the Prefect server IP address
3. Consider implementing additional security measures like IP whitelisting
4. Regular monitoring logs should be checked for unauthorized access attempts 
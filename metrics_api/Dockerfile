FROM python:3.11-slim

WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY metrics_api_server.py .

# Create directory for data if needed
RUN mkdir -p /data

# Set environment variables
ENV METRICS_API_PORT=8000
ENV METRICS_API_KEY=""

# Expose the port
EXPOSE 8000

# Run the application
CMD ["python", "metrics_api_server.py"] 
FROM python:3.11-slim

# Install dependencies
RUN pip install --no-cache-dir fastapi uvicorn requests websockets python-multipart

# Create app directory
WORKDIR /app

# Copy source
COPY serve_agent.py /app/

# Environment defaults (can be overridden by Fly API)
ENV HOST=0.0.0.0 PORT=8080 PYTHONUNBUFFERED=1

# Expose internal port
EXPOSE 8080

# Start agent server
CMD ["uvicorn", "serve_agent:app", "--host", "0.0.0.0", "--port", "8080"]
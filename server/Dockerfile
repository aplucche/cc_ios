FROM python:3.11-slim

# Install dependencies including curl for Claude Code installation and tmux for session management
RUN apt-get update && apt-get install -y \
    curl \
    tmux \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir fastapi uvicorn requests websockets python-multipart

# Install Claude Code CLI using native installer
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && ln -sf ~/.local/bin/claude /usr/local/bin/claude

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
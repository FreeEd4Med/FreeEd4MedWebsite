FROM python:3.10-slim

# Prevent Python from writing pyc files and buffering stdout
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
# ffmpeg: for media processing
# imagemagick: for image processing
# fonts-liberation: for text rendering
# procps: for ps command if needed
RUN apt-get update && apt-get install -y \
    ffmpeg \
    imagemagick \
    fonts-liberation \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Fix ImageMagick policy to allow PDF/Text operations if needed
# We use find because the path varies between Debian versions (ImageMagick-6 vs ImageMagick)
RUN find /etc -name "policy.xml" -exec sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/' {} +

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy all scripts
COPY . .

# Make main script executable
RUN chmod +x freeed_media_super_tool.sh

# Create a volume mount point for user media
WORKDIR /data

# Set the entrypoint to the main script
# We use bash explicitly
ENTRYPOINT ["/bin/bash", "/app/freeed_media_super_tool.sh"]

# Use Python 3.11 slim image
FROM python:3.11-slim

# Allow statements and log messages to immediately appear in the logs
ENV PYTHONUNBUFFERED True

# Set working directory
WORKDIR /app

# Install dependencies
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code
COPY . ./

# Cloud Run uses PORT environment variable
ENV PORT 8080
EXPOSE 8080

# Run the Flask app
CMD ["python", "app/main.py"]

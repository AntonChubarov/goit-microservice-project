# Runtime-only env is passed via Kubernetes; do NOT bake secrets here.
FROM python:3.10-slim

# Helpful Python flags for containers
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install deps first (better layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# NOTE:
# DB settings must be injected at runtime by Kubernetes/Helm via env:
#   POSTGRES_HOST, POSTGRES_PORT, POSTGRES_NAME, POSTGRES_USER, POSTGRES_PASSWORD
# Do NOT set them here to avoid leaking secrets and build-time warnings.

# Copy app source (assumes manage.py is in the build context root)
COPY . .

EXPOSE 8000
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]

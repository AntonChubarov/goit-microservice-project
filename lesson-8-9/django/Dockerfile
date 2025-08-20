FROM python:3.10-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

#ENV POSTGRES_HOST=${POSTGRES_HOST}
#ENV POSTGRES_PORT=${POSTGRES_PORT}
#ENV POSTGRES_NAME=${POSTGRES_NAME}
#ENV POSTGRES_USER=${POSTGRES_USER}
#ENV POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Copy the whole django folder (where manage.py lives)
COPY . .

CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]

EXPOSE 8000
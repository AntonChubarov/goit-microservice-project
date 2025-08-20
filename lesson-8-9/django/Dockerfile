FROM python:3.10-slim

WORKDIR /app

# Copy requirements from the nested folder (build context = repo root)
COPY lesson-8-9/django/requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

# Copy the entire Django app directory so manage.py is present at /app/manage.py
COPY lesson-8-9/django/ .

CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]

EXPOSE 8000

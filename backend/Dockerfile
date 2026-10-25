FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY alembic.ini .
COPY alembic ./alembic
COPY docker-start.sh .
COPY docker-migrate.sh .

RUN useradd --create-home appuser
USER appuser
EXPOSE 8000
CMD ["sh", "/app/docker-start.sh"]

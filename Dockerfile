FROM python:3.12-slim

WORKDIR /app

# Install uv (Rust-based ultra-fast Python package installer)
RUN pip install --no-cache-dir uv

COPY requirements.txt ./
RUN uv pip install --system --no-cache-dir -r requirements.txt

COPY ./app ./app
COPY ./start_services.py ./start_services.py
COPY ./worker.py ./worker.py

ENV PYTHONPATH=/app

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--loop", "uvloop"]
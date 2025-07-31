# UploadDocsService with Background Processing

A FastAPI-based document upload and processing service with background task processing using Celery and Redis.

## Features

- **Background Processing**: Document processing happens asynchronously using Celery workers
- **File Support**: Upload and process PDF and DOCX files
- **Text Extraction**: Extract text content from documents
- **Text Chunking**: Split documents into smaller chunks for processing
- **Progress Tracking**: Monitor task progress and status
- **Database Storage**: Store documents and chunks in SQLite database
- **RESTful API**: Clean API endpoints for all operations

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   FastAPI App   │    │   Celery Worker │    │     Redis       │
│                 │    │                 │    │                 │
│ - Upload files  │───▶│ - Process docs  │◀──▶│ - Task queue    │
│ - Check status  │    │ - Extract text  │    │ - Results store │
│ - List docs     │    │ - Chunk text    │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Prerequisites

- Python 3.8+
- Redis server
- Required Python packages (see `requirements.txt`)

## Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd UploadDocsService
   ```

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Install and start Redis**:
   
   **macOS**:
   ```bash
   brew install redis
   brew services start redis
   ```
   
   **Ubuntu/Debian**:
   ```bash
   sudo apt-get update
   sudo apt-get install redis-server
   sudo systemctl start redis-server
   ```
   
   **Windows**: Download from [Redis.io](https://redis.io/download)

4. **Initialize the database**:
   ```bash
   python -c "from app.backend.db import init_db; import asyncio; asyncio.run(init_db())"
   ```

## Usage

### Quick Start

Use the startup script to launch all services:

```bash
python start_services.py
```

This will:
- Check if Redis is running (start it if needed)
- Start Celery worker
- Start FastAPI server

### Manual Start

1. **Start Redis** (if not already running):
   ```bash
   redis-server
   ```

2. **Start Celery worker**:
   ```bash
   python worker.py
   ```

3. **Start FastAPI server**:
   ```bash
   uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```

## API Endpoints

### Upload Document
```http
POST /api/documents/
Content-Type: multipart/form-data

file: [PDF or DOCX file]
```

**Response**:
```json
{
  "task_id": "abc123-def456-ghi789",
  "status": "processing",
  "message": "Document uploaded and queued for processing"
}
```

### Check Task Status
```http
GET /api/documents/task/{task_id}
```

**Response**:
```json
{
  "task_id": "abc123-def456-ghi789",
  "state": "PROGRESS",
  "status": "Extracting text",
  "progress": 30
}
```

### List Documents
```http
GET /api/documents/?skip=0&limit=10
```

**Response**:
```json
{
  "documents": [
    {
      "id": 1,
      "filename": "document.pdf",
      "content_type": "application/pdf",
      "upload_time": "2024-01-01T12:00:00",
      "num_chunks": 5
    }
  ],
  "total_count": 1,
  "skip": 0,
  "limit": 10
}
```

### Get Document Chunks
```http
GET /api/documents/{document_id}/chunks?skip=0&limit=10
```

**Response**:
```json
{
  "document": {
    "id": 1,
    "filename": "document.pdf",
    "content_type": "application/pdf",
    "upload_time": "2024-01-01T12:00:00",
    "num_chunks": 5
  },
  "chunks": [
    {
      "id": 1,
      "chunk_index": 0,
      "text": "This is the first chunk of text..."
    }
  ],
  "total_chunks": 5,
  "skip": 0,
  "limit": 10
}
```

## Configuration

### Environment Variables

Create a `.env` file in the project root:

```env
# Database Configuration
DATABASE_URL=sqlite+aiosqlite:///./files.db

# Redis Configuration
REDIS_URL=redis://localhost:6379/0

# Celery Configuration
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0

# Application Configuration
MAX_FILE_SIZE_MB=20
CHUNK_SIZE=1000

# Logging
LOG_LEVEL=INFO
```

### Celery Configuration

The Celery configuration is in `app/celery_app.py`. Key settings:

- **Broker**: Redis for task queue
- **Backend**: Redis for result storage
- **Task Timeout**: 30 minutes
- **Worker Concurrency**: 2 (configurable)
- **Queues**: `default` and `document_processing`

## Background Tasks

### Document Processing Task

The main background task (`process_document`) performs:

1. **File Validation**: Check file type and size
2. **Text Extraction**: Extract text from PDF/DOCX
3. **Text Chunking**: Split into smaller pieces
4. **Database Storage**: Save document and chunks
5. **Progress Updates**: Report progress throughout

### Cleanup Task

A cleanup task (`cleanup_old_documents`) can be scheduled to remove old documents:

```python
from app.tasks import cleanup_old_documents

# Schedule cleanup for documents older than 30 days
cleanup_old_documents.delay(days_old=30)
```

## Monitoring

### Task States

- **PENDING**: Task is waiting to be processed
- **PROGRESS**: Task is currently being processed
- **SUCCESS**: Task completed successfully
- **FAILURE**: Task failed with an error

### Progress Tracking

Tasks report progress with status messages and percentage:

```json
{
  "state": "PROGRESS",
  "status": "Extracting text",
  "progress": 30
}
```

## Development

### Project Structure

```
UploadDocsService/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI application
│   ├── celery_app.py        # Celery configuration
│   ├── tasks.py             # Background tasks
│   ├── backend/
│   │   ├── db.py           # Database configuration
│   │   └── db_depends.py   # Database dependencies
│   ├── models/
│   │   ├── document.py     # Document model
│   │   └── chunk.py        # Document chunk model
│   └── routers/
│       └── upload.py       # API endpoints
├── worker.py               # Celery worker script
├── start_services.py       # Service startup script
├── requirements.txt        # Python dependencies
└── README.md              # This file
```

### Adding New Tasks

1. **Create the task function** in `app/tasks.py`:
   ```python
   @celery_app.task
   def my_new_task(param1, param2):
       # Task logic here
       return result
   ```

2. **Call the task** from your API:
   ```python
   from app.tasks import my_new_task
   
   task = my_new_task.delay(param1, param2)
   ```

### Testing

1. **Start services**:
   ```bash
   python start_services.py
   ```

2. **Upload a document**:
   ```bash
   curl -X POST "http://localhost:8000/api/documents/" \
        -H "Content-Type: multipart/form-data" \
        -F "file=@your_document.pdf"
   ```

3. **Check task status**:
   ```bash
   curl "http://localhost:8000/api/documents/task/{task_id}"
   ```

## Troubleshooting

### Common Issues

1. **Redis Connection Error**:
   - Ensure Redis is running: `redis-cli ping`
   - Check Redis URL in configuration

2. **Celery Worker Not Starting**:
   - Check Redis connection
   - Verify task imports in `celery_app.py`

3. **Task Not Processing**:
   - Check worker logs for errors
   - Verify task is in correct queue
   - Check database connection

4. **File Upload Issues**:
   - Check file size limits
   - Verify file type is supported
   - Check disk space

### Logs

- **FastAPI logs**: Check terminal where server is running
- **Celery worker logs**: Check terminal where worker is running
- **Redis logs**: Check Redis server logs

## Performance

### Optimization Tips

1. **Worker Concurrency**: Adjust based on CPU cores
2. **Chunk Size**: Optimize based on document size
3. **Database**: Consider PostgreSQL for production
4. **Redis**: Configure persistence and memory limits
5. **File Storage**: Consider cloud storage for large files

### Scaling

- **Multiple Workers**: Run multiple Celery worker processes
- **Load Balancing**: Use multiple Redis instances
- **Database**: Use connection pooling
- **Monitoring**: Add Celery monitoring tools (Flower)

## License

[Your License Here] 
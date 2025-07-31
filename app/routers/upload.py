import tempfile
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated, Any

from fastapi import APIRouter, UploadFile, File, HTTPException, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.backend.db_depends import get_db
from app.backend.operations import (
    get_documents_paginated,
    get_document_by_id,
    get_document_chunks_paginated
)
from app.backend.utils import validate_file
from app.celery_app import celery_app
from app.tasks import process_document

router = APIRouter(prefix="/documents", tags=["documents"])


@asynccontextmanager
async def temp_upload_file(file: UploadFile) -> Path:
    """Context manager for temporary file handling."""
    ext = Path(file.filename).suffix
    with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as tmp:
        tmp.write(await file.read())
        tmp_path = Path(tmp.name)

    try:
        yield tmp_path
    finally:
        tmp_path.unlink(missing_ok=True)


@router.post("/", status_code=202, summary="Upload a document for background processing")
async def upload_file(
        file: Annotated[UploadFile, File(description="PDF or DOCX file to upload")]
) -> dict[str, Any]:
    """
    Upload a document file (PDF or DOCX) for background processing.

    The file will be:
    - Validated (size and type)
    - Queued for background processing
    - Processed asynchronously (text extraction, chunking, database storage)
    
    Returns a task ID that can be used to check processing status.
    """
    await validate_file(file)

    # Read file content
    file_content = await file.read()

    # Submit task for background processing
    task = process_document.delay(
        file_content=file_content,
        filename=file.filename,
        content_type=file.content_type
    )

    return {
        "task_id": task.id,
        "status": "processing",
        "message": "Document uploaded and queued for processing"
    }


@router.get("/task/{task_id}", summary="Get task status and result")
async def get_task_status(task_id: str) -> dict[str, Any]:
    """
    Get the status and result of a background processing task.
    
    Args:
        task_id: The task ID returned from the upload endpoint
        
    Returns:
        dict with task status, progress, and result if completed
    """
    task = celery_app.AsyncResult(task_id)

    if task.state == "PENDING":
        response = {
            "task_id": task_id,
            "state": task.state,
            "status": "Task is pending..."
        }
    elif task.state == "PROGRESS":
        response = {
            "task_id": task_id,
            "state": task.state,
            "status": task.info.get("status", ""),
            "progress": task.info.get("progress", 0)
        }
    elif task.state == "SUCCESS":
        response = {
            "task_id": task_id,
            "state": task.state,
            "status": "Task completed successfully",
            "result": task.result
        }
    else:
        # Task failed
        response = {
            "task_id": task_id,
            "state": task.state,
            "status": "Task failed",
            "error": str(task.info)
        }

    return response


@router.get("/", summary="List all documents")
async def list_documents(
        db: Annotated[AsyncSession, Depends(get_db)],
        skip: int = 0,
        limit: int = 100
) -> dict[str, Any]:
    """
    List all processed documents with pagination.
    
    Args:
        skip: Number of documents to skip
        limit: Maximum number of documents to return
        
    Returns:
        dict with list of documents and total count
    """
    documents, total_count = await get_documents_paginated(db, skip, limit)

    return {
        "documents": [
            {
                "id": doc.id,
                "filename": doc.filename,
                "content_type": doc.content_type,
                "upload_time": doc.upload_time.isoformat(),
                "num_chunks": doc.num_chunks
            }
            for doc in documents
        ],
        "total_count": total_count,
        "skip": skip,
        "limit": limit
    }


@router.get("/{document_id}/chunks", summary="Get document chunks")
async def get_document_chunks(
        document_id: int,
        db: Annotated[AsyncSession, Depends(get_db)],
        skip: int = 0,
        limit: int = 100
) -> dict[str, Any]:
    """
    Get chunks for a specific document with pagination.
    
    Args:
        document_id: ID of the document
        skip: Number of chunks to skip
        limit: Maximum number of chunks to return
        
    Returns:
        dict with list of chunks and total count
    """
    # Check if document exists
    document = await get_document_by_id(db, document_id)

    if not document:
        raise HTTPException(404, "Document not found")

    # Get chunks
    chunks, total_count = await get_document_chunks_paginated(db, document_id, skip, limit)

    return {
        "document": {
            "id": document.id,
            "filename": document.filename,
            "content_type": document.content_type,
            "upload_time": document.upload_time.isoformat(),
            "num_chunks": document.num_chunks
        },
        "chunks": [
            {
                "id": chunk.id,
                "chunk_index": chunk.chunk_index,
                "text": chunk.text
            }
            for chunk in chunks
        ],
        "total_chunks": total_count,
        "skip": skip,
        "limit": limit
    }

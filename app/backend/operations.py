from datetime import datetime, timedelta
from typing import List, Optional

from sqlalchemy import select, func, delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.chunk import DocumentChunk
from app.models.document import Document


async def create_document_with_chunks(
        db: AsyncSession,
        filename: str,
        content_type: str,
        chunks: List[str]
) -> tuple[int, int]:
    """
    Create a document and its chunks in the database.
    
    Args:
        db: Database session
        filename: Original filename
        content_type: MIME type of the file
        chunks: List of text chunks
        
    Returns:
        tuple of (document_id, num_chunks)
    """
    async with db.begin():
        doc = Document(
            filename=filename,
            content_type=content_type,
            num_chunks=len(chunks)
        )
        db.add(doc)
        await db.flush()  # Get the ID before commit

        db.add_all(
            DocumentChunk(
                document_id=doc.id,
                chunk_index=idx,
                text=chunk
            )
            for idx, chunk in enumerate(chunks)
        )

        return doc.id, len(chunks)


async def get_documents_paginated(
        db: AsyncSession,
        skip: int = 0,
        limit: int = 100
) -> tuple[List[Document], int]:
    """
    Get documents with pagination.
    
    Args:
        db: Database session
        skip: Number of documents to skip
        limit: Maximum number of documents to return
        
    Returns:
        tuple of (documents, total_count)
    """
    # Get total count
    count_result = await db.execute(select(func.count(Document.id)))
    total_count = count_result.scalar()

    # Get documents
    result = await db.execute(
        select(Document)
        .offset(skip)
        .limit(limit)
        .order_by(Document.upload_time.desc())
    )
    documents = result.scalars().all()

    return documents, total_count


async def get_document_by_id(
        db: AsyncSession,
        document_id: int
) -> Optional[Document]:
    """
    Get a document by ID.
    
    Args:
        db: Database session
        document_id: ID of the document
        
    Returns:
        Document object or None if not found
    """
    result = await db.execute(select(Document).where(Document.id == document_id))
    return result.scalar_one_or_none()


async def get_document_chunks_paginated(
        db: AsyncSession,
        document_id: int,
        skip: int = 0,
        limit: int = 100
) -> tuple[List[DocumentChunk], int]:
    """
    Get chunks for a specific document with pagination.
    
    Args:
        db: Database session
        document_id: ID of the document
        skip: Number of chunks to skip
        limit: Maximum number of chunks to return
        
    Returns:
        tuple of (chunks, total_count)
    """
    # Get total count of chunks
    count_result = await db.execute(
        select(func.count(DocumentChunk.id))
        .where(DocumentChunk.document_id == document_id)
    )
    total_count = count_result.scalar()

    # Get chunks
    result = await db.execute(
        select(DocumentChunk)
        .where(DocumentChunk.document_id == document_id)
        .order_by(DocumentChunk.chunk_index)
        .offset(skip)
        .limit(limit)
    )
    chunks = result.scalars().all()

    return chunks, total_count


async def get_documents_by_owner_paginated(
        db: AsyncSession,
        owner_id: int,
        skip: int = 0,
        limit: int = 100
) -> tuple[List[Document], int]:
    """
    Get documents by owner_id with pagination.
    
    Args:
        db: Database session
        owner_id: ID of the document owner
        skip: Number of documents to skip
        limit: Maximum number of documents to return
        
    Returns:
        tuple of (documents, total_count)
    """
    # Get total count for this owner
    count_result = await db.execute(
        select(func.count(Document.id))
        .where(Document.owner_id == owner_id)
    )
    total_count = count_result.scalar()

    # Get documents for this owner
    result = await db.execute(
        select(Document)
        .where(Document.owner_id == owner_id)
        .offset(skip)
        .limit(limit)
        .order_by(Document.upload_time.desc())
    )
    documents = result.scalars().all()

    return documents, total_count


async def delete_old_documents(
        db: AsyncSession,
        days_old: int = 30
) -> int:
    """
    Delete documents older than specified days.
    
    Args:
        db: Database session
        days_old: Number of days after which documents should be deleted
        
    Returns:
        Number of deleted documents
    """
    cutoff_date = datetime.utcnow() - timedelta(days=days_old)

    # Delete documents older than cutoff_date
    result = await db.execute(
        delete(Document).where(Document.upload_time < cutoff_date)
    )
    await db.commit()

    return result.rowcount

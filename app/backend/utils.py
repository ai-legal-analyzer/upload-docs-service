import tempfile
from pathlib import Path

from PyPDF2 import PdfReader
from docx import Document as DocxDocument
from fastapi import UploadFile, HTTPException

# Shared constants
ALLOWED_EXTENSIONS = {"pdf", "docx"}
MAX_FILE_SIZE_MB = 20
CHUNK_SIZE = 1000  # characters


def is_allowed_file(filename: str) -> bool:
    """Check if the file extension is allowed."""
    return Path(filename).suffix[1:].lower() in ALLOWED_EXTENSIONS


async def validate_file(file: UploadFile) -> None:
    """Validate file size and type."""
    if not is_allowed_file(file.filename):
        raise HTTPException(400, "File type not allowed. Only PDF and DOCX are accepted.")

    file_size = 0
    for chunk in file.file:
        file_size += len(chunk)
        if file_size > MAX_FILE_SIZE_MB * 1024 * 1024:
            raise HTTPException(413, f"File too large. Max size is {MAX_FILE_SIZE_MB}MB.")

    # Reset file pointer after validation
    await file.seek(0)


def parse_pdf(file_path: Path) -> str:
    """Extract text from PDF file."""
    reader = PdfReader(file_path)
    return "\n".join(page.extract_text() or "" for page in reader.pages)


def parse_docx(file_path: Path) -> str:
    """Extract text from DOCX file."""
    doc = DocxDocument(file_path)
    return "\n".join(para.text for para in doc.paragraphs)


def chunk_text(text: str, chunk_size: int = CHUNK_SIZE) -> list[str]:
    """Split text into chunks of specified size."""
    return [text[i:i + chunk_size] for i in range(0, len(text), chunk_size)]


def extract_text_from_file(file_path: Path) -> str:
    """Extract text from file based on its extension."""
    match file_path.suffix.lower():
        case ".pdf":
            return parse_pdf(file_path)
        case ".docx":
            return parse_docx(file_path)
        case _:
            raise ValueError("Unsupported file type")


async def process_file_content(file_content: bytes, filename: str) -> tuple[str, list[str]]:
    """
    Process file content and return extracted text and chunks.
    
    Args:
        file_content: The file content as bytes
        filename: Original filename
        
    Returns:
        tuple of (extracted_text, chunks)
    """
    # Create temporary file
    ext = Path(filename).suffix
    with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as tmp:
        tmp.write(file_content)
        tmp_path = Path(tmp.name)

    try:
        # Extract text based on file type
        text = extract_text_from_file(tmp_path)

        if not text.strip():
            raise ValueError("No text extracted from file")

        # Chunk the text
        chunks = chunk_text(text)

        return text, chunks

    finally:
        # Clean up temporary file
        tmp_path.unlink(missing_ok=True)

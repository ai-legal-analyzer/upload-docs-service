#!/usr/bin/env python3
"""
Celery worker script for UploadDocsService.

Usage:
    python worker.py                    # Start worker with default settings
    python worker.py --loglevel=info   # Start worker with specific log level
    python worker.py --concurrency=4   # Start worker with specific concurrency
"""

import os
import sys
from celery.bin.celery import main as celery_main

if __name__ == "__main__":
    # Set default arguments if none provided
    if len(sys.argv) == 1:
        sys.argv.extend([
            "worker",
            "--loglevel=info",
            "--concurrency=2",
            "--queues=default,document_processing"
        ])
    
    # Run the celery worker
    celery_main() 
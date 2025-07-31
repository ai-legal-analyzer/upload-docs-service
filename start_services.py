#!/usr/bin/env python3
"""
Startup script for UploadDocsService.

This script helps start all necessary services:
1. Redis server (if not running)
2. Celery worker
3. FastAPI server

Usage:
    python start_services.py
"""

import subprocess
import sys
import time
import os
from pathlib import Path


def check_redis():
    """Check if Redis is running."""
    try:
        import redis
        r = redis.Redis(host='localhost', port=6379, db=0)
        r.ping()
        print("✅ Redis is running")
        return True
    except Exception as e:
        print(f"❌ Redis is not running: {e}")
        return False


def start_redis():
    """Start Redis server."""
    print("Starting Redis server...")
    try:
        # Try to start Redis (this might not work on all systems)
        subprocess.run(["redis-server", "--daemonize", "yes"], check=True)
        time.sleep(2)  # Wait for Redis to start
        if check_redis():
            print("✅ Redis started successfully")
            return True
        else:
            print("❌ Failed to start Redis")
            return False
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ Could not start Redis. Please install and start Redis manually:")
        print("   - macOS: brew install redis && brew services start redis")
        print("   - Ubuntu: sudo apt-get install redis-server")
        print("   - Or download from: https://redis.io/download")
        return False


def start_celery_worker():
    """Start Celery worker."""
    print("Starting Celery worker...")
    try:
        # Start worker in background
        worker_process = subprocess.Popen([
            sys.executable, "worker.py",
            "worker",
            "--loglevel=info",
            "--concurrency=2",
            "--queues=default,document_processing"
        ])
        print("✅ Celery worker started")
        return worker_process
    except Exception as e:
        print(f"❌ Failed to start Celery worker: {e}")
        return None


def start_fastapi_server():
    """Start FastAPI server."""
    print("Starting FastAPI server...")
    try:
        # Start FastAPI server
        server_process = subprocess.Popen([
            sys.executable, "-m", "uvicorn",
            "app.main:app",
            "--host", "0.0.0.0",
            "--port", "8000",
            "--reload"
        ])
        print("✅ FastAPI server started at http://localhost:8000")
        return server_process
    except Exception as e:
        print(f"❌ Failed to start FastAPI server: {e}")
        return None


def main():
    """Main startup function."""
    print("🚀 Starting UploadDocsService...")
    
    # Check and start Redis
    if not check_redis():
        if not start_redis():
            sys.exit(1)
    
    # Start Celery worker
    worker_process = start_celery_worker()
    if not worker_process:
        sys.exit(1)
    
    # Start FastAPI server
    server_process = start_fastapi_server()
    if not server_process:
        worker_process.terminate()
        sys.exit(1)
    
    print("\n🎉 All services started successfully!")
    print("📖 API Documentation: http://localhost:8000/docs")
    print("📋 API Endpoints:")
    print("   - POST /api/documents/ - Upload document for processing")
    print("   - GET  /api/documents/task/{task_id} - Check task status")
    print("   - GET  /api/documents/ - List all documents")
    print("   - GET  /api/documents/{id}/chunks - Get document chunks")
    print("\nPress Ctrl+C to stop all services")
    
    try:
        # Keep the script running
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n🛑 Stopping services...")
        if worker_process:
            worker_process.terminate()
        if server_process:
            server_process.terminate()
        print("✅ Services stopped")


if __name__ == "__main__":
    main() 
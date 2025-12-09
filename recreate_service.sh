#!/bin/bash

echo "🔄 Recreating UploadDocsService with migrations..."

# Stop all services
echo "📦 Stopping all services..."
docker-compose down -v

# Remove any existing volumes to start fresh
echo "🧹 Cleaning up volumes..."
docker volume rm uploaddocsservice_postgres_data 2>/dev/null || true

# Build the images
echo "🔨 Building images..."
docker-compose build

# Start the database and wait for it to be healthy
echo "🐘 Starting database..."
docker-compose up -d db

echo "⏳ Waiting for database to be ready..."
until docker-compose exec -T db pg_isready -U postgres; do
    echo "Waiting for database..."
    sleep 2
done

# Run migrations
echo "📊 Running migrations..."
docker-compose run --rm migrate

# Start all services
echo "🚀 Starting all services..."
docker-compose up -d

echo "✅ Service recreation complete!"
echo "📋 Services status:"
docker-compose ps

echo ""
echo "🌐 Web service should be available at: http://localhost:8000"
echo "📊 Database is running on: localhost:5432"
echo "🔴 Redis is running on: localhost:6379" 
# Makefile
.PHONY: all infra config migrate web worker ingress status logs clean port-forward restart deploy build push

K8S_DIR = k8s
NAMESPACE = upload-service-ns
IMAGE_NAME = upload-service
IMAGE_TAG = latest
REGISTRY ?= localhost:5000

# Main targets
all: deploy

# Build Docker image
build:
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .
	@echo "✅ Image built: $(IMAGE_NAME):$(IMAGE_TAG)"

# Push to registry (optional)
push:
	docker tag $(IMAGE_NAME):$(IMAGE_TAG) $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)
	docker push $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)
	@echo "✅ Image pushed to registry"

# Deploy everything (correct order!)
deploy: namespace config infra migrate web worker
	@echo "⌛ Waiting for worker to start..."
	@sleep 10
	@echo "✅ Everything deployed! Check status: make status"

# Sequential deployment with waits
deploy-seq: namespace config infra-wait migrate web worker
	@echo "✅ Everything deployed!"

# Create namespace
namespace:
	@echo "📦 Creating namespace..."
	kubectl apply -f $(K8S_DIR)/00-namespace.yaml

# Configurations (MUST BE FIRST!)
config:
	@echo "🔧 Applying ConfigMap and Secret..."
	kubectl apply -f $(K8S_DIR)/05-configs/secret.yaml
	kubectl apply -f $(K8S_DIR)/05-configs/configmap.yaml
	@sleep 2

# Infrastructure
infra:
	@echo "🏗️  Deploying infrastructure..."
#	kubectl apply -f $(K8S_DIR)/01-infrastructure/postgres/pvc.yaml
	kubectl apply -f $(K8S_DIR)/01-infrastructure/postgres/statefulset.yaml
	kubectl apply -f $(K8S_DIR)/01-infrastructure/postgres/service.yaml
	kubectl apply -f $(K8S_DIR)/01-infrastructure/redis/deployment.yaml
	kubectl apply -f $(K8S_DIR)/01-infrastructure/redis/service.yaml

# Infrastructure with wait
infra-wait: infra
	@echo "⌛ Waiting for PostgreSQL and Redis to start..."
	@echo "Waiting for PostgreSQL..."
	@until kubectl get pods -n $(NAMESPACE) -l app=postgres -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; do \
		echo "PostgreSQL not ready yet, waiting..."; \
		sleep 5; \
	done
	@echo "✅ PostgreSQL is running"
	@echo "Waiting for Redis..."
	@until kubectl get pods -n $(NAMESPACE) -l app=redis -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; do \
		echo "Redis not ready yet, waiting..."; \
		sleep 3; \
	done
	@echo "✅ Redis is running"
	@sleep 5

# Database migrations
migrate:
	@echo "🗄️  Running database migrations..."
	kubectl apply -f $(K8S_DIR)/02-migrations/job.yaml
	@echo "⌛ Waiting for migrations to complete (max 60 seconds)..."
	@if kubectl wait --for=condition=complete job/migrations-job -n $(NAMESPACE) --timeout=60s 2>/dev/null; then \
		echo "✅ Migrations completed successfully"; \
	else \
		echo "⚠️  Migrations took longer or failed"; \
		echo "Migration logs:"; \
		kubectl logs -n $(NAMESPACE) job/migrations-job --tail=20; \
	fi

# Web service
web:
	@echo "🌐 Deploying web service..."
	kubectl apply -f $(K8S_DIR)/03-web/deployment.yaml
	kubectl apply -f $(K8S_DIR)/03-web/service.yaml

# Celery worker
worker:
	@echo "👷 Deploying Celery worker..."
	kubectl apply -f $(K8S_DIR)/04-worker/deployment.yaml
	@echo "⌛ Waiting for worker to start (10 seconds)..."
	@sleep 10

# Ingress (optional)
ingress:
	@if [ -f "$(K8S_DIR)/06-ingress/ingress.yaml" ]; then \
		echo "🌍 Deploying Ingress..."; \
		kubectl apply -f $(K8S_DIR)/06-ingress/ingress.yaml; \
	else \
		echo "⚠️  Ingress not configured, skipping"; \
	fi

# Status check
status:
	@echo "📊 === Pods ==="
	kubectl get pods -n $(NAMESPACE) -o wide
	@echo "\n🌐 === Services ==="
	kubectl get svc -n $(NAMESPACE)
	@echo "\n🚀 === Deployments/StatefulSets ==="
	kubectl get deployments,statefulsets -n $(NAMESPACE)
	@echo "\n💾 === PVC ==="
	kubectl get pvc -n $(NAMESPACE)
	@echo "\n📝 === ConfigMaps/Secrets ==="
	kubectl get configmaps,secrets -n $(NAMESPACE)
	@echo "\n🔗 === Ingress ==="
	kubectl get ingress -n $(NAMESPACE) 2>/dev/null || echo "Ingress not configured"

# Detailed status
status-detailed:
	@echo "📋 Detailed status..."
	@echo "=== All resources ==="
	kubectl get all -n $(NAMESPACE)
	@echo "\n=== PVC and Storage ==="
	kubectl get pvc,pv -n $(NAMESPACE)
	@echo "\n=== Events (last 10) ==="
	kubectl get events -n $(NAMESPACE) --sort-by='.lastTimestamp' | tail -10

# Logs
logs-web:
	@echo "📜 Web service logs..."
	kubectl logs -n $(NAMESPACE) -l app=upload-web --tail=100 -f

logs-worker:
	@echo "📜 Celery worker logs..."
	kubectl logs -n $(NAMESPACE) -l app=celery-worker --tail=100 -f

logs-postgres:
	@echo "📜 PostgreSQL logs..."
	kubectl logs -n $(NAMESPACE) -l app=postgres --tail=100 -f

logs-redis:
	@echo "📜 Redis logs..."
	kubectl logs -n $(NAMESPACE) -l app=redis --tail=100 -f

logs-migrations:
	@echo "📜 Migration logs..."
	kubectl logs -n $(NAMESPACE) job/migrations-job --tail=100

# Cleanup
clean:
	@echo "🗑️  Cleaning up all resources..."
	@echo "Deleting in correct order (dependencies first)..."
	# Ingress (if exists)
	-kubectl delete -f $(K8S_DIR)/06-ingress/ingress.yaml --ignore-not-found=true --wait=false
	# Worker
	-kubectl delete -f $(K8S_DIR)/04-worker/deployment.yaml --ignore-not-found=true --wait=false
	# Web
	-kubectl delete -f $(K8S_DIR)/03-web/service.yaml --ignore-not-found=true --wait=false
	-kubectl delete -f $(K8S_DIR)/03-web/deployment.yaml --ignore-not-found=true --wait=false
	# Migrations
	-kubectl delete -f $(K8S_DIR)/02-migrations/job.yaml --ignore-not-found=true --wait=false
	# Infrastructure
	-kubectl delete -f $(K8S_DIR)/01-infrastructure/redis/service.yaml --ignore-not-found=true --wait=false
	-kubectl delete -f $(K8S_DIR)/01-infrastructure/redis/deployment.yaml --ignore-not-found=true --wait=false
	-kubectl delete -f $(K8S_DIR)/01-infrastructure/postgres/service.yaml --ignore-not-found=true --wait=false
	-kubectl delete -f $(K8S_DIR)/01-infrastructure/postgres/statefulset.yaml --ignore-not-found=true --wait=false
#	-kubectl delete -f $(K8S_DIR)/01-infrastructure/postgres/pvc.yaml --ignore-not-found=true --wait=false
	# Configurations
	-kubectl delete -f $(K8S_DIR)/05-configs/configmap.yaml --ignore-not-found=true --wait=false
	-kubectl delete -f $(K8S_DIR)/05-configs/secret.yaml --ignore-not-found=true --wait=false
	# Namespace (will delete everything else)
	-kubectl delete -f $(K8S_DIR)/00-namespace.yaml --ignore-not-found=true
	@echo "⌛ Waiting for cleanup to complete..."
	@sleep 5
	@echo "✅ Cleanup completed!"

# Force cleanup
clean-force:
	@echo "💥 Force deleting all resources..."
	kubectl delete namespace $(NAMESPACE) --ignore-not-found=true --force --grace-period=0
	@echo "✅ Force cleanup completed"

# Port-forward
port-forward:
	@echo "🔌 Starting port-forward..."
	@echo "Web UI: http://localhost:8000"
	@echo "API: http://localhost:8000/docs"
	@echo "PostgreSQL: localhost:5432"
	@echo "Redis: localhost:6379"
	@echo ""
	@echo "Press Ctrl+C to stop all"
	@echo "================================"
	@trap 'kill $$(jobs -p)' EXIT; \
	kubectl port-forward -n $(NAMESPACE) svc/upload-web-service 8000:8000 & \
	kubectl port-forward -n $(NAMESPACE) svc/postgres-service 5432:5432 & \
	kubectl port-forward -n $(NAMESPACE) svc/redis-service 6379:6379 & \
	wait

# Port-forward only web
pf-web:
	kubectl port-forward -n $(NAMESPACE) svc/upload-web-service 8000:8000

# Restart services
restart-web:
	@echo "🔄 Restarting web service..."
	kubectl rollout restart deployment/upload-web -n $(NAMESPACE)

restart-worker:
	@echo "🔄 Restarting Celery worker..."
	kubectl rollout restart deployment/celery-worker -n $(NAMESPACE)

restart-all: restart-web restart-worker

# SIMPLIFIED Connection checks - using separate script files
check-db:
	@echo "🔍 Checking PostgreSQL connection..."
	@if [ ! -f "check_db.py" ]; then \
		echo '#!/usr/bin/env python3\nimport asyncpg\nimport asyncio\nimport os\n\nasync def test():\n    try:\n        conn = await asyncpg.connect(os.environ.get("DATABASE_URL", "postgresql+asyncpg://postgres:postgres@localhost:5432/postgres"))\n        print("✅ PostgreSQL: Connection successful")\n        try:\n            count = await conn.fetchval("SELECT COUNT(*) FROM documents")\n            print(f"    Documents in database: {count}")\n        except:\n            print("    Documents table might not exist yet")\n        await conn.close()\n    except Exception as e:\n        print(f"❌ PostgreSQL error: {e}")\n\nif __name__ == "__main__":\n    asyncio.run(test())' > check_db.py; \
	fi
	@WEB_POD=$$(kubectl get pods -n $(NAMESPACE) -l app=upload-web -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$WEB_POD" ]; then \
		echo "❌ No web pod found"; \
	else \
		kubectl cp check_db.py $(NAMESPACE)/$$WEB_POD:/tmp/check_db.py && \
		kubectl exec -n $(NAMESPACE) $$WEB_POD -- python3 /tmp/check_db.py; \
	fi

check-redis:
	@echo "🔍 Checking Redis connection..."
	@if [ ! -f "check_redis.py" ]; then \
		echo '#!/usr/bin/env python3\nimport redis\nimport os\n\ntry:\n    redis_url = os.environ.get("CELERY_BROKER_URL", "redis://localhost:6379/0")\n    r = redis.Redis.from_url(redis_url)\n    if r.ping():\n        print("✅ Redis: Connection successful")\n    else:\n        print("❌ Redis: Not responding")\nexcept Exception as e:\n    print(f"❌ Redis error: {e}")' > check_redis.py; \
	fi
	@WEB_POD=$$(kubectl get pods -n $(NAMESPACE) -l app=upload-web -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	if [ -z "$$WEB_POD" ]; then \
		echo "❌ No web pod found"; \
	else \
		kubectl cp check_redis.py $(NAMESPACE)/$$WEB_POD:/tmp/check_redis.py && \
		kubectl exec -n $(NAMESPACE) $$WEB_POD -- python3 /tmp/check_redis.py; \
	fi

check-all: check-db check-redis
	@rm -f check_db.py check_redis.py 2>/dev/null || true

# Fast deployment (parallel, for advanced users)
fast-deploy:
	@echo "⚡ Fast deployment..."
	kubectl apply -f $(K8S_DIR)/00-namespace.yaml
	kubectl apply -f $(K8S_DIR)/05-configs/
	kubectl apply -f $(K8S_DIR)/01-infrastructure/
	sleep 15
	kubectl apply -f $(K8S_DIR)/02-migrations/
	kubectl apply -f $(K8S_DIR)/03-web/
	kubectl apply -f $(K8S_DIR)/04-worker/
	@if [ -f "$(K8S_DIR)/06-ingress/ingress.yaml" ]; then \
		kubectl apply -f $(K8S_DIR)/06-ingress/ingress.yaml; \
	fi
	@echo "✅ Fast deployment completed!"

# Deploy service with its monitoring config
deploy-with-monitoring: deploy
	@echo "📊 Applying service monitoring configuration..."
	kubectl apply -f k8s/07-monitoring/
	@echo "✅ Service monitoring deployed!"

# Export metrics config
generate-metrics:
	@echo "🔧 Generating metrics configuration..."
	python scripts/generate-prometheus-config.py

# Help
help:
	@echo "🚀 Upload Service Management Commands:"
	@echo ""
	@echo "📦 Deployment:"
	@echo "  make build          - Build Docker image"
	@echo "  make deploy         - Full deployment (recommended)"
	@echo "  make deploy-seq     - Sequential deployment with waits"
	@echo "  make fast-deploy    - Fast deployment"
	@echo ""
	@echo "🔧 Management:"
	@echo "  make status         - Status of all resources"
	@echo "  make status-detailed- Detailed status"
	@echo "  make restart-all    - Restart all services"
	@echo "  make restart-web    - Restart web service"
	@echo "  make restart-worker - Restart Celery worker"
	@echo ""
	@echo "📊 Monitoring:"
	@echo "  make logs-web       - Web service logs"
	@echo "  make logs-worker    - Celery worker logs"
	@echo "  make logs-postgres  - PostgreSQL logs"
	@echo "  make logs-redis     - Redis logs"
	@echo "  make check-all      - Check all connections"
	@echo ""
	@echo "🔌 Local Development:"
	@echo "  make port-forward   - Port-forward all services"
	@echo "  make pf-web         - Port-forward only web"
	@echo ""
	@echo "🧹 Cleanup:"
	@echo "  make clean          - Delete all resources"
	@echo "  make clean-force    - Force delete all resources"
	@echo ""
	@echo "❓ Help:"
	@echo "  make help           - This help message"
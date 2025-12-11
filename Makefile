# Makefile
.PHONY: all infra config migrate web worker ingress status logs clean port-forward restart deploy

K8S_DIR = .
NAMESPACE = upload-service-ns

# Основные цели
all: deploy

# Развертывание всего
deploy: namespace infra config migrate web worker ingress
	@echo "✅ Все развернуто!"

# Создание namespace
namespace:
	kubectl apply -f $(K8S_DIR)/00-namespace.yaml

# Инфраструктура
infra:
	kubectl apply -f $(K8S_DIR)/01-infrastructure/postgres/pvc.yaml
	kubectl apply -f $(K8S_DIR)/01-infrastructure/postgres/statefulset.yaml
	kubectl apply -f $(K8S_DIR)/01-infrastructure/postgres/service.yaml
	kubectl apply -f $(K8S_DIR)/01-infrastructure/redis/deployment.yaml
	kubectl apply -f $(K8S_DIR)/01-infrastructure/redis/service.yaml

# Конфигурации
config:
	kubectl apply -f $(K8S_DIR)/05-configs/secret.yaml
	kubectl apply -f $(K8S_DIR)/05-configs/configmap.yaml

# Миграции
migrate:
	kubectl apply -f $(K8S_DIR)/02-migrations/job.yaml

# Web сервис
web:
	kubectl apply -f $(K8S_DIR)/03-web/deployment.yaml
	kubectl apply -f $(K8S_DIR)/03-web/service.yaml

# Worker
worker:
	kubectl apply -f $(K8S_DIR)/04-worker/deployment.yaml

# Ingress
ingress:
	kubectl apply -f $(K8S_DIR)/06-ingress/ingress.yaml

# Статус
status:
	@echo "=== Pods ==="
	kubectl get pods -n $(NAMESPACE)
	@echo "\n=== Services ==="
	kubectl get svc -n $(NAMESPACE)
	@echo "\n=== Deployments ==="
	kubectl get deployments -n $(NAMESPACE)

# Логи
logs-web:
	kubectl logs -n $(NAMESPACE) -l app=upload-web -f

logs-worker:
	kubectl logs -n $(NAMESPACE) -l app=celery-worker -f

logs-postgres:
	kubectl logs -n $(NAMESPACE) -l app=postgres -f

# Очистка
clean:
	@for file in 06-ingress/ingress.yaml 04-worker/deployment.yaml 03-web/service.yaml 03-web/deployment.yaml 02-migrations/job.yaml 05-configs/configmap.yaml 05-configs/secret.yaml 01-infrastructure/redis/service.yaml 01-infrastructure/redis/deployment.yaml 01-infrastructure/postgres/service.yaml 01-infrastructure/postgres/statefulset.yaml 01-infrastructure/postgres/pvc.yaml 00-namespace.yaml; do \
		kubectl delete -f $(K8S_DIR)/$$file --ignore-not-found=true; \
	done

# Port-forward
port-forward:
	kubectl port-forward -n $(NAMESPACE) svc/upload-web 8000:8000 &
	kubectl port-forward -n $(NAMESPACE) svc/postgres-service 5432:5432 &
	kubectl port-forward -n $(NAMESPACE) svc/redis-service 6379:6379
	@echo "Press Ctrl+C to stop"

# Перезапуск
restart-web:
	kubectl rollout restart deployment/upload-web -n $(NAMESPACE)

restart-worker:
	kubectl rollout restart deployment/celery-worker -n $(NAMESPACE)

# Быстрый деплой (параллельный)
fast-deploy:
	kubectl apply -f $(K8S_DIR)/00-namespace.yaml
	kubectl apply -f $(K8S_DIR)/01-infrastructure/
	kubectl apply -f $(K8S_DIR)/05-configs/
	kubectl apply -f $(K8S_DIR)/02-migrations/
	kubectl apply -f $(K8S_DIR)/03-web/
	kubectl apply -f $(K8S_DIR)/04-worker/
	kubectl apply -f $(K8S_DIR)/06-ingress/
	@echo "✅ Быстрое развертывание завершено!"
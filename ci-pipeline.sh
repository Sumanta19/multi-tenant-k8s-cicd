#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status

TENANT=$1
if [ -z "$TENANT" ]; then
  echo "Usage: ./ci-pipeline.sh <tenant-name>"
  exit 1
fi

# 1. Generate Tag (Date + Short SHA)
DATE=$(date +%Y%m%d)
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
TAG="${DATE}-${SHA}"
IMAGE_NAME="localhost:5000/web-app:${TAG}"

echo "🚀 Starting Pipeline for ${TENANT} with tag ${TAG}"

# 2. Build Docker Image
echo "📦 Building Docker Image..."
docker build -t ${IMAGE_NAME} ./app



# 4. Push to Local Registry
echo "⬆️ Pushing to Local Registry..."
docker push ${IMAGE_NAME}

# 5. Helm Deploy
echo "⛵ Deploying via Helm..."
helm upgrade --install ${TENANT} ./charts/web-app \
  --create-namespace \
  --namespace ${TENANT} \
  -f tenants/${TENANT}.yaml \
  --set image.repository=localhost:5000/web-app \
  --set image.tag=${TAG} \
  --set image.pullPolicy=Always \
  --wait --timeout 60s

# 6. Health Gate / Smoke Test
echo "🏥 Running Health Gate..."
# We use port-forward to check the app directly inside the cluster
kubectl port-forward -n ${TENANT} svc/web-service 8081:80 > /dev/null 2>&1 &
PF_PID=$!
sleep 2

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081)
kill $PF_PID

if [ "$HTTP_STATUS" -eq 200 ]; then
  echo "✅ Health Gate Passed! (HTTP 200)"
  echo "📢 Publishing event: WebsiteCreated to Kafka..."
  
  POD_NAME="kafka-producer-${TENANT}-$(date +%s)"
  kubectl run $POD_NAME --restart='Never' \
    --image docker.io/bitnamilegacy/kafka:4.0.0-debian-12-r10 \
    --namespace default --command -- /bin/sh -c \
    "echo '{\"event\":\"WebsiteCreated\",\"tenant\":\"${TENANT}\",\"sha\":\"${SHA}\"}' | kafka-console-producer.sh --bootstrap-server kafka.default.svc.cluster.local:9092 --topic website.events"
  
  echo "Event published successfully!"
else
  echo "❌ Health Gate Failed! (HTTP ${HTTP_STATUS})"
  echo "Publishing event: deploy.failed (Tenant: ${TENANT}, SHA: ${SHA})"
  
  echo "⏪ Rolling back Helm release..."
  helm rollback ${TENANT}
  exit 1
fi
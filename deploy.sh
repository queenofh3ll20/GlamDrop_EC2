#!/bin/bash
set -e

# Change directory to script location
cd "$(dirname "$0")"

echo "=========================================================================="
echo "   [GlamDrop] Deploy su Cluster Kubernetes AWS EC2 + S3/CloudFront"
echo "=========================================================================="

# --- FASE 1: Recupero informazioni da Terraform ---
echo "=== [1/5] Recupero parametri e credenziali da Terraform ==="
cd terraform

CONTROL_PLANE_ID=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -raw control_plane_id 2>/dev/null || true)
CONTROL_PLANE_IP=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -raw control_plane_public_ip 2>/dev/null || true)
AWS_REGION=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -raw aws_region 2>/dev/null || echo "eu-south-1")
S3_BUCKET=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -raw s3_frontend_bucket 2>/dev/null || true)
CLOUDFRONT_URL=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -raw cloudfront_domain_name 2>/dev/null || true)
CLOUDFRONT_DIST_ID=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -raw cloudfront_distribution_id 2>/dev/null || true)
SSH_KEY_PATH=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -raw control_plane_ssh_command 2>/dev/null | awk -F'-i ' '{print $2}' | awk '{print $1}' || echo "id_ed25519")

AUTH_ECR=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -json ecr_repository_urls 2>/dev/null | grep -o '"auth-service": "[^"]*' | cut -d'"' -f4 || true)
BOOKING_ECR=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -json ecr_repository_urls 2>/dev/null | grep -o '"booking-service": "[^"]*' | cut -d'"' -f4 || true)
DROP_ECR=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -json ecr_repository_urls 2>/dev/null | grep -o '"drop-service": "[^"]*' | cut -d'"' -f4 || true)
NOTIF_ECR=$(TF_CLI_CONFIG_FILE=/dev/null terraform output -json ecr_repository_urls 2>/dev/null | grep -o '"notification-service": "[^"]*' | cut -d'"' -f4 || true)

cd ..

# Fallback automatico via AWS CLI se i parametri non sono nel tfstate locale
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null || true)
if [ -z "$CONTROL_PLANE_ID" ]; then
  CONTROL_PLANE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=glamdrop-control-plane-1" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text --region "$AWS_REGION" 2>/dev/null || true)
fi
if [ -z "$S3_BUCKET" ] && [ -n "$AWS_ACCOUNT_ID" ]; then
  S3_BUCKET=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'glamdrop-frontend')].Name" --output text 2>/dev/null | awk '{print $1}')
fi
if [ -z "$AUTH_ECR" ] && [ -n "$AWS_ACCOUNT_ID" ]; then
  AUTH_ECR="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/glamdrop/auth-service"
  BOOKING_ECR="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/glamdrop/booking-service"
  DROP_ECR="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/glamdrop/drop-service"
  NOTIF_ECR="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/glamdrop/notification-service"
fi
if [ -z "$CLOUDFRONT_URL" ] || [ -z "$CLOUDFRONT_DIST_ID" ]; then
  CLOUDFRONT_DIST_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Comment, 'glamdrop')].Id | [0]" --output text 2>/dev/null || true)
  if [ "$CLOUDFRONT_DIST_ID" != "None" ] && [ -n "$CLOUDFRONT_DIST_ID" ]; then
    CLOUDFRONT_URL=$(aws cloudfront get-distribution --id "$CLOUDFRONT_DIST_ID" --query "Distribution.DomainName" --output text 2>/dev/null || true)
  fi
fi

if [ -z "$CONTROL_PLANE_ID" ] && [ -z "$CONTROL_PLANE_IP" ]; then
  echo "[ERRORE] Impossibile determinare l'istanza Control Plane. Verifica i Terraform output."
  exit 1
fi

echo "  -> Control Plane ID: ${CONTROL_PLANE_ID}"
echo "  -> Control Plane IP: ${CONTROL_PLANE_IP}"
echo "  -> AWS Region: ${AWS_REGION}"
echo "  -> S3 Frontend Bucket: ${S3_BUCKET}"
echo "  -> CloudFront URL: ${CLOUDFRONT_URL}"
echo "  -> CloudFront Dist ID: ${CLOUDFRONT_DIST_ID}"
echo "  -> ECR Auth Service: ${AUTH_ECR}"

# --- FASE 2: Deploy Frontend su AWS S3 & CloudFront ---
echo ""
echo "=== [2/5] Deploy del Frontend su S3 e invalidazione CDN ==="
if [ -n "$S3_BUCKET" ]; then
  echo "  -> Sincronizzazione file statici su s3://${S3_BUCKET}..."
  aws s3 sync frontend/ "s3://${S3_BUCKET}/" --exclude "Dockerfile" --exclude "nginx.conf" --delete
  echo "  Frontend caricato con successo su S3."

  if [ -n "$CLOUDFRONT_DIST_ID" ]; then
    echo "  -> Invalidazione cache CloudFront per la distribuzione ${CLOUDFRONT_DIST_ID}..."
    aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_DIST_ID" --paths "/*" >/dev/null 2>&1 || true
    echo "  Invalidazione cache CloudFront richiesta."
  fi
else
  echo "  S3 bucket non configurato, salto deploy frontend."
fi

# --- FASE 3: Build & Push Immagini Docker su ECR (se Docker è presente) ---
if command -v docker &>/dev/null && [ -n "$AUTH_ECR" ]; then
  echo ""
  echo "=== [3/5] Build & Push immagini Docker su Amazon ECR ==="
  REGISTRY=$(echo "$AUTH_ECR" | cut -d'/' -f1)
  echo "  -> Autenticazione con Amazon ECR ($REGISTRY)..."
  aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null 2>&1 || true
  
  echo "  -> Compilazione & caricamento auth-service..."
  docker build --platform linux/amd64 -q -t "${AUTH_ECR}:v1.0.0" services/auth-service/
  docker push -q "${AUTH_ECR}:v1.0.0"
  
  echo "  -> Compilazione & caricamento booking-service..."
  docker build --platform linux/amd64 -q -t "${BOOKING_ECR}:v1.0.0" services/booking-service/
  docker push -q "${BOOKING_ECR}:v1.0.0"
  
  echo "  -> Compilazione & caricamento drop-service..."
  docker build --platform linux/amd64 -q -t "${DROP_ECR}:v1.0.0" services/drop-service/
  docker push -q "${DROP_ECR}:v1.0.0"

  echo "  -> Compilazione & caricamento notification-service..."
  docker build --platform linux/amd64 -q -t "${NOTIF_ECR}:v1.0.0" services/notification-service/
  docker push -q "${NOTIF_ECR}:v1.0.0"
  echo "  Tutte le immagini sono caricate su Amazon ECR."
fi

# --- FASE 4: Verifica Segreti & Trasferimento Manifesti ---
echo ""
echo "=== [4/5] Trasferimento manifesti K8s sul Control Plane ==="

SSH_KEY="terraform/${SSH_KEY_PATH}"
if [ ! -f "$SSH_KEY" ]; then
  SSH_KEY="terraform/id_ed25519"
fi

SAFE_KEY="/tmp/glamdrop_deploy_key"
cp "$SSH_KEY" "$SAFE_KEY"
tr -d '\r' < "$SSH_KEY" > "$SAFE_KEY"
chmod 600 "$SAFE_KEY"

PROXY_CMD="aws ssm start-session --target ${CONTROL_PLANE_ID} --document-name AWS-StartSSHSession --parameters portNumber=%p --region ${AWS_REGION}"

echo "  -> Connessione tramite AWS Systems Manager (SSM)..."
echo "  -> Trasferimento manifesti in corso..."

MAX_RETRIES=10
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if tar -czf - -C k8s . | ssh -i "$SAFE_KEY" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=120 \
    -o ConnectionAttempts=10 \
    -o ServerAliveInterval=15 \
    -o ProxyCommand="$PROXY_CMD" \
    "ubuntu@${CONTROL_PLANE_ID}" "mkdir -p /home/ubuntu/k8s && tar -xzf - -C /home/ubuntu/k8s"; then
    SUCCESS=true
    break
  fi
  echo " Timeout o errore SSH via SSM. Ritento tra 10 secondi... ($((RETRY_COUNT+1))/$MAX_RETRIES)"
  sleep 10
  RETRY_COUNT=$((RETRY_COUNT+1))
done

if [ "$SUCCESS" = false ]; then
  echo "[ERRORE] Impossibile trasferire i file sul Control Plane dopo $MAX_RETRIES tentativi."
  rm -f "$SAFE_KEY"
  exit 1
fi

# --- FASE 5: Applicazione dei Manifesti Kubernetes ---
echo ""
echo "=== [5/5] Applicazione dei manifesti Kubernetes dei Microservizi ==="
ECR_PASS=$(aws ecr get-login-password --region "$AWS_REGION" 2>/dev/null || echo "")
REGISTRY=$(echo "$AUTH_ECR" | cut -d'/' -f1)
AWS_AK=$(aws configure get aws_access_key_id 2>/dev/null || echo "")
AWS_SK=$(aws configure get aws_secret_access_key 2>/dev/null || echo "")

ssh -i "$SAFE_KEY" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=120 \
  -o ConnectionAttempts=10 \
  -o ServerAliveInterval=15 \
  -o ProxyCommand="$PROXY_CMD" \
  "ubuntu@${CONTROL_PLANE_ID}" "bash -s \"$AUTH_ECR\" \"$BOOKING_ECR\" \"$DROP_ECR\" \"$NOTIF_ECR\" \"$REGISTRY\" \"$ECR_PASS\" \"$AWS_AK\" \"$AWS_SK\"" << 'EOF'
set -e
export KUBECONFIG=/home/ubuntu/.kube/config

AUTH_ECR="$1"
BOOKING_ECR="$2"
DROP_ECR="$3"
NOTIF_ECR="$4"
REGISTRY="$5"
ECR_PASS="$6"
AWS_AK="$7"
AWS_SK="$8"

echo '0. Verifica che i nodi Worker dell'\''ASG siano connessi e pronti...'
for i in {1..60}; do
  READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
  if [ "$READY_NODES" -ge 2 ]; then
    echo "  -> Nodi rilevati in stato Ready: $READY_NODES"
    break
  fi
  echo "  -> In attesa dei nodi Worker... ($READY_NODES/2 pronti, tentativo $i/60)"
  sleep 10
done

echo '1. Applicazione Namespace, LimitRange, Quota e NetworkPolicies...'
kubectl apply -f /home/ubuntu/k8s/namespace.yaml
kubectl apply -f /home/ubuntu/k8s/network-policy.yaml

echo '2. Configurazione credenziali di autenticazione Amazon ECR e CronJob di rinnovo...'
if [ -n "$ECR_PASS" ] && [ -n "$REGISTRY" ]; then
  kubectl create secret docker-registry ecr-secret -n glamdrop \
    --docker-server="$REGISTRY" \
    --docker-username=AWS \
    --docker-password="$ECR_PASS" \
    --dry-run=client -o yaml | kubectl apply -f -
  
  sleep 3
  kubectl patch serviceaccount default -n glamdrop -p '{"imagePullSecrets": [{"name": "ecr-secret"}]}' || true
fi
if [ -f /home/ubuntu/k8s/ecr-cronjob.yaml ]; then
  kubectl apply -f /home/ubuntu/k8s/ecr-cronjob.yaml
fi

echo '3. Applicazione Secrets Database, RabbitMQ, Redis e credenziali AWS...'
if [ -f /home/ubuntu/k8s/secret.yaml ]; then
  kubectl apply -f /home/ubuntu/k8s/secret.yaml
fi

if [ -n "$AWS_AK" ] && [ -n "$AWS_SK" ]; then
  AWS_AK_B64=$(echo -n "$AWS_AK" | base64 -w 0)
  AWS_SK_B64=$(echo -n "$AWS_SK" | base64 -w 0)
  kubectl patch secret glamdrop-secrets -n glamdrop -p "{\"data\": {\"aws-access-key-id\": \"$AWS_AK_B64\", \"aws-secret-access-key\": \"$AWS_SK_B64\"}}" || true
fi

if [ -n "$AUTH_ECR" ]; then
  echo '4. Aggiornamento percorsi immagini ECR nei manifesti...'
  sed -i "s|image: auth-service:v1.0.0|image: ${AUTH_ECR}:v1.0.0|g" /home/ubuntu/k8s/auth-service.yaml || true
  sed -i "s|image: booking-service:v1.0.0|image: ${BOOKING_ECR}:v1.0.0|g" /home/ubuntu/k8s/booking-service.yaml || true
  sed -i "s|image: drop-service:v1.0.0|image: ${DROP_ECR}:v1.0.0|g" /home/ubuntu/k8s/drop-service.yaml || true
  sed -i "s|image: notification-service:v1.0.0|image: ${NOTIF_ECR}:v1.0.0|g" /home/ubuntu/k8s/notification-service.yaml || true
fi

echo '5. Installazione dichiarativa Ingress Nginx Controller (NodePort 30080)...'
kubectl apply -f /home/ubuntu/k8s/ingress-nginx.yaml
kubectl delete ValidatingWebhookConfiguration ingress-nginx-admission --ignore-not-found || true

echo '6. Applicazione Microservizi Backend, HPA/PDB e Ingress...'
kubectl apply -f /home/ubuntu/k8s/auth-service.yaml
kubectl apply -f /home/ubuntu/k8s/booking-service.yaml
kubectl apply -f /home/ubuntu/k8s/drop-service.yaml
kubectl apply -f /home/ubuntu/k8s/notification-service.yaml
kubectl apply -f /home/ubuntu/k8s/hpa-pdb.yaml || true
kubectl apply -f /home/ubuntu/k8s/ingress.yaml

echo '7. Rollout restart per caricare le nuove configurazioni...'
kubectl rollout restart deployment auth-service booking-service drop-service notification-service -n glamdrop || true
sleep 3

echo '8. Stato dei Pod distribuiti:'
kubectl get pods -n glamdrop -o wide
kubectl get pods -n ingress-nginx
EOF

echo ""
echo "=========================================================================="
echo " Deployment AWS completato con successo!"
echo "=========================================================================="
echo "Accedi all'applicazione web tramite:"
echo "   ${CLOUDFRONT_URL}"
echo ""

rm -f "$SAFE_KEY"

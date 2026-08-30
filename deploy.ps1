# ==========================================================================
#    [GlamDrop-AWS] Deploy su Cluster EC2 K8s + S3/CloudFront (PowerShell)
# ==========================================================================
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "   [GlamDrop-AWS] Deploy su Cluster Kubernetes EC2 + S3/CloudFront" -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan

# --- FASE 1: Recupero parametri da Terraform ---
Write-Host "`n=== [1/5] Recupero parametri e credenziali da Terraform ===" -ForegroundColor Yellow
Set-Location (Join-Path $scriptDir "terraform")

$CONTROL_PLANE_ID = (terraform output -raw control_plane_id 2>$null)
$CONTROL_PLANE_IP = (terraform output -raw control_plane_public_ip 2>$null)
$AWS_REGION = (terraform output -raw aws_region 2>$null)
if (-not $AWS_REGION) { $AWS_REGION = "eu-south-1" }
$S3_BUCKET = (terraform output -raw s3_frontend_bucket 2>$null)
$CLOUDFRONT_URL = (terraform output -raw cloudfront_domain_name 2>$null)
$CLOUDFRONT_DIST_ID = (terraform output -raw cloudfront_distribution_id 2>$null)
$SSH_KEY_PATH = "id_ed25519"

$ecrJson = (terraform output -json ecr_repository_urls 2>$null)
$AUTH_ECR = ""
$BOOKING_ECR = ""
$DROP_ECR = ""
$NOTIF_ECR = ""

if ($ecrJson) {
    try {
        $ecrObj = $ecrJson | ConvertFrom-Json
        $AUTH_ECR = $ecrObj.'auth-service'
        $BOOKING_ECR = $ecrObj.'booking-service'
        $DROP_ECR = $ecrObj.'drop-service'
        $NOTIF_ECR = $ecrObj.'notification-service'
    } catch {}
}

Set-Location $scriptDir

# Fallback automatico via AWS CLI se necessario
$AWS_ACCOUNT_ID = (aws sts get-caller-identity --query "Account" --output text 2>$null)
if (-not $CONTROL_PLANE_ID -or $CONTROL_PLANE_ID -eq "None") {
    $CONTROL_PLANE_ID = (aws ec2 describe-instances --filters "Name=tag:Name,Values=glamdrop-control-plane-1" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text --region $AWS_REGION 2>$null)
}
if (-not $S3_BUCKET -and $AWS_ACCOUNT_ID) {
    $S3_BUCKET = (aws s3api list-buckets --query "Buckets[?starts_with(Name, 'glamdrop-frontend')].Name" --output text 2>$null | Select-Object -First 1)
}
if (-not $AUTH_ECR -and $AWS_ACCOUNT_ID) {
    $AUTH_ECR = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/glamdrop/auth-service"
    $BOOKING_ECR = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/glamdrop/booking-service"
    $DROP_ECR = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/glamdrop/drop-service"
    $NOTIF_ECR = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/glamdrop/notification-service"
}
if (-not $CLOUDFRONT_URL -or -not $CLOUDFRONT_DIST_ID) {
    $CLOUDFRONT_DIST_ID = (aws cloudfront list-distributions --query "DistributionList.Items[?contains(Comment, 'glamdrop')].Id | [0]" --output text 2>$null)
    if ($CLOUDFRONT_DIST_ID -and $CLOUDFRONT_DIST_ID -ne "None") {
        $domain = (aws cloudfront get-distribution --id $CLOUDFRONT_DIST_ID --query "Distribution.DomainName" --output text 2>$null)
        $CLOUDFRONT_URL = "https://$domain"
    }
}

if (-not $CONTROL_PLANE_ID -and -not $CONTROL_PLANE_IP) {
    Write-Error "Impossibile determinare l'istanza Control Plane. Verifica i Terraform output."
    exit 1
}

Write-Host "  -> Control Plane ID: $CONTROL_PLANE_ID"
Write-Host "  -> Control Plane IP: $CONTROL_PLANE_IP"
Write-Host "  -> AWS Region: $AWS_REGION"
Write-Host "  -> S3 Frontend Bucket: $S3_BUCKET"
Write-Host "  -> CloudFront URL: $CLOUDFRONT_URL"
Write-Host "  -> CloudFront Dist ID: $CLOUDFRONT_DIST_ID"
Write-Host "  -> ECR Auth Service: $AUTH_ECR"

# --- FASE 2: Deploy Frontend su AWS S3 & CloudFront ---
Write-Host "`n=== [2/5] Deploy del Frontend su S3 e invalidazione CDN ===" -ForegroundColor Yellow
if ($S3_BUCKET -and $S3_BUCKET -ne "None") {
    Write-Host "  -> Sincronizzazione file statici su s3://$S3_BUCKET..."
    aws s3 sync frontend/ "s3://$S3_BUCKET/" --exclude "Dockerfile" --exclude "nginx.conf" --delete
    Write-Host "  [OK] Frontend caricato con successo su S3." -ForegroundColor Green

    if ($CLOUDFRONT_DIST_ID -and $CLOUDFRONT_DIST_ID -ne "None") {
        Write-Host "  -> Invalidazione cache CloudFront ($CLOUDFRONT_DIST_ID)..."
        aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_DIST_ID --paths "/*" | Out-Null
        Write-Host "  [OK] Invalidazione cache CloudFront richiesta." -ForegroundColor Green
    }
}

# --- FASE 3: Build & Push Immagini Docker su ECR ---
$hasDocker = Get-Command docker -ErrorAction SilentlyContinue
if ($hasDocker -and $AUTH_ECR) {
    Write-Host "`n=== [3/5] Build & Push immagini Docker su Amazon ECR ===" -ForegroundColor Yellow
    $REGISTRY = $AUTH_ECR.Split("/")[0]
    Write-Host "  -> Autenticazione con Amazon ECR ($REGISTRY)..."
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REGISTRY | Out-Null

    Write-Host "  -> Compilazione & caricamento auth-service..."
    docker build --platform linux/amd64 -q -t "${AUTH_ECR}:v1.0.0" services/auth-service/
    docker push -q "${AUTH_ECR}:v1.0.0"

    Write-Host "  -> Compilazione & caricamento booking-service..."
    docker build --platform linux/amd64 -q -t "${BOOKING_ECR}:v1.0.0" services/booking-service/
    docker push -q "${BOOKING_ECR}:v1.0.0"

    Write-Host "  -> Compilazione & caricamento drop-service..."
    docker build --platform linux/amd64 -q -t "${DROP_ECR}:v1.0.0" services/drop-service/
    docker push -q "${DROP_ECR}:v1.0.0"

    Write-Host "  -> Compilazione & caricamento notification-service..."
    docker build --platform linux/amd64 -q -t "${NOTIF_ECR}:v1.0.0" services/notification-service/
    docker push -q "${NOTIF_ECR}:v1.0.0"
    Write-Host "  [OK] Tutte le immagini sono caricate su Amazon ECR." -ForegroundColor Green
}

# --- FASE 4 & 5: Connessione e Rollout K8s sul Control Plane ---
Write-Host "`n=== [4/5] Trasferimento manifesti e rollout K8s sul Control Plane ===" -ForegroundColor Yellow

$SSH_KEY = Join-Path $scriptDir "terraform\id_ed25519"
if (-not (Test-Path $SSH_KEY)) {
    $SSH_KEY = Join-Path $scriptDir "terraform\$SSH_KEY_PATH"
}

$PROXY_CMD = "aws ssm start-session --target $CONTROL_PLANE_ID --document-name AWS-StartSSHSession --parameters portNumber=%p --region $AWS_REGION"
$TARGET_HOST = "ubuntu@$CONTROL_PLANE_ID"
if (-not $CONTROL_PLANE_ID -and $CONTROL_PLANE_IP) {
    $TARGET_HOST = "ubuntu@$CONTROL_PLANE_IP"
}

$REGISTRY = ""
if ($AUTH_ECR) { $REGISTRY = $AUTH_ECR.Split("/")[0] }
$ECR_PASS = (aws ecr get-login-password --region $AWS_REGION 2>$null)
$AWS_AK = (aws configure get aws_access_key_id 2>$null)
$AWS_SK = (aws configure get aws_secret_access_key 2>$null)

# Creazione archivio temporaneo dei manifesti k8s
$tempTar = [System.IO.Path]::GetTempFileName() + ".tar.gz"
tar -czf "$tempTar" -C k8s .

Write-Host "  -> Trasferimento manifesti via SSH/SSM..."
$sshOpts = @(
    "-i", "$SSH_KEY",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "ConnectTimeout=60",
    "-o", "ServerAliveInterval=15"
)
if ($CONTROL_PLANE_ID) {
    $sshOpts += @("-o", "ProxyCommand=$PROXY_CMD")
}

# Copia manifesti
scp @sshOpts "$tempTar" "${TARGET_HOST}:/tmp/k8s_manifests.tar.gz"
Remove-Item -Force "$tempTar" -ErrorAction SilentlyContinue

Write-Host "`n=== [5/5] Applicazione dei manifesti Kubernetes dei Microservizi ===" -ForegroundColor Yellow

$remoteScript = @"
set -e
export KUBECONFIG=/home/ubuntu/.kube/config
mkdir -p /home/ubuntu/k8s
tar -xzf /tmp/k8s_manifests.tar.gz -C /home/ubuntu/k8s
rm -f /tmp/k8s_manifests.tar.gz

echo '0. Verifica che i nodi Worker dell ASG siano connessi e pronti...'
for i in {1..60}; do
  READY_NODES=`$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
  if [ "`$READY_NODES" -ge 2 ]; then
    echo "  -> Nodi rilevati in stato Ready: `$READY_NODES"
    break
  fi
  echo "  -> In attesa dei nodi Worker... (`$READY_NODES/2 pronti, tentativo `$i/60)"
  sleep 10
done

echo '1. Applicazione Namespace, LimitRange e NetworkPolicies...'
kubectl apply -f /home/ubuntu/k8s/namespace.yaml
kubectl apply -f /home/ubuntu/k8s/network-policy.yaml

echo '2. Configurazione credenziali di autenticazione Amazon ECR...'
if [ -n "$ECR_PASS" ] && [ -n "$REGISTRY" ]; then
  kubectl create secret docker-registry ecr-secret -n glamdrop \
    --docker-server="$REGISTRY" \
    --docker-username=AWS \
    --docker-password="$ECR_PASS" \
    --dry-run=client -o yaml | kubectl apply -f -
  sleep 3
  kubectl patch serviceaccount default -n glamdrop -p '{"imagePullSecrets": [{"name": "ecr-secret"}]}' 2>/dev/null || true
fi
if [ -f /home/ubuntu/k8s/ecr-cronjob.yaml ]; then
  kubectl apply -f /home/ubuntu/k8s/ecr-cronjob.yaml
fi

echo '3. Applicazione Secrets Database, RabbitMQ, Redis e credenziali AWS...'
if [ -f /home/ubuntu/k8s/secret.yaml ]; then
  kubectl apply -f /home/ubuntu/k8s/secret.yaml
fi

if [ -n "$AUTH_ECR" ]; then
  echo '4. Aggiornamento percorsi immagini ECR nei manifesti...'
  sed -i "s|image: auth-service:v1.0.0|image: ${AUTH_ECR}:v1.0.0|g" /home/ubuntu/k8s/auth-service.yaml || true
  sed -i "s|image: booking-service:v1.0.0|image: ${BOOKING_ECR}:v1.0.0|g" /home/ubuntu/k8s/booking-service.yaml || true
  sed -i "s|image: drop-service:v1.0.0|image: ${DROP_ECR}:v1.0.0|g" /home/ubuntu/k8s/drop-service.yaml || true
  sed -i "s|image: notification-service:v1.0.0|image: ${NOTIF_ECR}:v1.0.0|g" /home/ubuntu/k8s/notification-service.yaml || true
fi

echo '5. Installazione Ingress Nginx Controller (NodePort 30080)...'
kubectl apply -f /home/ubuntu/k8s/ingress-nginx.yaml
kubectl delete ValidatingWebhookConfiguration ingress-nginx-admission --ignore-not-found 2>/dev/null || true

echo '6. Applicazione Microservizi Backend, HPA/PDB e Ingress...'
kubectl apply -f /home/ubuntu/k8s/auth-service.yaml
kubectl apply -f /home/ubuntu/k8s/booking-service.yaml
kubectl apply -f /home/ubuntu/k8s/drop-service.yaml
kubectl apply -f /home/ubuntu/k8s/notification-service.yaml
kubectl apply -f /home/ubuntu/k8s/hpa-pdb.yaml 2>/dev/null || true
kubectl apply -f /home/ubuntu/k8s/ingress.yaml

echo '7. Rollout restart...'
kubectl rollout restart deployment auth-service booking-service drop-service notification-service -n glamdrop 2>/dev/null || true
sleep 3

echo '8. Stato dei Pod distribuiti:'
kubectl get pods -n glamdrop -o wide
kubectl get pods -n ingress-nginx
"@

ssh @sshOpts "$TARGET_HOST" "$remoteScript"

Write-Host "`n==========================================================================" -ForegroundColor Green
Write-Host " Deployment AWS completato con successo!" -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host "Accedi all'applicazione web tramite:" -ForegroundColor Cyan
Write-Host "   $CLOUDFRONT_URL" -ForegroundColor Yellow
Write-Host ""

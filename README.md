<div align="center">

<img src="docs/assets/logo.png" alt="GlamDrop Logo" width="160"/>

<h1 align="center">GlamDrop AWS — Beauty Booking Platform su Kubernetes EC2</h1>

<p align="center">
  Applicazione web 3-tier a microservizi distribuita su <strong>Amazon Web Services (AWS)</strong>.<br>
  Cluster Kubernetes autogestito con Control Plane su istanza EC2, Worker Nodes scalabili su Auto Scaling Group,<br>
  driver di rete <strong>Calico CNI</strong> e persistenza delegata interamente ai <strong>Servizi Gestiti AWS</strong>.<br>
  Mitigazione atomica del <strong>Thundering Herd Problem</strong> tramite script Lua in-memory su ElastiCache Redis.
</p>

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
![Status](https://img.shields.io/badge/status-active-success.svg?style=for-the-badge)
![Kubernetes](https://img.shields.io/badge/kubernetes-1.31-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-EC2%20%7C%20RDS%20%7C%20Redis%20%7C%20MQ-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-Automation-EE0000?style=for-the-badge&logo=ansible&logoColor=white)
![Calico](https://img.shields.io/badge/Calico-Zero--Trust%20CNI-FFA500?style=for-the-badge)

</div>

---

## 🎯 Panoramica

**GlamDrop AWS** (Infrastruttura A) rappresenta l'implementazione cloud-native dell'architettura GlamDrop basata su un cluster Kubernetes autogestito (*self-managed*) su macchine **Amazon EC2**, integrato con l'ecosistema dei servizi gestiti AWS.

La piattaforma mette in relazione tre tipologie di utenti:

<div align="center">

| 👤 Ruolo | Descrizione |
|:---:|---|
| ![Cliente](https://img.shields.io/badge/Cliente-8A2BE2?style=flat-square) | Ricerca saloni con autocompletamento geografico, prenota trattamenti e riscatta i Drop promozionali |
| ![Gestore](https://img.shields.io/badge/Gestore-FF69B4?style=flat-square) | Amministra il catalogo servizi, configura orari/turni del personale e monitora le prenotazioni |
| ![Estetista](https://img.shields.io/badge/Estetista-20B2AA?style=flat-square) | Consulta l'agenda appuntamenti in tempo reale e segnala indisponibilità o assenze |

</div>

### ⚡ Il Concetto di "Drop" e la Gestione della Concorrenza
Il fulcro del sistema sono i **Drop**: promozioni flash a disponibilità limitata generate automaticamente con il **50% di sconto** a seguito di cancellazioni tardive (< 24h dall'appuntamento). 
Per scongiurare il **Thundering Herd Problem** e l'overselling durante i picchi simultanei di claim, la concorrenza è gestita mediante **script atomici Lua** eseguiti nel single-thread di **Amazon ElastiCache Redis 7**, rispondendo con HTTP `202 Accepted` all'unico vincitore e HTTP `409 Conflict` agli altri utenti in < 2ms, delegando il salvataggio a worker asincroni su **Amazon MQ RabbitMQ**.

![divider](https://capsule-render.vercel.app/api?type=soft&color=0:FF69B4,100:FFA500&height=3&section=header)

### ✨ Funzionalità principali

| Area | Funzionalità |
|---|---|
| 🔐 **Autenticazione & Saloni** | Registrazione multi-ruolo (Cliente, Gestore, Dipendente), login con token JWT firmati, gestione anagrafica e dataset ISTAT dei comuni italiani |
| 📅 **Prenotazioni & Disponibilità** | Catalogo trattamenti con 7 categorie, calcolo slot a intervalli di 15m, lock pessimistici sul DB relazionale e rilevamento anti-sovrapposizione |
| ⚡ **Flash Drop & Lock Atomico** | Generazione automatica da disdette tardive, lock atomico in-memory Redis (`HGET` + `HSET`), ingestione asincrona su coda RabbitMQ |
| 🔔 **Notifiche Event-Driven** | Consumer multithread AMQP su RabbitMQ, formattazione notifiche contestuali e persistenza su tabella NoSQL **Amazon DynamoDB** |
| 🌐 **Edge Delivery & Sicurezza** | Frontend distribuito su **Amazon S3 + CloudFront CDN**, routing Layer 7 con **ALB + Ingress Nginx** e validazione header segreto `X-Origin-Verify` |

---

## 🏗 Architettura & Flusso degli Eventi

<div align="center">

<img src="docs/assets/Architettura.png" alt="Architettura del sistema GlamDrop" width="90%"/>

![divider](https://capsule-render.vercel.app/api?type=soft&color=0:FF69B4,100:FFA500&height=3&section=header)

<img src="docs/assets/Applicazione.png" alt="Interfaccia dell'applicazione GlamDrop" width="90%"/>

![divider](https://capsule-render.vercel.app/api?type=soft&color=0:FF69B4,100:FFA500&height=3&section=header)

</div>

### 📸 Schema Architetturale AWS

```
[ Utente / Browser ]
        │
        ▼
[ Amazon CloudFront CDN ] (PriceClass_100, OAC, Security Headers, SPA Fallback)
   ├── /*         ──► [ Amazon S3 Bucket ] (Frontend SPA Statico: HTML5/CSS3/Vanilla JS)
   └── /api/*     ──► [ AWS Application Load Balancer (ALB) ]
                            │ (Port 80 -> NodePort 30080, X-Origin-Verify)
                            ▼
            [ Kubernetes Cluster su EC2 (Control Plane + Auto Scaling Group Workers) ]
            ┌─────────────────────────────────────────────────────────┐
            │  • EC2 Auto Scaling Group (Launch Template + SSM Join)  │
            │  • Ingress Nginx Controller (NodePort: 30080)           │
            │  • Auth Service (Node.js/Express, 2 Repliche, HPA)      │
            │  • Booking Service (Node.js/Express, 2 Repliche, HPA)   │
            │  • Drop Service (Node.js/Express, 2 Repliche, HPA)      │
            │  • Notification Service (Python/Flask, 2 Repliche, HPA) │
            │  • Calico CNI (NetworkPolicy Enforcement L3/L4)         │
            └─────────────────────────────────────────────────────────┘
                    │             │            │            │
                    ▼             ▼            ▼            ▼
             [ Amazon RDS ]  [ Amazon MQ ] [ ElastiCache ] [ DynamoDB ]
             (PostgreSQL 15)  (RabbitMQ)     (Redis 7)     (Notifications)
             (Encrypted gp3)  (AMQPS TLS)   (In-Transit)   (Pay-Per-Request)
```

### 🔄 Flusso degli eventi
1. Un **cliente cancella** una prenotazione con anticipo < 24h $\rightarrow$ il *Booking Service* pubblica `booking.cancelled.late` su **Amazon MQ (RabbitMQ)**.
2. Il **Drop Service** consuma l'evento: genera il record promozionale su **RDS PostgreSQL** e carica il payload su **ElastiCache Redis** con TTL dinamico.
3. Più clienti tentano simultaneamente il claim $\rightarrow$ lo script Lua in **Redis** esegue il lock atomico: il primo riceve `202 Accepted`, mentre tutti gli altri ricevono istantaneamente `409 Conflict`.
4. Il claim vincitore viene inviato sulla coda `drop.claims.processing` per la finalizzazione asincrona su RDS e l'aggiornamento dell'agenda su Booking Service.
5. Il **Notification Service** consuma gli eventi e persiste l'audit trail delle notifiche su **Amazon DynamoDB**.

---

## 🛠 Stack Tecnologico & Mappatura Servizi AWS

<div align="center">

<img src="https://skillicons.dev/icons?i=nodejs,express,python,flask,postgres,redis,html,css,js,nginx,docker,kubernetes,terraform,ansible,aws" alt="Tech stack icons"/>

</div>

| Modulo / Servizio | Tecnologia | Servizio AWS / Hosting | Responsabilità & Dettagli |
| :--- | :--- | :--- | :--- |
| **Frontend SPA** | HTML5, CSS3, JS ES6+ | **Amazon S3 + CloudFront CDN** | Hosting statico su S3 protetto da Origin Access Control (OAC), fallback SPA `/index.html`, Security Headers e caching edge. |
| **Reverse Proxy / Ingress** | AWS ALB + Ingress Nginx | **Application Load Balancer** | Instradamento del traffico `/api/*` verso il target group dei worker sulla NodePort `30080` con filtro header `X-Origin-Verify`. |
| **Auth Service** | Node.js 20, Express, pg, bcrypt, jwt | **K8s su EC2 + Amazon RDS** | Autenticazione JWT, anagrafica saloni e clienti; persistenza su **PostgreSQL 15 (RDS)** con cifratura at-rest KMS e SSL forzato (`rds.force_ssl=1`). |
| **Booking Service** | Node.js 20, Express, pg, amqplib | **K8s su EC2 + RDS & Amazon MQ** | Gestione prenotazioni, turni e cancellazioni; emissione eventi AMQP su **Amazon MQ RabbitMQ (AMQPS TLS)**. |
| **Drop Service** | Node.js 20, Express, pg, redis, amqplib | **K8s su EC2 + RDS, Redis & MQ** | Gestione flash sales con claiming ad alta concorrenza via script Lua su **ElastiCache Redis 7** e persistenza su **PostgreSQL**. |
| **Notification Service** | Python 3.11, Flask, boto3, pika | **K8s su EC2 + Amazon MQ & DynamoDB** | Consumer AMQP per notifiche asincrone; persistenza NoSQL su **DynamoDB** (Pay-Per-Request con GSI `AllNotificationsIndex`). |
| **Message Broker** | RabbitMQ 3.13 (AMQPS) | **Amazon MQ for RabbitMQ** | Broker gestito per il disaccoppiamento affidabile degli eventi con canale cifrato TLS (porta 5671). |
| **In-Memory Cache** | Redis 7 | **Amazon ElastiCache Redis** | Cluster gestito con crittografia at-rest KMS, transit encryption TLSv1.2 e autenticazione tramite Redis AUTH token. |
| **Secrets & Config** | SSM Parameter Store | **AWS Systems Manager** | Archiviazione centralizzata e cifrata dei secret (`SecureString`) e generazione automatica dei secret K8s. |
| **Container Registry** | Docker Multi-Stage | **Amazon ECR** | Repository privato con scansione automatica vulnerabilità e lifecycle policies. |
| **Monitoring & Alarms** | CloudWatch Metrics | **Amazon CloudWatch** | Allarmi proattivi su CPU Control Plane/Worker, storage RDS e codici 5XX sull'ALB. |

---

## ⚙️ Infrastruttura

### 🖥️ Cluster Kubernetes su EC2

| Istanza / Componente | Ruolo | Tipo EC2 | vCPU | RAM | Rete & Sicurezza |
|:---|:---:|:---:|:---:|:---:|:---|
| `glamdrop-control-plane-1` | 🧠 Control Plane | `t3.micro` | 2 | 1 GB | Subnet Pubblica AZ-a (10.0.1.0/24), SSM Managed, kubeadm v1.31 |
| `glamdrop-worker-asg` (x2) | ⚙️ Worker Nodes | `t3.micro` | 2 | 1 GB | Auto Scaling Group Multi-AZ (AZ-a & AZ-b), Self-Join via SSM |
| `glamdrop-cni` | 🌐 Network Driver | Calico CNI | — | — | Overlay VXLAN + NetworkPolicies L3/L4 Zero-Trust |

### 📦 Pipeline IaC & Deployment

```
┌─────────────────────────────────┐
│     1. TERRAFORM APPLY          │ ──► Crea VPC, EC2, RDS, ElastiCache, MQ, ALB, SSM, S3/CDN
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│     2. ANSIBLE PLAYBOOK         │ ──► Inizializza Control Plane, Calico CNI e Join Token su SSM
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│     3. ASG SELF-BOOTSTRAP       │ ──► I nodi Worker recuperano il token da SSM e si uniscono
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│     4. ./deploy.sh              │ ──► Build & Push ECR, Apply Manifests K8s, Sync S3 Frontend
└─────────────────────────────────┘
```

---

## 🚀 Guida al Deployment su AWS (Step-by-Step)

Il deployment completo dell'Infrastruttura A si esegue in **3 passaggi automatizzati**:

### ✅ Prerequisiti
- **AWS CLI (v2)** installata e autenticata (`aws configure`).
- **Terraform** (>= 1.5.0).
- **Ansible** (>= 2.12) e client **OpenSSH** (su Linux o WSL2).
- **AWS Session Manager Plugin** per accesso SSH trasparente via SSM.
- **Docker** (opzionale, per compilare e caricare le immagini su ECR).

---

### 1️⃣ Passo 1: Provisioning dell'Infrastruttura con Terraform

1. Spostati nella cartella `terraform/`:
   ```bash
   cd terraform
   terraform init
   ```
2. Genera la chiave SSH per i nodi (se non già presente):
   ```bash
   ssh-keygen -t ed25519 -f id_ed25519 -N ""
   ```
3. Avvia il provisioning delle risorse su AWS:
   ```bash
   terraform apply -auto-approve
   ```
   *Terraform creerà la VPC Multi-AZ, i Security Group concatenati, l'EC2 Control Plane, il Launch Template e l'ASG Worker, RDS PostgreSQL, ElastiCache Redis, Amazon MQ, DynamoDB, l'ALB, il bucket S3 con CloudFront OAC e genererà automaticamente `ansible/hosts.ini` e `k8s/secret.yaml`.*

---

### 2️⃣ Passo 2: Configurazione del Cluster con Ansible

Dalla root del repository, esegui il playbook Ansible (oppure usa lo script helper):

```bash
cd ansible
bash run-ansible.sh
```

*In alternativa tramite comando diretto:*
```bash
ansible-playbook -i hosts.ini site.yml
```

#### Cosa esegue Ansible:
- **`00-prerequisites.yml`**: Configura parametri kernel sysctl, swapfile da 2GB, runtime **containerd** e tool **Kubernetes v1.31**.
- **`01-control-plane.yml`**: Esegue `kubeadm init`, installa **Calico CNI**, genera il token di join permanente e lo salva su **AWS SSM Parameter Store** (`/glamdrop/k8s/join_command`). I nodi worker dell'ASG prelevano autonomamente il token all'avvio completando il bootstrap.

---

### 3️⃣ Passo 3: Deployment dei Microservizi e Frontend (`deploy.sh` / `deploy.ps1`)

Dalla radice del repository, lancia lo script orchestratore (Bash su Linux/WSL/Git Bash o PowerShell su Windows):

```bash
# Su Linux / WSL / Git Bash:
chmod +x deploy.sh
./deploy.sh

# Oppure su Windows PowerShell:
.\deploy.ps1
```

#### Fasi eseguite automaticamente dallo script:
1. **Recupero Parametri**: Estrae gli endpoint live dagli output Terraform (IP Control Plane, S3, CloudFront, ECR).
2. **Deploy Frontend**: Sincronizza i file statici su S3 e richiede l'invalidazione della cache CloudFront.
3. **Build & Push ECR**: Compila le immagini Docker dei quattro microservizi e le carica sui repository Amazon ECR.
4. **Trasferimento Manifesti**: Invia in sicurezza i manifesti Kubernetes al Control Plane tramite tunnel AWS SSM Session Manager.
5. **Rollout Kubernetes**: Applica Namespace, Secret, NetworkPolicies Calico, Ingress Nginx Controller (NodePort 30080), microservizi backend e regole HPA/PDB.

Al termine, l'applicazione sarà accessibile pubblicamente all'URL CloudFront:
```
👉 https://dxxxxxxxxxxxx.cloudfront.net
```

---

## 🔧 Configurazione Variabili d'Ambiente e Secret Kubernetes

### 1️⃣ File di Configurazione Locale (`.env.example`)
I microservizi backend supportano la configurazione tramite variabili d'ambiente:
```ini
# PostgreSQL (Amazon RDS)
POSTGRES_USER=postgres
POSTGRES_PASSWORD=secure_random_password
DB_HOST=glamdrop-postgres-db.xxxxxxxx.eu-south-1.rds.amazonaws.com
DB_PORT=5432
DB_NAME=auth_db    # auth_db | booking_db | drop_db

# JWT Secret
JWT_SECRET=super_secure_jwt_secret_key

# Message Broker (Amazon MQ) & Cache (ElastiCache)
RABBITMQ_URL=amqps://glamdrop_user:password@b-xxxx.mq.eu-south-1.amazonaws.com:5671
REDIS_URL=rediss://:auth_token@glamdrop-redis.xxxx.cache.amazonaws.com:6379
```

### 2️⃣ Secret Kubernetes (`k8s/secret.yaml`)
> [!IMPORTANT]
> Il file `k8s/secret.yaml` viene **generato automaticamente da Terraform** durante la fase di provisioning, iniettando le password casuali generate e gli endpoint effettivi dei servizi AWS gestiti. Non è necessario modificare manualmente i segreti per il deployment su AWS.

---

## 🧪 Test Automatizzati

### 🐑 Test Concorrenza Drop — "Thundering Herd"
Simula **50 clienti concorrenti** che tentano simultaneamente di riscattare l'ultimo Drop disponibile:
```bash
python tests/test-concurrency.py --endpoint https://<CLOUDFRONT_DOMAIN>/api
```
- ✅ **Esito atteso**: esattamente **1 client** riceve HTTP `202 Accepted` (claim confermato), mentre i restanti **49** ricevono HTTP `409 Conflict`.
- 🔒 **Integrità**: quantità residua pari a `0`, nessun overselling o deadlock su RDS.

### 📆 Test Sovrapposizione Prenotazioni
Verifica i vincoli di non sovrapposizione degli appuntamenti per lo stesso operatore:
```bash
python tests/test-booking-overlap.py --endpoint https://<CLOUDFRONT_DOMAIN>/api
```

| # | Scenario di Test | Esito Atteso |
|:---:|---|:---:|
| 1 | Prenotazione slot base (10:00–11:00) | ✅ Confermata (201) |
| 2 | Stesso identico orario sullo stesso operatore | ❌ Conflitto (409) |
| 3 | Sovrapposizione parziale inizio (10:30–11:30) | ❌ Conflitto (409) |
| 4 | Sovrapposizione parziale fine (09:30–10:30) | ❌ Conflitto (409) |
| 5 | Intervallo interamente contenuto (10:15–10:45) | ❌ Conflitto (409) |
| 6 | Slot adiacente senza sovrapposizione (11:00–12:00) | ✅ Confermata (201) |
| 7 | Cancellazione e ri-prenotazione dello stesso slot | ✅ Confermata (201) |

---

## 🛡️ Sicurezza, Hardening e DevSecOps

- **Crittografia Completa**:
  - **RDS PostgreSQL**: storage cifrato con AWS KMS, parametro `rds.force_ssl=1` e certificato CA AWS.
  - **Amazon MQ**: endpoint AMQPS con canale TLS obbligatorio (porta 5671).
  - **ElastiCache Redis**: crittografia at-rest KMS, in-transit TLSv1.2 e autenticazione obbligatoria tramite Redis AUTH.
  - **Amazon S3 & CloudFront**: crittografia SSE-S3 AES-256, forzatura HTTPS e policy Origin Access Control (OAC).
- **Protezione Perimetrale ALB**:
  - Validazione header segreto `X-Origin-Verify` generato da Terraform: l'ALB risponde con HTTP `403 Forbidden` a qualsiasi richiesta che tenti di bypassare CloudFront.
- **Isolamento di Rete & NetworkPolicies**:
  - Database e broker confinati in Subnet Private prive di rotte Internet.
  - Policy **Calico CNI** Zero-Trust con blocco predefinito del traffico (*default-deny*) e autorizzazione granulare solo tra i pod necessari.
- **Hardening dei Container**:
  - Esecuzione obbligatoria con utente non-root, `allowPrivilegeEscalation: false` e drop di tutte le capabilities Linux (`drop: ALL`).
- **Pipeline DevSecOps CI/CD**:
  - Scansione secret con **Gitleaks**, analisi statica del codice (SAST) con **Semgrep** e conformità IaC con **Checkov**.

---

## 🧹 Teardown dell'Infrastruttura

Per distruggere determinatisticamente tutte le risorse create su AWS ed azzerare i costi:

```bash
cd terraform
terraform destroy -auto-approve
```

---

<div align="center">

![Footer wave](https://capsule-render.vercel.app/api?type=waving&color=0:FF69B4,100:FFA500&height=150&section=footer&text=GlamDrop%20AWS%20Infrastructure%20A&fontSize=26&fontColor=ffffff&animation=fadeIn)

</div>
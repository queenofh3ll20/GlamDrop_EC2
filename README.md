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

## 📑 Indice

- [Panoramica](#-panoramica)
- [Funzionalità Principali](#-funzionalità-principali)
- [Architettura & Flusso degli Eventi](#-architettura--flusso-degli-eventi)
- [Stack Tecnologico & Mappatura Servizi AWS](#-stack-tecnologico--mappatura-servizi-aws)
- [Infrastruttura](#️-infrastruttura)
- [Deployment](#-deployment-su-aws)
- [Configurazione](#-configurazione-variabili-dambiente-e-secret-kubernetes)
- [Test Automatizzati](#-test-automatizzati)
- [Sicurezza](#️-sicurezza-hardening-e-devsecops)
- [Teardown](#-teardown-dellinfrastruttura)
- [Struttura del Progetto](#-struttura-del-progetto)

## 🎯 Panoramica

**GlamDrop** è un'applicazione web 3-tier a microservizi per la prenotazione di servizi beauty e la gestione di promozioni flash (*Drop*) a disponibilità limitata. Il sistema copre l'intero ciclo di vita del software: dall'**Infrastructure as Code** (IaC) al **frontend**, integrando orchestrazione dei container, messaggistica asincrona event-driven e gestione della concorrenza ad alte prestazioni.

> Questa versione (**Infrastruttura A**) rappresenta l'implementazione cloud-native su **Amazon Web Services (AWS)** con cluster Kubernetes autogestito (*self-managed*) su macchine **Amazon EC2** e persistenza su servizi gestiti AWS.

La piattaforma mette in relazione tre tipologie di utenti:

<div align="center">

| 👤 Ruolo | Descrizione |
|:---:|---|
| ![Cliente](https://img.shields.io/badge/Cliente-8A2BE2?style=flat-square) | Ricerca saloni con autocompletamento geografico (dataset ISTAT), prenota trattamenti estetici e riscatta i Drop promozionali |
| ![Gestore](https://img.shields.io/badge/Gestore-FF69B4?style=flat-square) | Amministra il salone, gestisce il catalogo trattamenti, configura turni/orari del personale e monitora le prenotazioni |
| ![Estetista](https://img.shields.io/badge/Estetista-20B2AA?style=flat-square) | Consulta l'agenda appuntamenti in tempo reale, visualizza i dettagli dei trattamenti e segnala indisponibilità |

</div>

### ⚡ Il Concetto di "Drop" e la Gestione della Concorrenza

Il cuore della piattaforma sono i **Drop**: promozioni flash a disponibilità limitata con **sconto del 50%**, generate automaticamente a seguito di cancellazioni tardive (< 24 ore dall'appuntamento) o create manualmente dai gestori.

Per mitigare il **Thundering Herd Problem** ed evitare fenomeni di *overselling* durante i picchi simultanei di richiesta:
1. **Lock Atomico in-memory**: La concorrenza sul riscatto è gestita a livello di cache in-memory (**Redis**) tramite operazioni atomiche (`SET NX` / script Lua single-thread).
2. **Latenza Sub-millisecondo**: Il sistema risponde immediatamente con HTTP `202 Accepted` all'unico vincitore del claim e con HTTP `409 Conflict` a tutti gli altri tentativi concorrenti in $< 2\text{ms}$.
3. **Persistenza Asincrona Event-Driven**: Il claim confermato viene pubblicato su una coda dedicata (**RabbitMQ**) per la finalizzazione asincrona su database relazionale (**PostgreSQL**) e l'aggiornamento in tempo reale delle agende.

![divider](https://capsule-render.vercel.app/api?type=soft&color=0:FF69B4,100:FFA500&height=3&section=header)

### ✨ Funzionalità principali

| Area | Funzionalità |
|---|---|
| 🔐 **Autenticazione & Saloni** | Registrazione multi-ruolo (Cliente, Gestore, Estetista), login stateless con token JWT firmati, validazione geografica basata sul dataset ISTAT dei comuni italiani |
| 📅 **Prenotazioni & Disponibilità** | Catalogo servizi suddiviso in 7 categorie (~30 trattamenti), calcolo slot a intervalli di 15m, lock sul database con algoritmo di rilevamento anti-sovrapposizione |
| ⚡ **Flash Drop & Lock Atomico** | Generazione automatica da cancellazioni tardive (sconto 50%), countdown temporizzato, lock atomico in-memory su Redis e ingestione asincrona |
| 🔔 **Notifiche Event-Driven** | Architettura a eventi tramite code RabbitMQ: notifiche contestuali per prenotazioni, cancellazioni, riscatti Drop e recensioni |
| ⭐ **Recensioni & Valutazioni** | Sistema di feedback a 5 stelle con commenti e ricalcolo automatico del punteggio medio del salone |

---

## 🏗 Architettura & Flusso degli Eventi

<div align="center">

<img src="docs/assets/Architettura.png" alt="Architettura del sistema GlamDrop" width="90%"/>

![divider](https://capsule-render.vercel.app/api?type=soft&color=0:FF69B4,100:FFA500&height=3&section=header)

<img src="docs/assets/Applicazione.png" alt="Interfaccia dell'applicazione GlamDrop" width="90%"/>

![divider](https://capsule-render.vercel.app/api?type=soft&color=0:FF69B4,100:FFA500&height=3&section=header)

</div>


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

---

## 🚀 Deployment su AWS

Il deployment dell'infrastruttura e dei microservizi su AWS si articola in **3 fasi automatizzate**, eseguibili sia da ambienti Linux/macOS sia da Windows.


### 🐧 Opzione A — Deploy da Linux / WSL / macOS

#### ✅ Prerequisiti

| Strumento | Versione Minima | Note |
|:---|:---:|:---|
| [AWS CLI](https://aws.amazon.com/cli/) | v2 | Configurata con `aws configure` |
| [Terraform](https://www.terraform.io/) | 1.5+ | Provisioning IaC |
| [Ansible](https://docs.ansible.com/) | 2.12+ | Configurazione cluster K8s |
| [OpenSSH](https://www.openssh.com/) | — | Client SSH per Ansible |
| [AWS SSM Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) | — | Accesso SSH trasparente via SSM |
| [Docker](https://docs.docker.com/get-docker/) | 20.10+ | Build e push immagini su ECR |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.31+ | Client CLI per Kubernetes |

#### 1️⃣ Provisioning Infrastruttura con Terraform

```bash
cd terraform
terraform init

# Genera la chiave SSH per i nodi (se non già presente)
ssh-keygen -t ed25519 -f id_ed25519 -N ""

# Avvia il provisioning delle risorse su AWS
terraform apply -auto-approve
```

*Terraform creerà la VPC Multi-AZ, i Security Group, l'EC2 Control Plane, il Launch Template e l'ASG Worker, RDS PostgreSQL, ElastiCache Redis, Amazon MQ, DynamoDB, l'ALB, il bucket S3 con CloudFront OAC e genererà automaticamente `ansible/hosts.ini` e `k8s/secret.yaml`.*

#### 2️⃣ Configurazione del Cluster con Ansible

```bash
cd ansible
bash run-ansible.sh

# In alternativa, tramite comando diretto:
ansible-playbook -i hosts.ini site.yml
```

**Cosa esegue Ansible:**
- **`00-prerequisites.yml`**: Configura parametri kernel sysctl, swapfile da 2GB, runtime **containerd** e tool **Kubernetes v1.31**.
- **`01-control-plane.yml`**: Esegue `kubeadm init`, installa **Calico CNI**, genera il token di join permanente e lo salva su **AWS SSM Parameter Store** (`/glamdrop/k8s/join_command`). I nodi worker dell'ASG prelevano autonomamente il token all'avvio.

#### 3️⃣ Deployment Microservizi e Frontend

```bash
# Dalla root del repository
chmod +x deploy.sh
./deploy.sh
```

![divider](https://capsule-render.vercel.app/api?type=soft&color=0:FF69B4,100:FFA500&height=3&section=header)

### 🪟 Opzione B — Deploy da Windows (PowerShell)

#### ✅ Prerequisiti

| Strumento | Versione Minima | Note |
|:---|:---:|:---|
| [AWS CLI](https://aws.amazon.com/cli/) | v2 | Configurata con `aws configure` |
| [Terraform](https://www.terraform.io/) | 1.5+ | Provisioning IaC |
| [WSL 2](https://docs.microsoft.com/en-us/windows/wsl/) | — | Con Ansible installato al suo interno |
| [AWS SSM Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) | — | Accesso SSH trasparente via SSM |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | 4.0+ | Build e push immagini su ECR |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.31+ | Client CLI per Kubernetes |

#### 1️⃣ Provisioning Infrastruttura con Terraform

```powershell
cd terraform
terraform init

# Genera la chiave SSH per i nodi (se non già presente)
ssh-keygen -t ed25519 -f id_ed25519 -N '""'

# Avvia il provisioning
terraform apply -auto-approve
```

#### 2️⃣ Configurazione del Cluster con Ansible (via WSL)

```powershell
# Ansible richiede un ambiente Linux — esecuzione tramite WSL
wsl bash -c "cd ansible && bash run-ansible.sh"
```

#### 3️⃣ Deployment Microservizi e Frontend

```powershell
# Dalla root del repository
.\deploy.ps1
```

![divider](https://capsule-render.vercel.app/api?type=soft&color=0:FF69B4,100:FFA500&height=3&section=header)

### 📋 Fasi Eseguite dallo Script di Deploy

Indipendentemente dalla piattaforma, lo script di deploy esegue automaticamente:

1. **Recupero Parametri** → Estrae gli endpoint live dagli output Terraform (IP Control Plane, S3, CloudFront, ECR)
2. **Deploy Frontend** → Sincronizza i file statici su S3 e richiede l'invalidazione della cache CloudFront
3. **Build & Push ECR** → Compila le immagini Docker dei quattro microservizi e le carica sui repository Amazon ECR
4. **Trasferimento Manifesti** → Invia i manifesti Kubernetes al Control Plane tramite tunnel AWS SSM Session Manager
5. **Rollout Kubernetes** → Applica Namespace, Secret, NetworkPolicies Calico, Ingress Nginx Controller (NodePort 30080), microservizi backend e regole HPA/PDB

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

## 🧹 Teardown dell'Infrastruttura

Per distruggere determinatisticamente tutte le risorse create su AWS ed azzerare i costi:

```bash
cd terraform
terraform destroy -auto-approve
```

## 📂 Struttura del Progetto

```
GlamDrop_EC2/
├── 📄 README.md
├── 📄 LICENSE
├── 📄 .gitignore
├── 🔧 deploy.sh                          # Script deploy completo (Linux/macOS)
├── 🔧 deploy.ps1                         # Script deploy completo (Windows)
├── 📁 docs/
│   └── 📁 assets/                        # Logo e diagrammi architetturali
├── 📁 services/
│   ├── 📁 auth-service/                  # Microservizio autenticazione (Node.js/Express)
│   ├── 📁 booking-service/               # Microservizio prenotazioni (Node.js/Express)
│   ├── 📁 drop-service/                  # Microservizio promozioni flash (Node.js/Express)
│   └── 📁 notification-service/          # Microservizio notifiche (Python/Flask)
├── 📁 frontend/                          # Frontend SPA (HTML/CSS/JS)
├── 📁 terraform/                         # Configurazione Terraform (VPC, EC2, RDS, Redis, MQ, ALB, S3, CDN)
├── 📁 ansible/                           # Playbook Ansible (setup K8s + Calico CNI)
│   ├── 📄 hosts.ini                      # Generato automaticamente da Terraform
│   ├── 📄 site.yml
│   └── 🔧 run-ansible.sh
├── 📁 k8s/                               # Manifest Kubernetes
│   └── 📄 *.yaml                         # Deployment, Service, Ingress, NetworkPolicy, HPA, PDB, Secret
└── 📁 tests/
    ├── 📄 test-concurrency.py            # Test Thundering Herd (50 client concorrenti)
    └── 📄 test-booking-overlap.py        # Test sovrapposizione prenotazioni (7 scenari)
```

<div align="center">

![Footer wave](https://capsule-render.vercel.app/api?type=waving&color=0:FF69B4,100:FFA500&height=150&section=footer&text=GlamDrop%20AWS%20Infrastructure%20A&fontSize=26&fontColor=ffffff&animation=fadeIn)

</div>
# 🤖 Ansible Playbooks — GlamDrop AWS (Infrastruttura A)

Questo modulo gestisce l'automazione, l'inizializzazione e la configurazione software del cluster Kubernetes autogestito (*self-managed*) su macchine **Amazon EC2**.

---

## 📂 Struttura del Modulo

```
ansible/
├── 00-prerequisites.yml  # Configurazione Kernel, containerd e pacchetti K8s v1.31
├── 01-control-plane.yml  # Inizializzazione kubeadm, Calico CNI e join token su SSM
├── ansible.cfg           # Configurazione globale di Ansible
├── hosts.ini.example     # Template di inventario
├── run-ansible.sh        # Script di esecuzione automatizzato con Session Manager
└── site.yml              # Playbook principale sequenziale
```

---

## ⚙️ Sequenza Operativa

I playbook vengono eseguiti in sequenza tramite `site.yml`:

1. **`00-prerequisites.yml`**:
   - Abilita i moduli kernel `overlay` e `br_netfilter`.
   - Imposta i parametri `sysctl` (`net.bridge.bridge-nf-call-iptables`, `net.ipv4.ip_forward`).
   - Crea e attiva uno swapfile da 2GB per la stabilità delle istanze `t3.micro`.
   - Installa e configura il container runtime **containerd** con supporto `SystemdCgroup`.
   - Installa i pacchetti ufficiali Kubernetes (**`kubelet`**, **`kubeadm`**, **`kubectl` v1.31**).

2. **`01-control-plane.yml`**:
   - Inizializza il Control Plane con `kubeadm init --pod-network-cidr=192.168.0.0/16`.
   - Configura le credenziali di accesso `~/.kube/config` per l'utente `ubuntu`.
   - Installa il driver di rete **Calico CNI** per l'applicazione delle NetworkPolicy Zero-Trust.
   - Genera un token di join permanente (`kubeadm token create --print-join-command --ttl 0`).
   - Pubblica in modo sicuro il comando di join su **AWS SSM Parameter Store** al percorso `/glamdrop/k8s/join_command`.

---

## 🚀 Istruzioni per l'Esecuzione

### Prerequisito
Assicurarsi che il provisioning con Terraform sia completato (`cd ../terraform && terraform apply`), in quanto Terraform genera automaticamente il file `hosts.ini` e la chiave privata SSH `id_ed25519`.

### Esecuzione Rapida
Dalla cartella `ansible/`:
```bash
bash run-ansible.sh
```

### Esecuzione Manuale
```bash
ansible-playbook -i hosts.ini site.yml
```

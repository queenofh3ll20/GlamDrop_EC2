#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================================="
echo "  GlamDrop - Ansible Playbook Execution (WSL)"
echo "=========================================================="

echo "[1/4] Verifica prerequisiti..."

if ! command -v ansible-playbook &>/dev/null; then
    echo "[ERRORE] ansible non trovato. Installa con: sudo apt install ansible"
    exit 1
fi

if ! command -v aws &>/dev/null; then
    echo "[ERRORE] AWS CLI non trovato. Installa AWS CLI v2."
    exit 1
fi

if ! command -v session-manager-plugin &>/dev/null; then
    echo "[WARN] Session Manager Plugin non trovato. Installazione automatica..."
    curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o /tmp/session-manager-plugin.deb
    sudo dpkg -i /tmp/session-manager-plugin.deb
    rm -f /tmp/session-manager-plugin.deb
    echo "[OK] Session Manager Plugin installato."
fi

echo "[2/4] Verifica inventario e chiave SSH..."

# Normalizza preventivamente i file da eventuali ritorni a capo Windows (CRLF)
for f in *.yml *.cfg hosts.ini; do
    if [ -f "$f" ]; then
        sed -i 's/\r$//' "$f" 2>/dev/null || true
    fi
done

if [ ! -f hosts.ini ]; then
    echo "[ERRORE] hosts.ini non trovato in $(pwd)."
    echo "   Esegui prima 'terraform apply' dalla cartella terraform/"
    exit 1
fi

SSH_KEY=$(grep 'ansible_ssh_private_key_file' hosts.ini | head -1 | sed 's/.*ansible_ssh_private_key_file=//' | awk '{print $1}' | tr -d '\r')
if [ -z "$SSH_KEY" ]; then
    SSH_KEY="../terraform/id_ed25519"
fi

if [ ! -f "$SSH_KEY" ]; then
    echo "[ERRORE] Chiave SSH non trovata: $SSH_KEY"
    echo "   Verifica che terraform apply abbia generato la chiave."
    exit 1
fi

SAFE_KEY="/tmp/glamdrop_ansible_key"
tr -d '\r' < "$SSH_KEY" > "$SAFE_KEY"
chmod 600 "$SAFE_KEY"

echo "  -> Inventario: $(pwd)/hosts.ini"
echo "  -> Chiave SSH: $SSH_KEY (copiata in $SAFE_KEY con permessi 0600)"

echo ""
echo "[3/4] Esecuzione playbook Ansible..."
echo ""

ANSIBLE_CONFIG=ansible.cfg ansible-playbook \
    -i hosts.ini \
    site.yml \
    --private-key "$SAFE_KEY" \
    -e "ansible_ssh_private_key_file=$SAFE_KEY" \
    -v

RC=$?


rm -f "$SAFE_KEY"

echo ""
if [ $RC -eq 0 ]; then
    echo "=========================================================="
    echo "[OK] Cluster Kubernetes configurato con successo via Ansible!"
    echo "=========================================================="
else
    echo "[ERRORE] Errore durante l'esecuzione del playbook (exit code: $RC)"
    exit $RC
fi

#!/bin/bash

set -e

echo "======================================"
echo " DevOps Server Bootstrap Starting"
echo "======================================"

# ---------------------------------------------------
# VARIABLES
# ---------------------------------------------------

DISK="/dev/nvme1n1"
MOUNT_POINT="/data"

DOCKER_DATA="$MOUNT_POINT/docker"
CONTAINERD_DATA="$MOUNT_POINT/containerd"

# ---------------------------------------------------
# UPDATE SYSTEM
# ---------------------------------------------------

echo "Updating packages..."

sudo apt update -y

# ---------------------------------------------------
# INSTALL JAVA
# ---------------------------------------------------

echo "Installing Java 17..."

sudo apt install openjdk-17-jdk -y

# ---------------------------------------------------
# INSTALL DOCKER
# ---------------------------------------------------

echo "Installing Docker..."

sudo apt install \
ca-certificates \
curl \
gnupg \
lsb-release \
apt-transport-https \
software-properties-common -y

# Docker GPG

sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Docker repo

echo \
"deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y

# Install Docker + Compose

sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# ---------------------------------------------------
# ENABLE SERVICES
# ---------------------------------------------------

sudo systemctl enable docker
sudo systemctl enable containerd

sudo systemctl start docker
sudo systemctl start containerd

# ---------------------------------------------------
# ADD USER TO DOCKER GROUP
# ---------------------------------------------------

sudo usermod -aG docker $USER

# ---------------------------------------------------
# EBS SETUP
# ---------------------------------------------------

echo "Formatting and mounting EBS disk..."

# Format only if not already formatted

if ! sudo blkid $DISK; then
    sudo mkfs.ext4 $DISK
fi

# Create mount point

sudo mkdir -p $MOUNT_POINT

# Mount disk

sudo mount $DISK $MOUNT_POINT

# ---------------------------------------------------
# FSTAB ENTRY
# ---------------------------------------------------

UUID=$(sudo blkid -s UUID -o value $DISK)

if ! grep -q "$UUID" /etc/fstab; then
    echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
fi

# ---------------------------------------------------
# STOP SERVICES
# ---------------------------------------------------

sudo systemctl stop docker || true
sudo systemctl stop containerd || true

# ---------------------------------------------------
# CREATE DIRECTORIES
# ---------------------------------------------------

sudo mkdir -p $DOCKER_DATA
sudo mkdir -p $CONTAINERD_DATA

# ---------------------------------------------------
# COPY EXISTING DATA
# ---------------------------------------------------

if [ -d "/var/lib/docker" ]; then
    sudo rsync -aP /var/lib/docker/ $DOCKER_DATA/
fi

if [ -d "/var/lib/containerd" ]; then
    sudo rsync -aP /var/lib/containerd/ $CONTAINERD_DATA/
fi

# ---------------------------------------------------
# BACKUP OLD DIRECTORIES
# ---------------------------------------------------

if [ -d "/var/lib/docker" ] && [ ! -d "/var/lib/docker.bak" ]; then
    sudo mv /var/lib/docker /var/lib/docker.bak
fi

if [ -d "/var/lib/containerd" ] && [ ! -d "/var/lib/containerd.bak" ]; then
    sudo mv /var/lib/containerd /var/lib/containerd.bak
fi

# ---------------------------------------------------
# CREATE NEW MOUNT TARGETS
# ---------------------------------------------------

sudo mkdir -p /var/lib/docker
sudo mkdir -p /var/lib/containerd

# ---------------------------------------------------
# BIND MOUNTS
# ---------------------------------------------------

sudo mount --bind $DOCKER_DATA /var/lib/docker
sudo mount --bind $CONTAINERD_DATA /var/lib/containerd

# ---------------------------------------------------
# PERSIST BIND MOUNTS
# ---------------------------------------------------

if ! grep -q "$DOCKER_DATA" /etc/fstab; then
    echo "$DOCKER_DATA /var/lib/docker none bind 0 0" | sudo tee -a /etc/fstab
fi

if ! grep -q "$CONTAINERD_DATA" /etc/fstab; then
    echo "$CONTAINERD_DATA /var/lib/containerd none bind 0 0" | sudo tee -a /etc/fstab
fi

# ---------------------------------------------------
# DOCKER CONFIG
# ---------------------------------------------------

sudo mkdir -p /etc/docker

cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "data-root": "/var/lib/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

# ---------------------------------------------------
# CONTAINERD CONFIG
# ---------------------------------------------------

sudo mkdir -p /etc/containerd

sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# ---------------------------------------------------
# START SERVICES
# ---------------------------------------------------

sudo systemctl daemon-reload

sudo systemctl restart containerd
sudo systemctl restart docker

# ---------------------------------------------------
# VERIFY
# ---------------------------------------------------

echo ""
echo "======================================"
echo " Installation Complete"
echo "======================================"

echo ""
echo "Java Version:"
java -version

echo ""
echo "Docker Version:"
docker --version

echo ""
echo "Docker Compose Version:"
docker compose version

echo ""
echo "Docker Root:"
docker info | grep "Docker Root Dir"

echo ""
echo "Disk Usage:"
df -h

echo ""
echo "Bind Mounts:"
mount | grep docker

echo ""
echo "Containerd Mount:"
mount | grep containerd

echo ""
echo "Test Container:"
docker run hello-world

echo ""
echo "======================================"
echo " SERVER READY"
echo "======================================"

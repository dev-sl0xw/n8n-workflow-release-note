#!/bin/bash
set -euo pipefail

# 1. 시스템 업데이트
dnf update -y

# 2. Swap 2GB 설정 (t2.micro 메모리 부족 대응)
dd if=/dev/zero of=/swapfile bs=128M count=16
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile swap swap defaults 0 0' >> /etc/fstab

# 3. Docker 설치 및 시작
dnf install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# 4. Docker Compose v2 설치 (바이너리 직접 다운로드)
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-linux-x86_64" -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# 5. n8n 작업 디렉토리 생성
mkdir -p /home/ec2-user/n8n-docker
cd /home/ec2-user/n8n-docker

# 6. .env 파일 생성
cat > .env << 'ENVEOF'
${env_content}
ENVEOF

# 7. docker-compose.yml 생성
cat > docker-compose.yml << 'COMPOSEEOF'
${compose_content}
COMPOSEEOF

# 8. 소유권 설정 및 n8n 실행
chown -R ec2-user:ec2-user /home/ec2-user/n8n-docker
docker compose up -d

# SOP: Claude Code 변경 로그 모니터 구축 및 운영

## 1. 개요

Claude Code의 [CHANGELOG.md](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)를 자동으로 모니터링하여 변경 사항이 감지되면 한국어로 번역된 HTML 이메일을 발송하는 n8n 워크플로우를 AWS Free Tier EC2에 셀프호스팅(Docker)으로 구축하는 절차서입니다.

## 2. 인프라 구성

### 2.1 전체 아키텍처

```
[AWS EC2 Free Tier (t2.micro)]
  └─ [Docker Engine]
       └─ [n8n Container]
            ├─ Schedule Trigger (12시간 간격)
            ├─ HTTP Request → GitHub CHANGELOG.md 가져오기
            ├─ Code → 변경 감지 (staticData diff)
            ├─ HTTP Request → Claude API 한국어 번역
            ├─ Code → HTML 이메일 생성
            └─ Send Email → SMTP 발송
```

### 2.2 사전 요구사항

| 항목 | 설명 | 비고 |
|------|------|------|
| AWS 계정 | Free Tier 사용 가능한 계정 | 가입 후 12개월간 무료 |
| Anthropic API 키 | Claude API 번역용 | [발급 링크](https://console.anthropic.com/settings/keys) |
| Gmail 앱 비밀번호 | SMTP 이메일 발송용 | [발급 링크](https://myaccount.google.com/apppasswords) |
| SSH 키 페어 | EC2 접속용 | AWS Console에서 생성 |

## 3. AWS EC2 인스턴스 설정

### 3.1 EC2 인스턴스 생성

1. [AWS Console](https://console.aws.amazon.com/ec2/)에 로그인
2. **Launch Instance** 클릭
3. 다음과 같이 설정:

| 설정 항목 | 값 |
|-----------|-----|
| Name | `n8n-server` |
| AMI | Amazon Linux 2023 AMI (Free Tier eligible) |
| Instance Type | `t2.micro` (Free Tier - 1 vCPU, 1GB RAM) |
| Key Pair | 기존 키 선택 또는 새로 생성 |
| Storage | 30GB gp3 (Free Tier 최대) |

### 3.2 보안 그룹(Security Group) 설정

| 타입 | 프로토콜 | 포트 | 소스 | 용도 |
|------|---------|------|------|------|
| SSH | TCP | 22 | My IP | SSH 접속 |
| Custom TCP | TCP | 5678 | My IP | n8n 웹 UI 접속 |

> **보안 권고**: 5678 포트는 반드시 `My IP`로 제한하세요. 프로덕션 환경에서는 리버스 프록시(Nginx) + HTTPS 구성을 강력히 권장합니다.

### 3.3 Elastic IP 할당 (필수)

EC2 인스턴스를 중지/재시작하면 Public IP가 변경됩니다. 고정 IP를 위해 Elastic IP를 할당합니다.

1. AWS Console > **EC2** > **Elastic IPs**
2. **Allocate Elastic IP address** 클릭
3. **Allocate** 확인
4. 생성된 Elastic IP 선택 > **Actions** > **Associate Elastic IP address**
5. Instance에서 `n8n-server` 선택 후 **Associate**

> **비용**: Elastic IP는 실행 중인 EC2 인스턴스에 연결되어 있으면 **무료**입니다. 연결 없이 보유만 하면 과금됩니다.

이후 본 문서에서 `<EC2_ELASTIC_IP>`는 할당받은 Elastic IP를 의미합니다.

### 3.4 EC2 접속

```bash
chmod 400 your-key.pem
ssh -i your-key.pem ec2-user@<EC2_ELASTIC_IP>
```

**체크포인트**: SSH 접속이 성공하면 다음 단계로 진행합니다.

## 4. 서버 초기 설정

### 4.1 시스템 업데이트

```bash
sudo dnf update -y
```

### 4.2 Swap 메모리 설정 (t2.micro 필수)

t2.micro는 RAM이 1GB뿐이므로 n8n 컨테이너 안정 운영을 위해 **반드시** Swap을 먼저 설정합니다.

```bash
# 2GB Swap 파일 생성
sudo dd if=/dev/zero of=/swapfile bs=128M count=16
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 재부팅 후에도 Swap 유지
echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab

# Swap 적용 확인
free -h
```

**체크포인트**: `free -h` 출력에서 Swap 행에 약 2.0G가 표시되어야 합니다.

## 5. Docker 설치 (Amazon Linux 2023)

### 5.1 Docker 설치 및 시작

```bash
# Docker 설치
sudo dnf install -y docker

# Docker 서비스 시작 및 부팅 시 자동 시작
sudo systemctl start docker
sudo systemctl enable docker

# ec2-user를 docker 그룹에 추가 (sudo 없이 docker 사용)
sudo usermod -aG docker ec2-user
```

> **중요**: 그룹 변경을 적용하려면 SSH 세션을 **종료 후 재접속**해야 합니다.

```bash
# SSH 세션 종료
exit

# 재접속
ssh -i your-key.pem ec2-user@<EC2_ELASTIC_IP>
```

### 5.2 Docker Compose 설치

```bash
sudo dnf install -y docker-compose-plugin
```

### 5.3 설치 확인

```bash
docker --version
docker compose version
docker run hello-world
```

**체크포인트**: `docker run hello-world`가 `Hello from Docker!` 메시지를 출력하면 성공입니다.

## 6. n8n 컨테이너 배포

### 6.1 작업 디렉토리 생성

```bash
mkdir -p ~/n8n-docker
cd ~/n8n-docker
```

### 6.2 환경변수 파일 작성 (.env)

민감한 정보를 docker-compose.yml에 직접 넣지 않고 `.env` 파일로 분리합니다.

```bash
cat > .env << 'EOF'
# n8n 설정
N8N_HOST=<EC2_ELASTIC_IP>
N8N_PROTOCOL=http
N8N_PORT=5678
GENERIC_TIMEZONE=Asia/Seoul
TZ=Asia/Seoul
EOF
```

> **보안**: `.env` 파일에는 민감한 정보가 포함될 수 있으므로 git에 커밋하지 마세요. `<EC2_ELASTIC_IP>`를 실제 Elastic IP로 변경하세요.

### 6.3 Docker Compose 파일 작성

```bash
cat > docker-compose.yml << 'EOF'
services:
  n8n:
    image: n8nio/n8n
    container_name: n8n
    restart: always
    ports:
      - "5678:5678"
    env_file:
      - .env
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:
EOF
```

### 6.4 n8n 컨테이너 실행

```bash
docker compose up -d

# 상태 확인
docker compose ps

# 로그 확인 (Ctrl+C로 종료)
docker compose logs -f n8n
```

### 6.5 접속 및 초기 계정 설정

1. 브라우저에서 `http://<EC2_ELASTIC_IP>:5678` 접속
2. **최초 접속 시 Owner 계정 생성 화면**이 표시됨
3. 이메일, 이름, 비밀번호를 입력하여 관리자 계정 생성
4. 이 계정이 n8n 인스턴스의 Owner가 됨

> **중요**: Owner 계정은 n8n의 내장 인증 시스템입니다. 반드시 강력한 비밀번호를 설정하세요.

**체크포인트**: n8n 대시보드가 정상적으로 표시되면 성공입니다.

## 7. 워크플로우 배포

### 7.1 워크플로우 파일을 EC2로 전송

로컬 PC에서 워크플로우 JSON 파일을 EC2로 전송합니다.

```bash
# 로컬 PC에서 실행
scp -i your-key.pem workflows/changelog-monitor.json \
  ec2-user@<EC2_ELASTIC_IP>:~/changelog-monitor.json
```

또는 n8n UI에서 직접 가져오기를 사용할 수도 있습니다.

### 7.2 워크플로우 가져오기

1. n8n 웹 UI 접속
2. 좌측 메뉴에서 **Workflows** 클릭
3. 우측 상단 `...` 메뉴 > **Import from File** 선택
4. `changelog-monitor.json` 파일 업로드

### 7.3 Credential 설정

#### SMTP (Gmail)

1. **Credentials** > **Add Credential** > **SMTP** 선택
2. 아래와 같이 설정:

| 항목 | 값 |
|------|-----|
| Host | `smtp.gmail.com` |
| Port | `465` |
| User | 본인 Gmail 주소 |
| Password | [Gmail 앱 비밀번호](https://myaccount.google.com/apppasswords) |
| SSL/TLS | 활성화 |

#### Anthropic API (번역용)

1. **Credentials** > **Add Credential** > **Header Auth** 선택
2. 아래와 같이 설정:

| 항목 | 값 |
|------|-----|
| Name | `x-api-key` |
| Value | [Anthropic API 키](https://console.anthropic.com/settings/keys) |

### 7.4 워크플로우 활성화

1. 워크플로우를 열고 우측 상단 토글을 **Active**로 변경
2. 처음 실행 시 현재 CHANGELOG 내용을 저장하고 이메일은 발송하지 않음
3. 이후 12시간 간격으로 변경 감지 시 자동 이메일 발송

**체크포인트**: 워크플로우를 수동 실행(Test Workflow)하여 에러 없이 완료되는지 확인합니다.

## 8. 워크플로우 노드 구성

| 순서 | 노드 | 역할 |
|------|------|------|
| 1 | Schedule Trigger | 12시간마다 실행 |
| 2 | HTTP Request | GitHub에서 CHANGELOG.md 원본 가져오기 |
| 3 | Code (변경 감지) | staticData로 이전 내용과 비교, 버전별 diff 분류 |
| 4 | HTTP Request (번역) | Claude API로 변경 내용 한국어 번역 |
| 5 | Code (HTML 생성) | 차이점을 빨강/초록 HTML 이메일로 생성 |
| 6 | Send Email | SMTP로 이메일 발송 |

## 9. 이메일 출력 형식

| 색상 | 의미 |
|------|------|
| 초록색 블록 | 새로 추가된 버전/내용 |
| 빨간색 블록 | 삭제되거나 변경 전 내용 (취소선) |
| 보라색 헤더 | 변경된 버전 표시 |
| 번역 섹션 | Claude API로 번역된 한국어 내용 |

## 10. 운영 및 유지보수

### 10.1 n8n 컨테이너 관리

```bash
cd ~/n8n-docker

# 상태 확인
docker compose ps

# 로그 확인
docker compose logs -f n8n

# 재시작
docker compose restart n8n

# 중지
docker compose down

# n8n 업데이트
docker compose pull && docker compose up -d
```

### 10.2 데이터 백업

#### 수동 백업

```bash
# n8n 데이터 볼륨 백업 (~/n8n-docker 디렉토리에서 실행)
docker run --rm \
  -v n8n-docker_n8n_data:/data \
  -v ~/n8n-backups:/backup \
  alpine tar czf /backup/n8n-backup-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .
```

#### 자동 백업 (cron)

```bash
# 백업 디렉토리 생성
mkdir -p ~/n8n-backups

# 매일 새벽 3시 자동 백업 설정
(crontab -l 2>/dev/null; echo '0 3 * * * docker run --rm -v n8n-docker_n8n_data:/data -v ~/n8n-backups:/backup alpine tar czf /backup/n8n-backup-$(date +\%Y\%m\%d).tar.gz -C /data .') | crontab -

# 14일 이상 된 백업 자동 삭제
(crontab -l 2>/dev/null; echo '30 3 * * * find ~/n8n-backups -name "n8n-backup-*.tar.gz" -mtime +14 -delete') | crontab -
```

#### 백업 복원

```bash
# n8n 컨테이너 중지
cd ~/n8n-docker
docker compose down

# 기존 데이터 볼륨 삭제 후 복원
docker volume rm n8n-docker_n8n_data
docker volume create n8n-docker_n8n_data
docker run --rm \
  -v n8n-docker_n8n_data:/data \
  -v ~/n8n-backups:/backup \
  alpine tar xzf /backup/<BACKUP_FILE_NAME>.tar.gz -C /data

# n8n 재시작
docker compose up -d
```

### 10.3 디스크 관리

```bash
# 디스크 사용량 확인
df -h

# Docker 불필요한 이미지/캐시 정리
docker system prune -f

# n8n 로그 크기 확인
docker compose logs --no-log-prefix n8n 2>/dev/null | wc -c
```

### 10.4 AWS Free Tier 주의사항

| 항목 | Free Tier 한도 | 비고 |
|------|---------------|------|
| EC2 | t2.micro 750시간/월 | 1개 인스턴스 24시간 가동 시 약 720시간 |
| EBS | 30GB gp2/gp3 | 스토리지 초과 주의 |
| Elastic IP | 실행 중 인스턴스 연결 시 무료 | 미연결 시 시간당 과금 |
| 데이터 전송 | 100GB/월 아웃바운드 | 이메일 발송량에 따라 확인 |
| 기간 | **가입 후 12개월** | 12개월 이후 과금 발생 |

> **필수**: AWS Billing 콘솔 > **Budgets**에서 월 $0 예산 알림을 설정하여 예상치 못한 과금을 방지하세요.

## 11. 트러블슈팅

| 증상 | 원인 | 해결 방법 |
|------|------|-----------|
| EC2 SSH 접속 불가 | 보안 그룹 또는 키 페어 문제 | 보안 그룹에서 22 포트가 My IP에 오픈되었는지 확인. 키 파일 권한 `chmod 400` 확인 |
| n8n UI 접속 불가 | 보안 그룹 미설정 | 보안 그룹에서 5678 포트 오픈 확인. `docker compose ps`로 컨테이너 상태 확인 |
| 컨테이너 재시작 반복 | 메모리 부족 (OOM Kill) | `dmesg \| grep -i oom`으로 확인. 섹션 4.2의 Swap 설정 적용 |
| n8n 재시작 후 IP 변경 | Elastic IP 미설정 | 섹션 3.3의 Elastic IP 할당 절차 수행 |
| 이메일 발송 실패 | Gmail 앱 비밀번호 오류 | 앱 비밀번호 재생성 및 Credential 재설정. [보안 설정](https://myaccount.google.com/apppasswords) 확인 |
| 번역 실패 | Anthropic API 키 오류/잔액 부족 | API 키 유효성 및 크레딧 잔액 확인 |
| Docker 명령어 권한 오류 | docker 그룹 미적용 | `sudo usermod -aG docker ec2-user` 후 SSH 재접속 |

## 12. 체크리스트 요약

작업 완료 후 아래 항목을 순서대로 확인합니다.

- [ ] EC2 인스턴스 생성 및 보안 그룹 설정 완료
- [ ] Elastic IP 할당 및 인스턴스 연결 완료
- [ ] SSH 접속 성공
- [ ] Swap 메모리 설정 완료 (free -h로 확인)
- [ ] Docker 및 Docker Compose 설치 완료
- [ ] n8n 컨테이너 실행 및 웹 UI 접속 성공
- [ ] Owner 계정 생성 완료
- [ ] 워크플로우 JSON 가져오기 완료
- [ ] SMTP Credential 설정 완료
- [ ] Anthropic API Credential 설정 완료
- [ ] 워크플로우 수동 테스트 성공
- [ ] 워크플로우 Active 토글 활성화
- [ ] 자동 백업 cron 설정 완료
- [ ] AWS Billing 알림 설정 완료

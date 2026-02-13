# Claude Code 변경 로그 모니터

Claude Code의 [CHANGELOG.md](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)를 자동으로 모니터링하여 변경 사항이 감지되면 한국어로 번역된 HTML 이메일을 발송하는 n8n 워크플로우입니다.

## 주요 기능

- 12시간 간격으로 CHANGELOG.md 변경 감지
- 새 버전은 초록색, 삭제/변경 전 내용은 빨간색으로 시각적 구분
- Claude API를 활용한 한국어 자동 번역
- 깔끔한 HTML 이메일 포맷

## 아키텍처

```
[Schedule Trigger] → [Fetch CHANGELOG] → [Detect Changes] → [Translate] → [Generate HTML] → [Send Email]
```

### 노드 구성

1. **Schedule Trigger** - 12시간마다 실행
2. **HTTP Request** - GitHub에서 CHANGELOG.md 원본 가져오기
3. **Code (변경 감지)** - staticData로 이전 내용과 비교, 버전별 diff 분류
4. **HTTP Request (번역)** - Claude API로 변경 내용 한국어 번역
5. **Code (HTML 생성)** - 차이점을 빨강/초록 HTML 이메일로 생성
6. **Send Email** - SMTP로 이메일 발송

## 설치 방법

### 사전 요구사항

- n8n 인스턴스 (셀프호스팅 또는 n8n Cloud)
- Anthropic API 키 (번역용)
- Gmail 앱 비밀번호 (이메일 발송용)

### 워크플로우 가져오기

1. n8n 에디터에서 `...` 메뉴 > `Import from File` 선택
2. `workflows/changelog-monitor.json` 파일 업로드
3. 아래 Credential 설정 진행

### Credential 설정

#### SMTP (Gmail)

1. n8n에서 Credentials > New > SMTP 선택
2. Host: `smtp.gmail.com`
3. Port: `465`
4. User: 본인 Gmail 주소
5. Password: [Gmail 앱 비밀번호](https://myaccount.google.com/apppasswords)
6. SSL/TLS: 활성화

#### Anthropic API

1. n8n에서 Credentials > New > Header Auth 선택
2. Name: `x-api-key`
3. Value: [Anthropic API 키](https://console.anthropic.com/settings/keys)

### 활성화

1. 워크플로우를 열고 우측 상단 토글을 Active로 변경
2. 처음 실행 시 현재 내용을 저장하고 이메일은 발송하지 않음
3. 이후 변경 감지 시 자동 이메일 발송

## 이메일 형식

- **초록색 블록**: 새로 추가된 버전/내용
- **빨간색 블록**: 삭제되거나 변경 전 내용 (취소선)
- **보라색 헤더**: 변경된 버전 표시
- **번역 섹션**: Claude API로 번역된 한국어 내용

## 라이선스

MIT

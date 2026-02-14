# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

n8n workflow that monitors the [Claude Code CHANGELOG.md](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) every 12 hours, detects changes via version-level diff, translates them to Korean using the Claude API, and sends an HTML email with color-coded additions (green) and removals (red).

## Repository Structure

- `workflows/changelog-monitor-v3.json` — **현재 활성 워크플로우** (import into n8n via UI)
- `workflows/changelog-monitor-v2.json` — v2 레거시 (참조용, v3로 대체됨)
- `workflows/changelog-monitor.json` — v1 레거시 (참조용, v2로 대체됨)
- `docs/sop.md` — Full deployment SOP for AWS EC2 Free Tier + Docker self-hosting
- `infra/` — Terraform IaC로 AWS EC2 + n8n 자동 배포 (`terraform apply` 한 번으로 완료)
- `.mcp.json` — n8n-mcp server config for node/template reference during development

## Workflow Architecture

```
Schedule Trigger (12h) → Fetch CHANGELOG (HTTP) → Detect Changes (Code/staticData)
  → Translate to Korean (Claude API via HTTP) → Generate HTML Email (Code) → Send Email (SMTP)
```

### v3 주요 개선사항 (v2 대비)
- `neverError: true` — Fetch CHANGELOG HTTP 에러(404, 500 등)도 throw 없이 Detect Changes에서 status code 검증
- HTTP status code 검증 — `statusCode !== 200`이면 `return []`로 안전하게 flow 중단
- `<meta charset="UTF-8">` — HTML 이메일에 charset 명시로 한국어 렌더링 보장
- `<!DOCTYPE html>` + `<html lang="ko">` — 표준 HTML5 구조
- n8n MCP `validate_workflow` / `validate_node`으로 전체 설정 검증 완료

### v2 주요 개선사항
- `onError: continueRegularOutput` — 번역 API 실패 시에도 영문 원본으로 이메일 발송 (graceful degradation)
- HTTP 요청 타임아웃 설정: Fetch 30s, Translation 60s
- 각 노드에 `notesInFlow: true` 문서화
- 입력 데이터 유효성 검사 (`if (!input || !input.json)` guard)

### Key Design Decisions
- **Change detection**: `$getWorkflowStaticData('global')`로 이전 CHANGELOG 내용과 ETag를 실행 간 유지
- **첫 실행 동작**: baseline 저장만 수행, 이메일 미발송 (`return []`로 flow 중단 → false positive 방지)
- **ETag 최적화**: GitHub ETag 헤더 비교로 변경 없음 시 빠른 종료
- **Translation**: raw HTTP Request to `api.anthropic.com/v1/messages` + Header Auth (`x-api-key`), not built-in LangChain nodes
- **모델 버전 고정**: `claude-sonnet-4-5-20250929`
- **버전 감지 정규식**: `/^## (\d+\.\d+\.\d+.*)/gm`
- **색상 코딩**: green(추가), red(삭제), purple(변경)
- **HTML email**: Code node에서 inline 생성 (별도 템플릿 파일 없음)

## Working with the Workflow JSON

This project has no build, lint, or test commands. The workflow is a single JSON file edited either:
1. **In the n8n editor UI** — preferred for visual node editing and testing
2. **Directly in JSON** — for bulk changes; use the n8n-mcp tools (`search_nodes`, `get_node`, `validate_node`, `validate_workflow`) to verify correctness

To validate the workflow structure without deploying:
```
Use mcp__n8n-mcp__validate_workflow with the full JSON from workflows/changelog-monitor-v2.json
```

## Credentials Required (configured in n8n, not in repo)

- **Gmail OAuth2** (`Gmail OAuth2`): Google Cloud Console에서 OAuth2 Client ID/Secret 발급 후 n8n에서 연결
- **Header Auth** (`Anthropic API Key`): `x-api-key` header with Anthropic API key

## Deployment

Target: AWS EC2 Free Tier (`t2.micro`) running n8n via Docker.

- **수동 배포**: `docs/sop.md` 참조
- **Terraform 자동 배포**:
  ```bash
  cd infra
  cp terraform.tfvars.example terraform.tfvars  # 변수 편집
  terraform init
  terraform plan
  terraform apply
  ```
  배포 후 `n8n_url` output으로 웹 UI 접속 → Owner 계정 생성 → Credentials 설정 → 워크플로우 Import

## Language

All documentation, commit messages, and user-facing content should be in **Korean**. Technical terms (API, CLI, SDK, node names) remain in English.

## Git Workflow

- `main` — stable/production branch
- `dev` — active development branch

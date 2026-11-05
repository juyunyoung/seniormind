# backend — Cloud Run API (seniormind-api)

Java 21, Spring Boot 3.5, Gradle. 기능 명세의 원본은 팀 저장소 `memory_capsule_backend_spec_v0.4.md`(v0.4.3)입니다.
지역 `asia-northeast3`(서울), Firestore는 같은 프로젝트(`../db`).

## 실행

```bash
./gradlew test          # 규칙 테스트 21개(판단 해석·등급·빈도·안전 문구·억제 창·반복 규칙·푸시·스프링 구성)
./scripts/deploy.sh     # Cloud Run 배포. 끝나면 iOS에 넣을 주소를 알려 준다
```
- 배포 전에 `../db/scripts/setup_gcp.sh`(Firestore·인덱스)를 한 번 실행합니다.
- OpenAI 키가 없으면 `/api/session`·`/api/decision`은 503 `upstream_unavailable`을 돌려주고 나머지 API는 동작합니다. 키는 `../db/scripts/set_openai_key.sh`로 넣습니다.
- 로컬 실행에는 Google 자격 증명이 필요합니다(`gcloud auth application-default login`). 로컬에서만 `DEV_AUTH_BYPASS=true`면 `X-Debug-Uid` 헤더로 로그인 없이 시험할 수 있고, Cloud Run에서는 이 우회가 항상 꺼집니다.

## API (P1·P2 중 iOS 1차 화면에 필요한 것)

| API | 상태 | 비고 |
|---|---|---|
| `POST/GET /users/me`, `POST /devices`, `POST/GET /consents` | 구현 | 역할은 최초 1회, 알림 설정은 부분 병합 |
| `GET /config/latest` | 구현 | Firestore 활성 설정, 없으면 내장 기본값(`db/seed`와 같은 파일). 서명은 P2 |
| `POST /api/session` | 구현 | 동의·일일 상한·앱 최소 버전 확인 → OpenAI Live → SDP answer |
| `POST /api/decision` | 구현 | 아래 "판단" 참고 |
| `POST /sessions/{id}/end` | 구현(저장까지) | 전체 자막 저장(256KB), 비용 계산. 카드 추출은 P2라 `extraction_status=pending`(동의 없으면 `skipped`) |
| `POST /memories/control` | 구현(`last_utterance`) | DELETE: 판단·자막 삭제 + 기준선 재계산 표시. DO_NOT_REMEMBER: 추출 제외 목록 |
| `POST /pairing/code`, `POST /guardian/link`, `GET /guardian/links`, `DELETE /guardian/link/{id}` | 구현 | QR 5분, 연결 시 어르신 기기로 `pairing_done` |
| `GET/POST/PUT/DELETE /schedules`, `POST /schedules/{id}/ack` | 구현 | 투약만, 반복 규칙 공통 부분집합, 늦은·중복 ack 규칙, `needs_ack=false` 무시 |
| `GET /guardian/board/{senior_id}` | 구현 | 기준선 배치 전에는 최근 7일 판단으로 감정 4단계·강도만 계산 |
| `GET /guardian/alerts`, `GET/PATCH …/{id}`, `…/read`, `…/follow-up` | 구현 | |
| `POST /recall`, 카드 추출·임베딩 | P2 | |
| 배치(기준선·추세, 일정 미확인, 자막 7일 만료, 추출 재시도, R3 미확인 재발송, 방해 금지 시간 뒤 재발송) | P2 | Cloud Scheduler → 내부 API |

## 판단 `/api/decision`

- **중간 판단**(`final=false`): 반응 질문 하나만 보내 비용을 줄입니다. 저장하지 않고, 응답은 `risk_level=R0`, `assessment_status=reaction_only`. 세션당 동시 1건·950ms 간격(429).
- **최종 판단**(`final=true`): Q00~Q10 + `p_r3` 전체 질문 → 선택지 검증 → 등급(`p_r3≥0.30` R3, 영역 점수 0.60/0.35) → 7일 빈도 규칙 → 안전 문구 선택 → `assessments` 저장 → R2 이상이면 보호자 알림.
  - 같은 `(session_id, utterance_id)` 재전송은 저장된 결과를 그대로 돌려줍니다(OpenAI 재호출 없음).
  - Q01·Q02·`p_r3`가 없거나 Q02 확률이 없으면 1회 재시도 후 `needs_review`, `risk_level=unknown`. R0로 처리하지 않습니다.
  - R2·R3면 `reaction=empathy`, `safety_override=true`.
- 회신 전 임시 규칙: 반응 6종, Q10은 `same_intent_question`만, 선호 주제 AND(`docs/TODO.md` T6).

## 팀 문서와 다르게 한 것(1인 개발 단순화)

- **Pub/Sub·Cloud Functions 없음:** 보호자 알림을 판단 요청 안에서 바로 처리합니다. Cloud Run은 응답 뒤 CPU를 줄이므로 백그라운드 처리 대신 동기 처리했습니다. 알림 실패는 판단 응답에 영향을 주지 않습니다.
- **판단 실패 사람 검토 화면 없음:** `needs_review`는 저장만 합니다.

## 실제 OpenAI로 확인할 것(백엔드 5장)

`OpenAiClient`·`DecisionQuestions`·`DecisionParser`는 PoC 형식(`choice` 질문, `answers[].choice`) 기준입니다. 실제 키로 처음 호출할 때 아래만 맞추면 됩니다.
- 복수 선택 질문 표기(`"multiple": true`로 가정), `predicate`·`score` 질문 형식
- 선택지별 확률 필드 이름(`choices[].probability`, `probabilities{}` 모두 받음)
- `delegation.type`, 안전 문구 주입 이벤트(`session.commentary.append`)

## PC·스크립트 호출 막기

1. **Firebase ID 토큰(적용):** 모든 API가 검증합니다(`/health`만 예외).
2. **App Check(적용, 지금은 기록만):** `X-Firebase-AppCheck` 토큰을 공개키로 검증합니다(`AppCheckVerifier`). `APP_CHECK_MODE=log`는 실패를 기록만 하고, 유료 Apple 계정 전환 후 `enforce`로 바꾸면 실패 요청을 401로 막습니다.
3. **사용자별 호출 제한(적용):** UID당 분당 120회, 일일 대화 상한.

`User-Agent`·`X-Client-Platform` 검사는 쉽게 위조되므로 차단 수단으로 쓰지 않습니다.

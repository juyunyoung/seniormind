# backend — Cloud Run API (아직 코드 없음)

iOS 목 모드로 화면 흐름을 끝낸 다음 시작합니다. 기능 명세의 원본은 팀 저장소의 `memory_capsule_backend_spec_v0.4.md`(v0.4.3)입니다.

## 정해진 것

| 항목 | 값 |
|---|---|
| 언어·빌드 | Java 21, Spring Boot 3, Gradle |
| 실행 | Cloud Run `seniormind-api`, 지역 `asia-northeast3`(서울) |
| 호출 허용 | 공개 호출(`--allow-unauthenticated`) + 서버 코드에서 Firebase ID 토큰 검증 |
| 최소 인스턴스 | 0으로 시작, 데모 직전 1 |
| 비밀 | `OPENAI_API_KEY`는 Secret Manager `openai-api-key` |
| DB | 같은 프로젝트 Firestore(`../db`) |
| 첫 목표 | `POST /api/session` → iOS 실제 대화 연결 |

## 배포(처음에는 로컬에서)

```bash
gcloud run deploy seniormind-api --source . --region asia-northeast3 \
  --allow-unauthenticated --min-instances 0 \
  --set-secrets OPENAI_API_KEY=openai-api-key:latest \
  --set-env-vars APP_CHECK_MODE=log
```
안정되면 GitHub 연동 자동 배포로 바꿉니다.

## PC·스크립트 호출 막기 검토

공개 호출이라 주소만 알면 누구나 요청을 보낼 수 있습니다. 막는 방법은 세 겹입니다.

1. **Firebase ID 토큰(필수, 처음부터):** 앱에서 로그인한 사용자만 통과합니다. 다만 토큰은 PC에서도 만들 수 있어 이것만으로는 "앱에서 온 요청"인지 알 수 없습니다.
2. **Firebase App Check(핵심):** 요청 헤더 `X-Firebase-AppCheck`에 Apple이 증명한 "진짜 기기의 진짜 앱" 토큰이 붙습니다. PC·스크립트는 이 토큰을 만들 수 없습니다. iOS 앱에는 이미 넣어 두었습니다(`app/ios/SeniorMind/Core/AppCheckService.swift`).
   - 서버 검증: 토큰(JWT)을 `https://firebaseappcheck.googleapis.com/v1/jwks` 공개키로 검증하고, `iss`가 `https://firebaseappcheck.googleapis.com/<프로젝트 번호>`, `aud`에 `projects/<프로젝트 번호>`가 있는지 확인합니다. Spring의 필터 하나로 구현합니다.
   - 단계: 무료 Apple 계정 기간에는 App Attest를 못 쓰므로 `APP_CHECK_MODE=log`(검증 결과만 기록). 유료 전환 후 `enforce`(실패 시 401).
3. **사용자별 호출 제한:** UID당 분당 요청 수 제한과 일일 세션 상한(`daily_limit`)으로 남용 비용을 막습니다.

`User-Agent`나 `X-Client-Platform` 헤더 검사는 쉽게 위조되므로 차단 수단으로 쓰지 않습니다.

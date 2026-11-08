# db — Firestore (seniormind-513700, 서울)

필드 정의의 원본은 팀 저장소의 `memory_capsule_db_spec_v0.3.md`(v0.3.2)입니다. 이 폴더에는 실제로 배포하는 파일만 둡니다.

| 파일 | 내용 |
|---|---|
| `firestore.rules` | 앱의 직접 접근을 모두 막는 규칙. 서버(Admin SDK)만 읽고 씁니다. |
| `firestore.indexes.json` | 서버 조회용 복합 인덱스 + 기억 카드 벡터 인덱스(1024차원). 긴 원문 필드는 색인 제외. |
| `seed/config_versions.*.json` | 앱·서버 공통 설정 1건(임계값, 안전 문구, 일정 기본값 등). `numbers_verified_at`이 비어 있으면 배포 금지. |
| `scripts/setup_gcp.sh` | API 켜기, Firestore 생성(Native, 서울), 규칙·인덱스 배포, OpenAI 키 자리 생성 |
| `scripts/set_openai_key.sh` | OpenAI 키를 Secret Manager에 넣기(실서버 연결 때) |
| `scripts/seed_config.py` | 설정 문서를 Firestore에 넣고 활성화 |

## 1. 처음 한 번

1. Firebase 콘솔 → 프로젝트 추가 → **기존 Google Cloud 프로젝트 `seniormind-513700`** 선택.
2. Mac 터미널에서:
   ```bash
   gcloud auth login
   npm i -g firebase-tools && firebase login
   ./db/scripts/setup_gcp.sh
   ```
3. 설정 넣기:
   ```bash
   pip install google-cloud-firestore
   gcloud auth application-default login
   python db/scripts/seed_config.py db/seed/config_versions.2026.11.04-1.json
   ```

## 2. 컬렉션 16종

`users`, `devices`, `consents/{uid}/items`, `guardians`, `pairing_codes`, `sessions`, `transcripts/{sid}/parts`, `assessments`, `baselines`, `memory_cards`, `card_mentions`, `card_tombstones`, `alerts`, `schedules`, `schedule_logs`, `config_versions`

## 3. Firebase 콘솔에서 할 일

- 프로젝트 설정 → 앱 추가 → iOS, 번들 ID `com.daljoalab.seniormind` → `GoogleService-Info.plist`를 받아 `app/ios/MemoryCapsule/Firebase/GoogleService-Info-seniormind.plist`로 둡니다(`app/ios/scripts/switch_backend.sh seniormind --plist <파일>`). 저장소에는 올리지 않습니다.
- Authentication → 로그인 방법: 익명, 이메일/비밀번호, Google 켜기. Apple은 유료 계정 전환 후.
- App Check → iOS 앱에 디버그 토큰 등록(무료 계정 기간). 유료 전환 후 App Attest 등록.

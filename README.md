# seniormind — 기억의 캡슐 개발 저장소

AI 말벗 "기억이"와 대화하며 이야기를 기억 카드로 남기고, 보호자가 안부·투약 알림을 함께 챙기는 앱의 코드 저장소입니다.
기능 명세·결정 기록은 팀 저장소 [try-hackathon-study/memory-capsule](https://github.com/try-hackathon-study/memory-capsule)에 있습니다.

| 폴더 | 내용 | 상태 |
|---|---|---|
| `app/ios` | iOS 앱(SwiftUI, iOS 26+), 번들 ID `com.daljoalab.seniormind` | 1차 시니어 화면, 목 모드 |
| `app/android` | Android 앱 | 예정 |
| `backend` | Cloud Run API(Java 21, Spring Boot 3.5) | iOS 1차 화면용 API 구현, 테스트 21개. 카드 추출·회상·배치는 P2 |
| `db` | Firestore 규칙·인덱스·설정·설정 스크립트(서울) | 작성 |
| `docs/TODO.md` | 나중에 할 일 | |

참고하는 팀 문서: 앱 계획서 `memory_capsule_app_spec_v0.3.md`(v0.3.3), 백엔드 `memory_capsule_backend_spec_v0.4.md`(v0.4.3), DB `memory_capsule_db_spec_v0.3.md`(v0.3.2), iOS 대응표 `memory_capsule_ios_mapping_v0.2.md`, 데이터 명세 `memory_capsule_backend_spec_v0_6.xlsx`.

## 원칙

- OpenAI API 키는 서버(Secret Manager)에만 둡니다. 앱·저장소·채팅에 남기지 않습니다.
- `GoogleService-Info.plist`, Apple 팀 ID(`Config/Local.xcconfig`)는 올리지 않습니다.
- `main`은 PR로만 병합합니다.

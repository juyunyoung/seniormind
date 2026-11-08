# 기억의 캡슐 iOS 앱 (seniormind 저장소)

SwiftUI, iOS 26 이상, 홈 화면 이름 "기억의 캡슐". 어르신 모드와 보호자 모드를 한 앱에 담았습니다.
팀 저장소 `try-hackathon-study/memory-capsule`의 `ios/`(브랜치 `feature/ios`)와 같은 소스이고, 이 저장소에서는 **내 백엔드(`backend/`, GCP `seniormind-513700`)에 연결하는 것이 기본**입니다.

| `MC_BACKEND` | 서버 | 번들 ID | Firebase plist(저장소에 올리지 않음) |
|---|---|---|---|
| `seniormind` (기본) | 내 백엔드, GCP·Firebase `seniormind-513700` | `com.daljoalab.seniormind` | `MemoryCapsule/Firebase/GoogleService-Info-seniormind.plist` |
| `team` | 이현님 팀 서버, GCP·Firebase `memory-capsule-511111` | `com.daljoalab.memorycapsule` | `MemoryCapsule/Firebase/GoogleService-Info-team.plist` |

## 실행 (Mac)

```bash
brew install xcodegen
cp "$HOME/seniormind/app/ios/Config/Local.xcconfig.example" "$HOME/seniormind/app/ios/Config/Local.xcconfig"
cd "$HOME/seniormind/app/ios" && xcodegen generate && open "$HOME/seniormind/app/ios/MemoryCapsule.xcodeproj"
```
- 무료 Apple 계정이면 `MC_DEVELOPMENT_TEAM`에 Personal Team ID를 넣거나, Xcode Signing에서 팀을 고릅니다.
- 서버 없이 화면만 볼 때는 `Local.xcconfig`에서 `MC_USE_MOCK = YES`.
- 패키지(WebRTC, Firebase) 오류가 나면 File → Packages → Reset Package Caches.

## 백엔드 바꾸기

`Config/Local.xcconfig`의 **`MC_BACKEND`** 값에 따라 서버 주소·번들 ID·Firebase 설정 파일이 함께 바뀝니다. 기본은 `seniormind`(내 백엔드). 값은 위 표와 같습니다.

스크립트가 `Local.xcconfig` 수정·plist 확인·`xcodegen generate`·설정 확인까지 한 번에 합니다.
```bash
"$HOME/seniormind/app/ios/scripts/switch_backend.sh" seniormind --plist "$HOME/Downloads/GoogleService-Info.plist"   # 처음 한 번(내 plist 넣기)
"$HOME/seniormind/app/ios/scripts/switch_backend.sh" seniormind   # 내 백엔드(기본)
"$HOME/seniormind/app/ios/scripts/switch_backend.sh" team    # 이현님 팀 서버(처음 한 번 --plist 필요)
"$HOME/seniormind/app/ios/scripts/switch_backend.sh" mock    # 서버 없이 화면만
```
- 다른 백엔드(개인 테스트 서버 등)는 이름을 정해 처음 한 번 정보를 넣습니다. 값은 `Local.xcconfig`에만 저장되고 저장소에는 올라가지 않습니다.
  `switch_backend.sh <이름> --url <서버 주소> --bundle <번들 ID> --project <Firebase 프로젝트 ID> --plist <plist 파일>`
- plist의 번들 ID·프로젝트 ID가 맞지 않으면 아무것도 바꾸지 않고 멈춥니다.
- 바꾼 뒤 Xcode에서 ⇧⌘K → 실행. 번들 ID가 다르면 기기에 따로 설치됩니다.

## 팀 서버(memory-capsule-cloud)와의 대응

| 기능 | 팀 서버 상태(11/6) | 앱 동작 |
|---|---|---|
| 회원·동의·QR 연결·목록·해제 | 개발 서버 배포됨 | 그대로 사용 |
| Live 세션 `/api/session`, 판단 `/api/decision`, 종료 `/sessions/{id}/end` | 구현, 미배포 | 배포되면 그대로 사용 |
| `/devices`, `/config/latest` | 없음 | 실패해도 무시, 앱 내장 설정 사용 |
| `/memories/control`, 일정, 보드, 알림 | 없음 | 해당 화면은 오류 안내 |
| 말하는 속도(S13)·나이(C04) | 필드 없음(무시) | 화면은 동작, 기억이 말투에는 아직 반영 안 됨 |
| 보호자 `guardian_data_view` 동의 | 대상 어르신 ID 필수 | 보호자 화면(2단계)에서 맞출 예정 |

## 무료 계정에서 안 되는 것

푸시 알림, 시간 민감 알림, Sign in with Apple, App Attest. 유료 전환 때 `Local.xcconfig`의 `MC_ENTITLEMENTS`를 `Paid.entitlements`로 바꿉니다. AlarmKit 알람은 무료 계정에서도 됩니다.

## 화면과 파일 (와이어프레임 사본 11/6 기준, 1단계: 시니어)

| 화면 | 파일 |
|---|---|
| A01 누가 사용하시나요? · C01 대화 시작 동의 | `Features/Onboarding/OnboardingViews.swift` |
| C02 마이크 권한 · C03 마이크가 꺼져 있어요 · C04 이름·나이 | `AppState.seniorConsentAccepted`, `Features/Senior/SeniorFirstRunViews.swift` |
| S01 홈 · S02 듣는 중 · S03 잠시만 · S04 답변 · S05 연결 다시 확인 | `Features/Conversation/ConversationView.swift`(`ConversationViewModel.stage`) |
| S08 말로 조작하기 · S13 말하는 속도 · P01~P03·P05·P06 보호자 연결 | `Features/Senior/SeniorSettingsView.swift` |
| 화면 이동 · 공통 틀 | `Features/Senior/SeniorFlow.swift`, `SeniorComponents.swift` |
| R2 번호 카드 · R3 안전 화면 · 기억 제어 확인 · 알람 | `ConversationView.swift`, `SafetyView.swift`, `Features/Alarm/` |
| 캐릭터(아기 새, 표정별 날개·몸 동작) | `Features/Character/BirdView.swift` |
| 보호자 화면 | `Features/Guardian/` — G01·G29·G30/31 로그인, G28 이름, G03·G22·G23/26·G24 연결, G04·G06·G07·G10·G11·G33 오늘·알림, G12·G13·G15·G27 약·일정, G16·G18·G19·G20 설정 |

**와이어프레임과 다르게 한 것**: 캐릭터는 아기 새, 보호자 연결은 부모님 폰의 QR(또는 6자리 번호)로 바로 연결(어르신 승인 P04 없음), 부모님 연락처(G17·G32) 없음, "대화 마치기" 버튼·"연결된 보호자 · 동의 관리" 줄·연결 전 동의 화면 추가.

## 목 모드로 확인할 것

- 기억이를 누르면 예시 대화가 흐르며 표정이 바뀝니다.
- 개발자 패널(DEBUG): 표정 4종, 알람 화면 보기, 처음 실행 상태로 되돌리기.
- 목 판단(`MockAPIClient`): "죽고 싶" → R3 안전 화면, "불안해서 미치" → R2 번호 카드, "지워줘" → 기억 제어 확인.
- 보호자: 아무 이메일·비밀번호로 로그인(`wrong`은 오류), 연결 번호는 아무 6자리(`000000`은 만료). 팀 서버에 없는 API 목록은 [docs/app/memory_capsule_ios_mock_api.md](../docs/app/memory_capsule_ios_mock_api.md).

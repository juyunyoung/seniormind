# 기억의 캡슐 iOS (SeniorMind)

SwiftUI, iOS 26 이상, 번들 ID `com.daljoalab.seniormind`, 홈 화면 이름 "기억의 캡슐". 기본은 **목 모드**로, 서버 없이 화면 흐름을 끝까지 볼 수 있습니다.

## 실행(Mac)

```bash
brew install xcodegen
cd app/ios
cp Config/Local.xcconfig.example Config/Local.xcconfig   # 팀 ID 입력
xcodegen generate
open SeniorMind.xcodeproj
```
- 무료 Apple 계정이면 `Local.xcconfig`의 `MC_DEVELOPMENT_TEAM`에 Personal Team ID를 넣습니다. 권한 파일은 기본값 `Free.entitlements`(빈 파일)라 그대로 빌드됩니다.
- 패키지(WebRTC, Firebase)를 처음 받는 데 시간이 걸립니다. 오류가 나면 File → Packages → Reset Package Caches.
- 실서버 연결: `Local.xcconfig`에 `MC_API_BASE_URL`, `MC_USE_MOCK = NO`, Firebase 콘솔에서 받은 `GoogleService-Info.plist`를 `SeniorMind/`에 둡니다.

## 무료 계정에서 안 되는 것

푸시 알림, 시간 민감 알림, Sign in with Apple, App Attest. 코드는 들어 있고 유료 전환 때 `Paid.entitlements`로 바꾸면 켜집니다(`docs/TODO.md` T2). AlarmKit 알람은 무료 계정에서도 됩니다.

## 화면과 파일

| 화면(와이어프레임) | 모드 | 파일 |
|---|---|---|
| E00 역할 선택 | 공통 | `Features/Onboarding/OnboardingViews.swift` `RoleSelectView` |
| 동의 화면 | 공통 | 같은 파일 `ConsentFlowView`, 문구 `ConsentStep`(버전 `draft`) |
| S01 이름 입력(첫 실행) | 시니어 | `Features/Senior/SeniorFirstRunViews.swift` `NameEntryView` |
| 권한 안내 | 시니어 | 같은 파일 `PermissionPrimerView` |
| S01·S02·S04 대화 | 시니어 | `Features/Conversation/ConversationView.swift` |
| R2 상담 번호 카드 | 시니어 | 같은 파일 `hotlineCard` |
| 기억 제어 확인 | 시니어 | 같은 파일 `MemoryConfirmView`(대화 위 확인 창) |
| R3 안전 화면 | 시니어 | `Features/Conversation/SafetyView.swift` |
| 연결 실패 안내 | 시니어 | `ConversationView` 오류 상태(다시 연결·상담 번호) |
| S08 설정·도움 | 시니어 | `Features/Senior/SeniorSettingsView.swift` |
| P01 보호자 연결(QR·번호) | 시니어 | 같은 파일 `PairingQRView` |
| 알람 화면 | 시니어 | `Features/Alarm/AlarmRingView.swift`, 예약 `AlarmScheduler.swift` |
| 보호자 화면(G03·G04·G07·G12·G13) | 보호자 | `Features/Guardian/GuardianViews.swift` — 2차에서 다시 작업 |

## 캐릭터

아기 새 시안(11/2 "기억이, 두 가지 모습")을 그대로 옮겼습니다. 몸·날개 이미지는 시안에서 추출했고, 눈·볼·부리는 코드로 그립니다. 표정 4종의 날개·몸 동작 값은 팀 앱 계획서 1.4 표와 같습니다(`Features/Character/BirdView.swift`). 서버 `reaction` 6종 → 표정 매핑은 `ReactionMotion.swift`.

## 목 모드로 확인할 것

- 대화하기 → 예시 장면이 흐르며 표정이 바뀝니다.
- 개발자 패널(DEBUG): 표정 4종, 알람 화면 보기, 처음 실행 상태로 되돌리기.
- 목 판단 규칙(`MockAPIClient`): "죽고 싶" → R3 안전 화면, "불안해서 미치" → R2 번호 카드, "지워줘" → 기억 제어 확인.

## 서버 연결 규칙

- 딥링크: `seniormind://pair?v=1&code=123456`. 팀 공통 `memorycapsule://`도 읽습니다(T1).
- 요청 헤더: `Authorization`(Firebase ID 토큰), `X-Firebase-AppCheck`, `X-Config-Version`, `X-Client-Platform: ios`, `X-App-Version`.
- 회신 전 임시 규칙: 반응 6종, Q10은 `same_intent_question`만, 선호 주제 AND(T6).

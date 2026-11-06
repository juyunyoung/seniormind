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

## 화면과 파일 (와이어프레임 사본 11/6 기준, 1단계: 시니어)

| 화면 | 파일 |
|---|---|
| A01 누가 사용하시나요? | `Features/Onboarding/OnboardingViews.swift` `RoleSelectView` |
| C01 대화 시작 동의 · 개인정보 처리 안내 | 같은 파일 `SeniorConsentView`, `PrivacyNoticeView` |
| C02 마이크 권한(시스템 팝업) · C03 마이크가 꺼져 있어요 | `AppState.seniorConsentAccepted`, `Features/Senior/SeniorFirstRunViews.swift` `MicOffView` |
| C04 어떻게 불러드릴까요?(이름·나이) | 같은 파일 `NameEntryView` |
| S01 홈 · S02 듣는 중 · S03 잠시만 기다려 주세요 · S04 기억이 답변 · S05 연결 다시 확인 | `Features/Conversation/ConversationView.swift`(단계는 `ConversationViewModel.stage`) |
| S08 말로 조작하기 · S13 말하는 속도 | `Features/Senior/SeniorSettingsView.swift` |
| P01 보여주세요 · P02 QR · P03 인증번호 · P05 연결됐어요 · P06 새 번호 | 같은 파일 `Pair*View`, `PairingSession` |
| 화면 이동 | `Features/Senior/SeniorFlow.swift` `SeniorRouter`, `SeniorRootView` |
| 공통 틀(이전·설정·도움, 말풍선, 카드) | `Features/Senior/SeniorComponents.swift` |
| R2 번호 카드 · R3 안전 화면 · 기억 제어 확인 · 알람 화면 | `ConversationView.swift`, `SafetyView.swift`, `AlarmRingView.swift` |
| 보호자 화면 | `Features/Guardian/GuardianViews.swift` — 2단계에서 와이어프레임대로 다시 작업 |

**와이어프레임과 다르게 한 것**
- 캐릭터는 결정된 아기 새를 씁니다(와이어프레임은 원형 자리 표시).
- 보호자 연결은 부모님 폰의 QR(또는 같은 화면의 6자리 번호)로 바로 연결합니다. 어르신 승인 화면(P04)은 만들지 않습니다.
- 대화 중 "대화 마치기" 버튼을 추가했습니다(음성 "그만할게"가 기본, 버튼은 대비용).
- S08에 "연결된 보호자 · 동의 관리" 줄을 추가했습니다. 동의 철회 수단이 필요해서입니다.
- 보호자 연결 전에 보호자 공유·일정 공유 동의 화면을 거칩니다(서버가 확인하는 동의).
- 말하는 속도는 "천천히"를 고르면 기억이 지시문에 반영되고, 안내 음성도 조금 느려집니다.

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

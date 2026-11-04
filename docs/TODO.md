# 나중에 할 일

| # | 할 일 | 언제 | 메모 |
|---|---|---|---|
| T1 | **딥링크 스킴 통일** | Android·백엔드와 맞출 때 | iOS는 `seniormind://`, 팀 공통 계약(backend 6.3, 앱 계획서 2.1)은 `memorycapsule://`. iOS는 두 스킴을 모두 읽는다. 한쪽으로 정해 문서·Android·서버 `qr_payload`를 한꺼번에 바꾼다. |
| T2 | **Apple Developer 유료 전환** | 출시 직전 | 무료 계정에서는 푸시, 시간 민감 알림, Sign in with Apple, App Attest를 못 쓴다. 전환 후 `Config/Local.xcconfig`에서 `MC_ENTITLEMENTS`를 `Paid.entitlements`로, Firebase App Check를 App Attest로, 서버 `APP_CHECK_MODE=enforce`. 팀 ID가 `daljoalab` 계정인지 개인인지 그때 확정. |
| T3 | **OpenAI 키 등록** | 실서버 대화 연결 때 | `db/scripts/set_openai_key.sh` 실행. 키는 채팅·디스코드·저장소에 남기지 않는다. |
| T4 | 데모 전 최소 인스턴스 1 | 성과공유회 전날 | `gcloud run services update seniormind-api --min-instances 1 --region asia-northeast3`. 끝나면 0으로. |
| T5 | 보호자 2차 화면 | 1차 시니어 화면 후 | 가입·로그인(이메일·Google·Apple), 이름 입력, G03 관계 선택, G04·G07(안전 확인 버튼)·G12·G13·G16, 알림 설정. |
| T6 | 데이터 담당 회신 반영 | 회신 후 | `Q00_reaction` 위치, Q10 이름(`Q10_memory_signal`)과 `orientation_question`, `previous_reaction` 입력 설명. 지금은 반응 6종·Q10은 `same_intent_question`만·선호 주제 AND로 진행. |
| T7 | 동의 문구 교체 | 작업 목록 L13 완료 후 | 앱의 자리 표시 문구와 `ConsentStep.version = "draft"`를 확정본으로. |
| T8 | 상담 번호 확인일 | 배포 전 | 설정의 `safety.numbers_verified_at`이 비어 있으면 배포 금지. 확인 후 날짜 기입. |
| T9 | GitHub `main` 보호 | 지금 | Settings → Branches → `main` 규칙: PR 필수, 강제 push 금지. 도구로는 설정할 수 없어 직접 켜야 한다. |
| T10 | 백엔드 P2 | iOS 실서버 연결 확인 후 | 카드 추출·임베딩·`/recall`, 배치(기준선·추세, 일정 미확인, 자막 7일 만료, 추출 재시도, R3 30분 미확인 재발송, 방해 금지 시간 뒤 재발송), 설정 서명. |
| T11 | OpenAI 실제 형식 맞추기 | 키 등록 직후 | `backend/README.md` "실제 OpenAI로 확인할 것". 첫 호출 응답을 보고 `DecisionQuestions`·`DecisionParser`만 고친다. |

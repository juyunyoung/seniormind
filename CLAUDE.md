# seniormind 작업 메모

- **개발 PC는 모두 Mac**이다. 실행 방법·명령은 macOS(터미널, Homebrew, Xcode) 기준으로 안내한다.
  - 도구: `brew install xcodegen`, `brew install --cask google-cloud-sdk`, `npm i -g firebase-tools`
  - 백엔드는 Cloud Build가 빌드하므로 로컬 Java가 없어도 배포된다(`backend/scripts/deploy.sh`).
- 이 저장소는 리더 1인 개발 기준. 기능 명세·결정 기록은 팀 저장소 `try-hackathon-study/memory-capsule`.
- 폴더: `app/ios`(iOS 26+, `com.daljoalab.seniormind`), `backend`(Java 21, Spring Boot, Cloud Run 서울), `db`(Firestore 규칙·인덱스·스크립트), `docs/TODO.md`(나중에 할 일).
- GCP 프로젝트 `seniormind-513700`, 지역 `asia-northeast3`.
- 비밀은 올리지 않는다: OpenAI 키(Secret Manager만), `GoogleService-Info.plist`, `app/ios/Config/Local.xcconfig`.
- `main`은 작업 브랜치에서 PR로 병합한다.
- 답변은 한국어로, 첫 답은 핵심만. 다음 단계나 토큰이 많이 드는 작업은 먼저 확인한다.

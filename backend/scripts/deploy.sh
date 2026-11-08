#!/usr/bin/env bash
# Cloud Run 배포(처음에는 로컬에서). 안정되면 GitHub 연동 자동 배포로 바꾼다.
# 먼저 db/scripts/setup_gcp.sh, 실서버 대화 전에는 db/scripts/set_openai_key.sh 를 실행해 둔다.
set -euo pipefail
PROJECT=seniormind-513700
REGION=asia-northeast3
SERVICE=seniormind-api
APP_CHECK_MODE=${APP_CHECK_MODE:-log}     # 무료 Apple 계정 기간: log, 유료 전환 후: enforce
MIN_INSTANCES=${MIN_INSTANCES:-0}          # 데모 전날 1로

gcloud config set project "$PROJECT" >/dev/null
NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
RUNTIME_SA="${NUMBER}-compute@developer.gserviceaccount.com"

# 실행 계정이 OpenAI 키를 읽을 수 있게(한 번만 필요, 반복 실행해도 무해)
gcloud secrets add-iam-policy-binding openai-api-key \
  --member="serviceAccount:${RUNTIME_SA}" --role=roles/secretmanager.secretAccessor >/dev/null

cd "$(dirname "$0")/.."
gcloud run deploy "$SERVICE" --source . --region "$REGION" \
  --allow-unauthenticated \
  --min-instances "$MIN_INSTANCES" --max-instances 3 \
  --memory 1Gi --cpu 1 --timeout 60 \
  --set-secrets OPENAI_API_KEY=openai-api-key:latest \
  --set-env-vars "GOOGLE_CLOUD_PROJECT=${PROJECT},PROJECT_NUMBER=${NUMBER},APP_CHECK_MODE=${APP_CHECK_MODE}"

URL=$(gcloud run services describe "$SERVICE" --region "$REGION" --format='value(status.url)')
echo "배포 완료: $URL"
curl -fsS "$URL/health" && echo
echo "iOS 앱을 이 서버로: \"\$HOME/seniormind/app/ios/scripts/switch_backend.sh\" seniormind --url $URL"

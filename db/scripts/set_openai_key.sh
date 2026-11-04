#!/usr/bin/env bash
# 서버용 OpenAI 키를 Secret Manager에 넣는다. 키는 화면·채팅·저장소 어디에도 남기지 않는다.
set -euo pipefail
gcloud config set project seniormind-513700
read -rsp "OpenAI API 키 붙여넣기(화면에 안 보임): " KEY; echo
printf '%s' "$KEY" | gcloud secrets versions add openai-api-key --data-file=-
unset KEY
echo "등록 완료. Cloud Run은 --set-secrets OPENAI_API_KEY=openai-api-key:latest 로 읽는다."

#!/usr/bin/env bash
# seniormind-513700 프로젝트 초기 설정(한 번만). Mac 터미널에서 실행.
# 준비: ① Firebase 콘솔에서 "프로젝트 추가 → 기존 Google Cloud 프로젝트 seniormind-513700 선택"으로 Firebase 연결
#       ② gcloud auth login ③ npm i -g firebase-tools && firebase login
set -euo pipefail
PROJECT=seniormind-513700
REGION=asia-northeast3   # 서울. Firestore 위치는 만든 뒤 바꿀 수 없다.

gcloud config set project "$PROJECT"

echo "1) 필요한 API 켜기"
gcloud services enable \
  firestore.googleapis.com run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com pubsub.googleapis.com cloudscheduler.googleapis.com \
  firebase.googleapis.com identitytoolkit.googleapis.com fcm.googleapis.com firebaseappcheck.googleapis.com

echo "2) Firestore(Native 모드, 기본 데이터베이스, 서울)"
if gcloud firestore databases describe --database='(default)' >/dev/null 2>&1; then
  echo "   이미 있음: $(gcloud firestore databases describe --database='(default)' --format='value(locationId,type)')"
else
  gcloud firestore databases create --database='(default)' --location="$REGION" --type=firestore-native
fi

echo "3) 보안 규칙·인덱스 배포(벡터 인덱스 포함, 생성에 수 분 걸림)"
cd "$(dirname "$0")/.."
firebase deploy --only firestore:rules,firestore:indexes --project "$PROJECT"

echo "4) OpenAI 키 자리 만들기(값은 나중에: scripts/set_openai_key.sh)"
gcloud secrets describe openai-api-key >/dev/null 2>&1 || gcloud secrets create openai-api-key --replication-policy=automatic

echo "완료. 다음: Firebase 콘솔에서 iOS 앱 등록·Auth 공급자 켜기(db/README.md 3장)"

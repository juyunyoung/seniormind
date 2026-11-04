"""설정 문서(config_versions)를 Firestore에 넣는다.
준비: pip install google-cloud-firestore && gcloud auth application-default login
실행: python db/scripts/seed_config.py db/seed/config_versions.2026.11.04-1.json
"""
import json
import sys
from datetime import datetime, timezone

from google.cloud import firestore

PROJECT = "seniormind-513700"


def main(path: str) -> None:
    doc = json.load(open(path, encoding="utf-8"))
    version = doc["config"]["config_version"]
    db = firestore.Client(project=PROJECT)
    for old in db.collection("config_versions").where("active", "==", True).stream():
        old.reference.update({"active": False})
    doc["published_at"] = datetime.now(timezone.utc)
    doc["schema_version"] = "1"
    db.collection("config_versions").document(version).set(doc)
    print(f"config_versions/{version} 활성화")


if __name__ == "__main__":
    main(sys.argv[1])

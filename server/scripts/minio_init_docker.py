#!/usr/bin/env python
"""Tạo bucket MinIO cho Dock_Manager — thay cho container `minio/mc`.

MinIO đã xoá repo `minio/minio` và `minio/mc` khỏi Docker Hub (11/09/2026) nên
bước init cũ bằng `mc mb` không còn pull được image. Script này dùng SDK `minio`
(có sẵn trong image app) nên KHÔNG cần registry ngoài.

Idempotent: chạy lại bao nhiêu lần cũng an toàn.
"""
import os
import sys
import time

from minio import Minio
from minio.error import S3Error

WAIT_SECONDS = int(os.environ.get("MINIO_INIT_WAIT_SECONDS", "60"))


def env(*names: str, default: str = "") -> str:
    for n in names:
        v = (os.environ.get(n) or "").strip()
        if v:
            return v
    return default


def main() -> int:
    endpoint = env("MINIO_ENDPOINT", default="minio:9000")
    secure = env("MINIO_SECURE", default="false").lower() in ("1", "true", "yes", "on")
    access_key = env("MINIO_ROOT_USER", "MINIO_ACCESS_KEY", "AWS_ACCESS_KEY_ID")
    secret_key = env("MINIO_ROOT_PASSWORD", "MINIO_SECRET_KEY", "AWS_SECRET_ACCESS_KEY")
    bucket = env("MINIO_BUCKET", default="media")

    if not access_key or not secret_key:
        print("LOI: thiếu credential MinIO trong .env", file=sys.stderr)
        return 2

    client = Minio(endpoint, access_key=access_key, secret_key=secret_key, secure=secure)

    deadline = time.time() + WAIT_SECONDS
    last_err = None
    while time.time() < deadline:
        try:
            if client.bucket_exists(bucket):
                print(f"OK  bucket '{bucket}' đã tồn tại trên {endpoint}")
            else:
                client.make_bucket(bucket)
                print(f"OK  đã tạo bucket '{bucket}' trên {endpoint}")
            return 0
        except (S3Error, Exception) as exc:  # noqa: BLE001 — chờ service lên
            last_err = exc
            print(f"chờ MinIO... {exc}", flush=True)
            time.sleep(3)

    print(f"LOI: MinIO không sẵn sàng sau {WAIT_SECONDS}s ({last_err})", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())

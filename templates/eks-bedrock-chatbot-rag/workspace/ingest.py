#!/usr/bin/env python3
"""
Bedrock Knowledge Base ingestion script.

Triggers a sync of the configured S3 data source into the Knowledge Base.
Run this manually or via the CronJob defined in k8s/ingestion-job.yaml.

Usage:
    export AWS_REGION=us-gov-west-1
    export BEDROCK_KB_ID=replace-me
    export BEDROCK_KB_DATA_SOURCE_ID=replace-me
    python workspace/ingest.py
"""
import os
import sys

import boto3
from botocore.exceptions import ClientError

REGION = os.environ.get("AWS_REGION", "us-gov-west-1")
KB_ID = os.environ["BEDROCK_KB_ID"]
DATA_SOURCE_ID = os.environ["BEDROCK_KB_DATA_SOURCE_ID"]


def start_ingestion_job(client) -> str:
    response = client.start_ingestion_job(
        knowledgeBaseId=KB_ID,
        dataSourceId=DATA_SOURCE_ID,
    )
    return response["ingestionJob"]["ingestionJobId"]


def main() -> int:
    client = boto3.client("bedrock-agent", region_name=REGION)
    print(f"Starting ingestion job for KB={KB_ID}, DataSource={DATA_SOURCE_ID}")

    try:
        job_id = start_ingestion_job(client)
    except ClientError as exc:
        print(f"[ERROR] Failed to start ingestion job: {exc}", file=sys.stderr)
        return 1

    print(f"Ingestion job started: {job_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

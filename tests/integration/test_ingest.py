"""
Integration tests for the Bedrock Knowledge Base ingestion script.

Mocks boto3 bedrock-agent client to verify StartIngestionJob call shape
without requiring real AWS credentials or a live Knowledge Base.
"""
import importlib.util
import os
import sys
import types
import unittest
from unittest.mock import MagicMock, patch


def _load_ingest(kb_id: str = "kb-test-ingest", data_source_id: str = "ds-test-001"):
    """Import ingest.py with mocked boto3 and preset environment variables."""
    mock_agent_client = MagicMock()

    def _fake_boto3_client(service_name, **kwargs):
        if service_name == "bedrock-agent":
            return mock_agent_client
        return MagicMock()

    mock_boto3 = MagicMock()
    mock_boto3.client.side_effect = _fake_boto3_client

    fake_botocore = types.ModuleType("botocore")
    fake_exceptions = types.ModuleType("botocore.exceptions")

    class ClientError(Exception):
        def __init__(self, error_response, operation_name):
            self.response = error_response
            super().__init__(str(error_response))

    fake_exceptions.ClientError = ClientError
    fake_botocore.exceptions = fake_exceptions
    sys.modules["botocore"] = fake_botocore
    sys.modules["botocore.exceptions"] = fake_exceptions
    sys.modules["boto3"] = mock_boto3

    env_patch = {
        "AWS_REGION": "us-gov-west-1",
        "BEDROCK_KB_ID": kb_id,
        "BEDROCK_KB_DATA_SOURCE_ID": data_source_id,
    }
    for k, v in env_patch.items():
        os.environ[k] = v

    spec = importlib.util.spec_from_file_location(
        "ingest",
        os.path.join(
            os.path.dirname(__file__),
            "../../templates/eks-bedrock-chatbot-rag/workspace/ingest.py",
        ),
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod, mock_agent_client


class TestIngestStartIngestionJob(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod, cls.mock_agent = _load_ingest()

    def setUp(self):
        # Reset mock state before each test
        self.mock_agent.reset_mock()

    def _mock_ingestion_response(self, job_id: str = "job-abc-123") -> dict:
        return {
            "ingestionJob": {
                "ingestionJobId": job_id,
                "knowledgeBaseId": os.environ["BEDROCK_KB_ID"],
                "dataSourceId": os.environ["BEDROCK_KB_DATA_SOURCE_ID"],
                "status": "STARTING",
            }
        }

    def test_start_ingestion_job_returns_job_id(self):
        self.mock_agent.start_ingestion_job.return_value = self._mock_ingestion_response("job-xyz")
        job_id = self.mod.start_ingestion_job(self.mock_agent)
        self.assertEqual(job_id, "job-xyz")

    def test_start_ingestion_job_called_with_correct_kb_id(self):
        self.mock_agent.start_ingestion_job.return_value = self._mock_ingestion_response()
        self.mod.start_ingestion_job(self.mock_agent)
        call_kwargs = self.mock_agent.start_ingestion_job.call_args.kwargs
        self.assertEqual(call_kwargs["knowledgeBaseId"], self.mod.KB_ID)

    def test_start_ingestion_job_called_with_correct_data_source_id(self):
        self.mock_agent.start_ingestion_job.return_value = self._mock_ingestion_response()
        self.mod.start_ingestion_job(self.mock_agent)
        call_kwargs = self.mock_agent.start_ingestion_job.call_args.kwargs
        self.assertEqual(call_kwargs["dataSourceId"], self.mod.DATA_SOURCE_ID)

    def test_start_ingestion_job_called_exactly_once(self):
        self.mock_agent.start_ingestion_job.return_value = self._mock_ingestion_response()
        self.mod.start_ingestion_job(self.mock_agent)
        self.mock_agent.start_ingestion_job.assert_called_once()


class TestIngestMain(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod, cls.mock_agent = _load_ingest()

    def setUp(self):
        self.mock_agent.reset_mock()

    def _mock_ingestion_response(self, job_id: str = "job-main-001") -> dict:
        return {
            "ingestionJob": {
                "ingestionJobId": job_id,
                "status": "STARTING",
            }
        }

    def test_main_returns_0_on_success(self):
        self.mock_agent.start_ingestion_job.return_value = self._mock_ingestion_response()
        exit_code = self.mod.main()
        self.assertEqual(exit_code, 0)

    def test_main_returns_1_on_client_error(self):
        from botocore.exceptions import ClientError
        self.mock_agent.start_ingestion_job.side_effect = ClientError(
            {"Error": {"Code": "ResourceNotFoundException", "Message": "KB not found"}},
            "StartIngestionJob",
        )
        exit_code = self.mod.main()
        self.assertEqual(exit_code, 1)
        self.mock_agent.start_ingestion_job.side_effect = None

    def test_main_calls_boto3_client_with_bedrock_agent(self):
        # Reload to capture the boto3.client call made inside main()
        self.mock_agent.start_ingestion_job.return_value = self._mock_ingestion_response()
        sys.modules["boto3"].client.side_effect = lambda s, **kw: self.mock_agent
        self.mod.main()
        # Verify the service name used is 'bedrock-agent'
        call_args = sys.modules["boto3"].client.call_args
        self.assertIn("bedrock-agent", call_args.args)


if __name__ == "__main__":
    unittest.main()

"""
Integration tests for the RAG chatbot Flask service.

Mocks both bedrock-runtime (Converse) and bedrock-agent-runtime (Retrieve)
so no real AWS credentials are needed.
"""
import importlib.util
import os
import sys
import types
import unittest
from unittest.mock import MagicMock


def _load_rag_chatbot():
    """Import rag_chatbot with fully mocked boto3 and botocore."""
    mock_bedrock_client = MagicMock()
    mock_kb_client = MagicMock()

    def _fake_boto3_client(service_name, **kwargs):
        if service_name == "bedrock-runtime":
            return mock_bedrock_client
        if service_name == "bedrock-agent-runtime":
            return mock_kb_client
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

    os.environ["BEDROCK_KB_ID"] = "kb-test-123"
    os.environ["AWS_REGION"] = "us-gov-west-1"

    spec = importlib.util.spec_from_file_location(
        "rag_chatbot",
        os.path.join(
            os.path.dirname(__file__),
            "../../templates/eks-bedrock-chatbot-rag/workspace/rag_chatbot.py",
        ),
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod, mock_bedrock_client, mock_kb_client


def _kb_retrieve_response(*passages: str) -> dict:
    return {
        "retrievalResults": [
            {"content": {"text": p}} for p in passages
        ]
    }


def _converse_response(reply: str) -> dict:
    return {
        "output": {
            "message": {
                "content": [{"text": reply}]
            }
        }
    }


class TestRagChatbotHealth(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod, cls.mock_bedrock, cls.mock_kb = _load_rag_chatbot()
        cls.client = cls.mod.app.test_client()

    def test_health_returns_200(self):
        resp = self.client.get("/health")
        self.assertEqual(resp.status_code, 200)

    def test_health_includes_kb_id(self):
        resp = self.client.get("/health")
        data = resp.get_json()
        self.assertIn("kb_id", data)
        self.assertEqual(data["kb_id"], self.mod.KB_ID)


class TestRagChatbotChat(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod, cls.mock_bedrock, cls.mock_kb = _load_rag_chatbot()
        cls.client = cls.mod.app.test_client()

    def test_chat_returns_200(self):
        self.mock_kb.retrieve.return_value = _kb_retrieve_response("Fact A")
        self.mock_bedrock.converse.return_value = _converse_response("Based on context: Fact A.")
        resp = self.client.post("/chat", json={"message": "What is Fact A?"})
        self.assertEqual(resp.status_code, 200)

    def test_retrieve_called_with_correct_kb_id(self):
        self.mock_kb.retrieve.return_value = _kb_retrieve_response("Chunk 1")
        self.mock_bedrock.converse.return_value = _converse_response("Answer.")
        self.client.post("/chat", json={"message": "query"})
        call_kwargs = self.mock_kb.retrieve.call_args.kwargs
        self.assertEqual(call_kwargs["knowledgeBaseId"], self.mod.KB_ID)

    def test_retrieve_called_before_converse(self):
        """Verify retrieve happens before converse (RAG pipeline order)."""
        call_order = []
        self.mock_kb.retrieve.side_effect = (
            lambda **kw: call_order.append("retrieve") or _kb_retrieve_response("ctx")
        )
        self.mock_bedrock.converse.side_effect = (
            lambda **kw: call_order.append("converse") or _converse_response("ok")
        )
        self.client.post("/chat", json={"message": "order test"})
        self.assertEqual(call_order, ["retrieve", "converse"])
        self.mock_kb.retrieve.side_effect = None
        self.mock_bedrock.converse.side_effect = None

    def test_retrieved_context_injected_into_system_prompt(self):
        passage = "The capital of France is Paris."
        self.mock_kb.retrieve.return_value = _kb_retrieve_response(passage)
        self.mock_bedrock.converse.return_value = _converse_response("Paris.")
        self.client.post("/chat", json={"message": "capital of France?"})
        converse_kwargs = self.mock_bedrock.converse.call_args.kwargs
        system_text = converse_kwargs["system"][0]["text"]
        self.assertIn(passage, system_text)

    def test_chat_returns_kb_id_in_response(self):
        self.mock_kb.retrieve.return_value = _kb_retrieve_response("data")
        self.mock_bedrock.converse.return_value = _converse_response("reply")
        resp = self.client.post("/chat", json={"message": "question"})
        data = resp.get_json()
        self.assertIn("kb_id", data)

    def test_missing_message_returns_400(self):
        resp = self.client.post("/chat", json={})
        self.assertEqual(resp.status_code, 400)

    def test_converse_api_error_returns_502(self):
        from botocore.exceptions import ClientError
        self.mock_kb.retrieve.return_value = _kb_retrieve_response("ctx")
        self.mock_bedrock.converse.side_effect = ClientError(
            {"Error": {"Code": "ServiceUnavailableException", "Message": "Service down"}},
            "Converse",
        )
        resp = self.client.post("/chat", json={"message": "error case"})
        self.assertEqual(resp.status_code, 502)
        self.mock_bedrock.converse.side_effect = None


if __name__ == "__main__":
    unittest.main()

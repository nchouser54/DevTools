"""
Integration tests for the starter chatbot Flask service.

Uses unittest.mock to stub out AWS Bedrock so no real credentials are needed.
"""
import importlib
import sys
import types
import unittest
from unittest.mock import MagicMock, patch


def _load_chatbot():
    """Import starter chatbot with mocked boto3 to avoid real AWS calls at import time."""
    mock_bedrock = MagicMock()
    mock_boto3 = MagicMock()
    mock_boto3.client.return_value = mock_bedrock

    # Provide a fake botocore.exceptions module
    fake_botocore = types.ModuleType("botocore")
    fake_exceptions = types.ModuleType("botocore.exceptions")

    class ClientError(Exception):
        def __init__(self, error_response, operation_name):
            self.response = error_response
            super().__init__(str(error_response))

    fake_exceptions.ClientError = ClientError
    fake_botocore.exceptions = fake_exceptions
    sys.modules.setdefault("botocore", fake_botocore)
    sys.modules.setdefault("botocore.exceptions", fake_exceptions)
    sys.modules["boto3"] = mock_boto3

    import importlib.util, os
    spec = importlib.util.spec_from_file_location(
        "chatbot_starter",
        os.path.join(
            os.path.dirname(__file__),
            "../../templates/eks-bedrock-chatbot-starter/workspace/chatbot.py",
        ),
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod, mock_bedrock


class TestStarterChatbotHealth(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod, cls.mock_bedrock = _load_chatbot()
        cls.client = cls.mod.app.test_client()

    def test_health_returns_200(self):
        resp = self.client.get("/health")
        self.assertEqual(resp.status_code, 200)

    def test_health_body_has_status_ok(self):
        resp = self.client.get("/health")
        data = resp.get_json()
        self.assertEqual(data["status"], "ok")

    def test_health_body_has_model_and_region(self):
        resp = self.client.get("/health")
        data = resp.get_json()
        self.assertIn("model", data)
        self.assertIn("region", data)


class TestStarterChatbotChat(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod, cls.mock_bedrock = _load_chatbot()
        cls.client = cls.mod.app.test_client()

    def _make_converse_response(self, reply_text: str) -> dict:
        return {
            "output": {
                "message": {
                    "content": [{"text": reply_text}]
                }
            }
        }

    def test_chat_returns_200(self):
        self.mock_bedrock.converse.return_value = self._make_converse_response("Hello!")
        resp = self.client.post("/chat", json={"message": "Hi"})
        self.assertEqual(resp.status_code, 200)

    def test_chat_returns_reply(self):
        self.mock_bedrock.converse.return_value = self._make_converse_response("Pong!")
        resp = self.client.post("/chat", json={"message": "Ping"})
        data = resp.get_json()
        self.assertEqual(data["reply"], "Pong!")

    def test_chat_appends_to_history(self):
        self.mock_bedrock.converse.return_value = self._make_converse_response("Yes.")
        prior_history = [
            {"role": "user", "content": [{"text": "First turn"}]},
            {"role": "assistant", "content": [{"text": "Acknowledged."}]},
        ]
        resp = self.client.post("/chat", json={"message": "Second turn", "history": prior_history})
        data = resp.get_json()
        self.assertEqual(len(data["history"]), 4)  # 2 prior + user + assistant

    def test_converse_called_with_correct_model(self):
        self.mock_bedrock.converse.return_value = self._make_converse_response("OK")
        self.client.post("/chat", json={"message": "test"})
        call_kwargs = self.mock_bedrock.converse.call_args.kwargs
        self.assertEqual(call_kwargs["modelId"], self.mod.MODEL_ID)

    def test_missing_message_returns_400(self):
        resp = self.client.post("/chat", json={})
        self.assertEqual(resp.status_code, 400)

    def test_empty_message_returns_400(self):
        resp = self.client.post("/chat", json={"message": "   "})
        self.assertEqual(resp.status_code, 400)

    def test_bedrock_client_error_returns_502(self):
        from botocore.exceptions import ClientError
        self.mock_bedrock.converse.side_effect = ClientError(
            {"Error": {"Code": "ThrottlingException", "Message": "Rate exceeded"}},
            "Converse",
        )
        resp = self.client.post("/chat", json={"message": "throttled?"})
        self.assertEqual(resp.status_code, 502)
        self.mock_bedrock.converse.side_effect = None  # reset


if __name__ == "__main__":
    unittest.main()

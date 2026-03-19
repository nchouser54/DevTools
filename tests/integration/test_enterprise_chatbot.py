"""
Integration tests for the enterprise chatbot Flask service.

Stubs out boto3, botocore, opentelemetry, and structlog so no real
credentials, collector endpoints, or installed OTel packages are required.
"""
import importlib.util
import os
import sys
import types
import unittest
from unittest.mock import MagicMock


def _stub_otel_modules():
    """Install minimal no-op stubs for opentelemetry packages."""
    # opentelemetry top-level
    otel = types.ModuleType("opentelemetry")
    otel_trace = types.ModuleType("opentelemetry.trace")

    class _NoopSpan:
        def __enter__(self):
            return self
        def __exit__(self, *a):
            pass
        def set_attribute(self, *a, **kw):
            pass

    class _NoopTracer:
        def start_as_current_span(self, name, **kw):
            return _NoopSpan()

    otel_trace.get_tracer = lambda *a, **kw: _NoopTracer()
    otel_trace.set_tracer_provider = lambda *a, **kw: None
    otel.trace = otel_trace

    # SDK modules
    sdk_trace = types.ModuleType("opentelemetry.sdk.trace")
    sdk_trace.TracerProvider = MagicMock(return_value=MagicMock())
    sdk_res = types.ModuleType("opentelemetry.sdk.resources")
    sdk_res.Resource = MagicMock()
    sdk_res.Resource.create = MagicMock(return_value=MagicMock())
    sdk_trace_export = types.ModuleType("opentelemetry.sdk.trace.export")
    sdk_trace_export.BatchSpanProcessor = MagicMock()

    # Exporter
    exporter_otlp = types.ModuleType("opentelemetry.exporter.otlp")
    exporter_proto = types.ModuleType("opentelemetry.exporter.otlp.proto")
    exporter_grpc = types.ModuleType("opentelemetry.exporter.otlp.proto.grpc")
    exporter_trace_module = types.ModuleType("opentelemetry.exporter.otlp.proto.grpc.trace_exporter")
    exporter_trace_module.OTLPSpanExporter = MagicMock()

    for name, mod in [
        ("opentelemetry", otel),
        ("opentelemetry.trace", otel_trace),
        ("opentelemetry.sdk", types.ModuleType("opentelemetry.sdk")),
        ("opentelemetry.sdk.trace", sdk_trace),
        ("opentelemetry.sdk.resources", sdk_res),
        ("opentelemetry.sdk.trace.export", sdk_trace_export),
        ("opentelemetry.exporter", exporter_otlp),
        ("opentelemetry.exporter.otlp", exporter_otlp),
        ("opentelemetry.exporter.otlp.proto", exporter_proto),
        ("opentelemetry.exporter.otlp.proto.grpc", exporter_grpc),
        ("opentelemetry.exporter.otlp.proto.grpc.trace_exporter", exporter_trace_module),
    ]:
        sys.modules[name] = mod


def _stub_structlog():
    structlog_mod = types.ModuleType("structlog")
    structlog_mod.configure = lambda **kw: None
    structlog_mod.get_logger = lambda: MagicMock()
    processors = types.ModuleType("structlog.processors")
    processors.TimeStamper = MagicMock(return_value=lambda *a: None)
    processors.add_log_level = lambda *a: None
    processors.JSONRenderer = MagicMock(return_value=lambda *a: None)
    structlog_mod.processors = processors
    sys.modules["structlog"] = structlog_mod
    sys.modules["structlog.processors"] = processors


def _load_enterprise_chatbot():
    """Load enterprise chatbot with all heavy dependencies stubbed."""
    _stub_otel_modules()
    _stub_structlog()

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

    os.environ.setdefault("BEDROCK_KB_ID", "kb-enterprise-001")
    os.environ.setdefault("AWS_REGION", "us-gov-west-1")
    os.environ.setdefault("OTEL_SERVICE_NAME", "bedrock-chatbot-enterprise")
    os.environ.setdefault("OTEL_EXPORTER_OTLP_ENDPOINT", "http://adot-collector:4317")

    spec = importlib.util.spec_from_file_location(
        "enterprise_chatbot",
        os.path.join(
            os.path.dirname(__file__),
            "../../templates/eks-bedrock-chatbot-secure-enterprise/workspace/enterprise_chatbot.py",
        ),
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod, mock_bedrock_client, mock_kb_client


def _kb_response(*passages: str) -> dict:
    return {"retrievalResults": [{"content": {"text": p}} for p in passages]}


def _converse_response(reply: str) -> dict:
    return {"output": {"message": {"content": [{"text": reply}]}}}


class TestEnterpriseChatbotHealth(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod, cls.mock_bedrock, cls.mock_kb = _load_enterprise_chatbot()
        cls.client = cls.mod.app.test_client()

    def test_health_returns_200(self):
        resp = self.client.get("/health")
        self.assertEqual(resp.status_code, 200)

    def test_health_contains_required_fields(self):
        resp = self.client.get("/health")
        data = resp.get_json()
        for field in ("status", "model", "kb_id", "region", "service"):
            self.assertIn(field, data, f"Missing field: {field}")
        self.assertEqual(data["status"], "ok")

    def test_health_kb_id_matches_env(self):
        resp = self.client.get("/health")
        data = resp.get_json()
        self.assertEqual(data["kb_id"], "kb-enterprise-001")


class TestEnterpriseChatbotChat(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod, cls.mock_bedrock, cls.mock_kb = _load_enterprise_chatbot()
        cls.client = cls.mod.app.test_client()

    def test_successful_rag_chat_returns_200(self):
        self.mock_kb.retrieve.return_value = _kb_response("Policy section 4.1")
        self.mock_bedrock.converse.return_value = _converse_response("See policy section 4.1.")
        resp = self.client.post("/chat", json={"message": "What does policy say?"})
        self.assertEqual(resp.status_code, 200)

    def test_reply_present_in_response(self):
        self.mock_kb.retrieve.return_value = _kb_response("context")
        self.mock_bedrock.converse.return_value = _converse_response("Detailed answer.")
        resp = self.client.post("/chat", json={"message": "Explain"})
        data = resp.get_json()
        self.assertEqual(data["reply"], "Detailed answer.")

    def test_kb_id_returned_in_response(self):
        self.mock_kb.retrieve.return_value = _kb_response("ctx")
        self.mock_bedrock.converse.return_value = _converse_response("ok")
        resp = self.client.post("/chat", json={"message": "test"})
        self.assertIn("kb_id", resp.get_json())

    def test_context_injected_into_system_prompt(self):
        passage = "SOC 2 compliance requires annual audits."
        self.mock_kb.retrieve.return_value = _kb_response(passage)
        self.mock_bedrock.converse.return_value = _converse_response("annual audits required")
        self.client.post("/chat", json={"message": "compliance question"})
        converse_kwargs = self.mock_bedrock.converse.call_args.kwargs
        system_text = converse_kwargs["system"][0]["text"]
        self.assertIn(passage, system_text)

    def test_missing_message_returns_400(self):
        resp = self.client.post("/chat", json={})
        self.assertEqual(resp.status_code, 400)

    def test_kb_error_returns_502(self):
        from botocore.exceptions import ClientError
        self.mock_kb.retrieve.side_effect = ClientError(
            {"Error": {"Code": "ResourceNotFoundException", "Message": "KB not found"}},
            "Retrieve",
        )
        resp = self.client.post("/chat", json={"message": "trigger kb error"})
        self.assertEqual(resp.status_code, 502)
        self.mock_kb.retrieve.side_effect = None

    def test_converse_error_returns_502(self):
        from botocore.exceptions import ClientError
        self.mock_kb.retrieve.return_value = _kb_response("ok")
        self.mock_bedrock.converse.side_effect = ClientError(
            {"Error": {"Code": "ModelNotReadyException", "Message": "Model not ready"}},
            "Converse",
        )
        resp = self.client.post("/chat", json={"message": "trigger converse error"})
        self.assertEqual(resp.status_code, 502)
        self.mock_bedrock.converse.side_effect = None


if __name__ == "__main__":
    unittest.main()

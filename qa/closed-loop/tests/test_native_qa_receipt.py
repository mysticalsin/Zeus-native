"""Run the native hands-on receipt tests inside the closed-loop selftest suite."""
import importlib.util
from pathlib import Path


def load_tests(loader, tests, pattern):
    path = Path(__file__).resolve().parents[2] / "native-qa" / "test_validate.py"
    spec = importlib.util.spec_from_file_location("zeus_native_qa_test_validate", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return loader.loadTestsFromModule(module)

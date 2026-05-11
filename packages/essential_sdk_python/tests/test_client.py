from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from essential_sdk import EssentialClient, EssentialModel


class EssentialClientTest(unittest.TestCase):
    def test_generate_and_stream(self) -> None:
        with TemporaryDirectory() as directory:
            root = Path(directory)
            model_path = root / "model.gguf"
            adapter_path = root / "adapter.lora"
            model_path.write_text("model", encoding="utf-8")
            adapter_path.write_text("adapter", encoding="utf-8")

            client = EssentialClient([EssentialModel("mini", model_path)])

            result = client.generate("hello from essential", model_id="mini")
            client.attach_adapter("session-1", adapter_path)
            chunks = list(client.stream("hello from essential", model_id="mini"))
            client.detach_adapter("session-1")

            self.assertEqual(result.model_id, "mini")
            self.assertEqual(result.text, "hello from essential")
            self.assertEqual("".join(chunks).strip(), "hello from essential")


if __name__ == "__main__":
    unittest.main()

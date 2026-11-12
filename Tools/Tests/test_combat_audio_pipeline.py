"""音效上传回归：指定范围、哈希增量、失败保留映射和回退历史。"""
import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

MODULE_PATH = Path(__file__).resolve().parents[1] / "Audio" / "upload_roblox_audio.py"
spec = importlib.util.spec_from_file_location("uploader", MODULE_PATH)
uploader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(uploader)


class AudioUploadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.manifest = self.root / "audio_manifest.json"
        self.original = {"sounds": {"Pickup": {"assetId": "123", "rbxassetid": "rbxassetid://123"},
                                   "BGM": {"assetId": "456"}}, "groupId": uploader.GROUP_ID}
        self.manifest.write_text(json.dumps(self.original), encoding="utf-8")
        (self.root / "Pickup.mp3").write_bytes(b"new audio")

    def run_upload(self, **kwargs):
        with patch.object(uploader, "SOUNDS_DIR", self.root), \
             patch.object(uploader, "MANIFEST_PATH", self.manifest), \
             patch.object(uploader, "get_api_key", return_value="test-only"), \
             patch.object(uploader, "upload_single_audio", **kwargs) as upload, \
             patch.object(uploader.time, "sleep"), \
             patch("sys.argv", ["upload", "--names", "Pickup"]), \
             contextlib.redirect_stdout(io.StringIO()):
            result = uploader.main()
        return result, upload

    def test_legacy_baseline_and_unchanged_skip_then_modified_upload(self):
        result, upload = self.run_upload(return_value="789")
        self.assertEqual(result, 0)
        upload.assert_not_called()
        seeded = json.loads(self.manifest.read_text(encoding="utf-8"))
        self.assertIn("sha256", seeded["sounds"]["Pickup"])
        result, upload = self.run_upload(return_value="789")
        upload.assert_not_called()
        (self.root / "Pickup.mp3").write_bytes(b"changed")
        result, upload = self.run_upload(return_value="789")
        self.assertEqual(result, 0)
        upload.assert_called_once()
        data = json.loads(self.manifest.read_text(encoding="utf-8"))
        self.assertEqual(data["sounds"]["Pickup"]["assetId"], "789")
        self.assertEqual(data["sounds"]["Pickup"]["history"][0]["assetId"], "123")
        self.assertEqual(data["sounds"]["BGM"], self.original["sounds"]["BGM"])

    def test_processing_source_hash_updates_legacy_asset(self):
        (self.root / "combat_processing.json").write_text(json.dumps({"sounds": {"Pickup": {"sourceSha256": "old"}}}))
        result, upload = self.run_upload(return_value="789")
        self.assertEqual(result, 0)
        upload.assert_called_once()
        data = json.loads(self.manifest.read_text(encoding="utf-8"))
        self.assertEqual(data["sounds"]["Pickup"]["history"][0]["sha256"], "old")

    def test_failed_upload_preserves_old_mapping_and_returns_failure(self):
        self.original["sounds"]["Pickup"]["sha256"] = "old"
        self.manifest.write_text(json.dumps(self.original))
        result, upload = self.run_upload(side_effect=RuntimeError("simulated failure"))
        self.assertEqual(result, 1)
        self.assertEqual(json.loads(self.manifest.read_text())["sounds"], self.original["sounds"])

    def test_missing_source_returns_failure(self):
        (self.root / "Pickup.mp3").unlink()
        result, upload = self.run_upload(return_value="789")
        self.assertEqual(result, 1)
        upload.assert_not_called()

    def test_corrupt_manifest_is_not_replaced(self):
        self.manifest.write_text("invalid")
        with self.assertRaises(RuntimeError):
            self.run_upload(return_value="789")
        self.assertEqual(self.manifest.read_text(), "invalid")


if __name__ == "__main__":
    unittest.main()

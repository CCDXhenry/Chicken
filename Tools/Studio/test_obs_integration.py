"""
OBS & Roblox Studio MCP 集成自动化测试
验证项:
  1. OBS WebSocket 4455 端口健康检查与协议握手
  2. RobloxStudio 来源无损截屏落盘
  3. 录像控制流完整性 (StartRecord -> Chapter -> StopRecord -> 视频文件合法性)
  4. 上下文管理器异常安全熔断兜底测试
"""

import os
import sys
import time
import unittest

from obs_controller import OBSController
from obs_studio_bridge import RobloxRecordSession, RobloxMediaBridge


class TestOBSIntegration(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.obs = OBSController()
        if not cls.obs.is_connected():
            raise unittest.SkipTest("OBS WebSocket (127.0.0.1:4455) 未运行，跳过实机集成测试。")

    def test_01_connection_and_version(self):
        """测试 1: 验证 OBS WebSocket v5 连通性及版本响应"""
        info = self.obs.get_obs_info()
        self.assertIn("obsVersion", info)
        self.assertIn("obsWebSocketVersion", info)
        print(f"\n[PASS] OBS 连通测试通过: OBS v{info['obsVersion']} / WebSocket v{info['obsWebSocketVersion']}")

    def test_02_screenshot_generation(self):
        """测试 2: 验证屏幕截图直接落地与有效性"""
        test_png = os.path.abspath("Assets/Studio/unittest_obs_screenshot.png")
        if os.path.exists(test_png):
            os.remove(test_png)

        res = self.obs.take_screenshot(save_path=test_png, image_format="png")
        self.assertTrue(res.get("success"))
        self.assertTrue(os.path.exists(test_png), "截屏文件未落地")
        size = os.path.getsize(test_png)
        self.assertGreater(size, 1024, "截屏文件小于 1KB，疑似空文件")
        print(f"[PASS] 截屏测试通过，落地路径: {test_png} ({size / 1024:.1f} KB)")

    def test_03_recording_lifecycle(self):
        """测试 3: 验证录像生命周期 (Start -> Chapter -> Stop) 及文件落盘"""
        bridge = RobloxMediaBridge(obs_controller=self.obs)
        session_name = "UnitTest_Recording_Flow"

        with bridge.record_session(session_name) as session:
            # 持续录制 2 秒
            time.sleep(1.0)
            session.mark_chapter("MidPoint_Verification")
            time.sleep(1.0)

        video_path = session.video_output_path
        self.assertIsNotNone(video_path, "未返回视频输出路径")
        self.assertTrue(os.path.exists(video_path), f"视频文件未生成: {video_path}")
        size = os.path.getsize(video_path)
        self.assertGreater(size, 1024 * 10, "录制视频文件小于 10KB")
        print(f"[PASS] 录像生命周期测试通过，生成视频: {video_path} ({size / 1024:.1f} KB)")

        # 为后续用例留出 1 秒时间戳间隔，防止同秒文件名冲突
        time.sleep(1.0)

    def test_04_record_session_exception_safety(self):
        """测试 4: 验证测试抛出异常时，录像上下文依然能够安全终止并保存证据"""
        bridge = RobloxMediaBridge(obs_controller=self.obs)
        caught = False
        saved_video = None

        try:
            with bridge.record_session("UnitTest_Simulated_Failure") as session:
                time.sleep(1.0)
                raise RuntimeError("模拟自动化测试断言失败异常")
        except RuntimeError:
            caught = True
            saved_video = session.video_output_path

        self.assertTrue(caught, "业务异常未正常传递")
        self.assertIsNotNone(saved_video, "异常发生时未能成功保存视频证据")
        self.assertTrue(os.path.exists(saved_video), "异常保护录像文件不存在")
        print(f"[PASS] 异常安全保护测试通过，故障留痕视频: {saved_video}")


if __name__ == "__main__":
    unittest.main()

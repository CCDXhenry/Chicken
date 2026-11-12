# OBS 与 Studio 媒体桥接：默认严格采集，校准失败传播错误，录像由持续守卫管理。
"""
Roblox Studio & OBS Media Bridge
统一多媒体桥接层，将 OBS 录像/截屏能力与 Roblox MCP 自动化测试深度融合。
支持自动化测试录制上下文管理器；OBS 校准失败时直接报错。
"""

import os
import sys
import time
import logging
from typing import Optional, Dict, Any

from obs_controller import OBSController, DEFAULT_SOURCE_NAME

logger = logging.getLogger("RobloxMediaBridge")


class RobloxRecordSession:
    """
    自动化实机测试录像上下文管理器。
    使用示例:
    ```python
        with RobloxRecordSession("Chicken_Farm_Regression_Test") as session:
            # 1. 调用前已进入 Play，完成校准并复核边界
            # 2. 模拟角色动作或烤鸡操作
            session.snapshot("Assets/Studio/regression_step1.png")
            # 3. 校验断言
        # 退出上下文后自动完成 MP4 视频落盘与归档
    ```
    """

    def __init__(
        self,
        session_name: str = "RobloxTestSession",
        max_duration_sec: int = 300,
        obs_controller: Optional[OBSController] = None
    ):
        self.session_name = session_name
        self.max_duration_sec = max_duration_sec
        self.obs = obs_controller or OBSController()
        self.video_output_path: Optional[str] = None
        self.is_recording = False
        self.start_timestamp = 0.0

    def __enter__(self):
        self.obs.start_record(max_duration_sec=self.max_duration_sec)
        self.is_recording = True
        self.start_timestamp = time.monotonic()
        self.obs.create_record_chapter(f'Start_{self.session_name}')
        return self

    def snapshot(self, save_path: str, chapter_mark: Optional[str] = None) -> Optional[str]:
        """在录制过程中抓取高清快照并可打入章节标记"""
        if chapter_mark and self.is_recording:
            self.obs.create_record_chapter(chapter_mark)

        res = self.obs.take_screenshot(save_path=save_path)
        return res.get("save_path")

    def mark_chapter(self, chapter_name: str):
        """插入章节标记，方便后续在播放器中按章节跳转"""
        if self.is_recording:
            self.obs.create_record_chapter(chapter_name)

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.is_recording:
            try:
                self.video_output_path = self.obs.stop_record()
            except Exception:
                self.video_output_path = self.obs._last_record_file
                if exc_type is None:
                    raise
                logger.exception('录像无效；保留原测试异常')
            finally:
                self.is_recording = False
        return False


class RobloxMediaBridge:
    """
    Roblox Studio 多媒体统一门面：
    默认使用已校准 OBS 场景；原生 MCP 截图须显式选择。
    """

    def __init__(self, mcp_client=None, obs_controller: Optional[OBSController] = None):
        self.mcp_client = mcp_client
        self.obs = obs_controller or OBSController()

    def capture_screenshot(
        self,
        save_path: Optional[str] = None,
        prefer_obs: bool = True,
        camera_position=None,
        look_at_position=None,
        studio_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        截取 Studio 画面。
        :param save_path: 保存文件路径
        :param prefer_obs: 默认使用已校准 OBS 场景；指定镜头或 prefer_obs=False 时显式使用原生 MCP
        :param camera_position: 原生 MCP 的临时镜头坐标 [x, y, z]
        :param look_at_position: 原生 MCP 的临时注视目标 [x, y, z]
        """
        # 如果指定了特定镜头角度，使用原生 MCP 的镜头位移截屏
        if camera_position is not None or look_at_position is not None or not prefer_obs:
            return self._capture_native_mcp(save_path, camera_position, look_at_position, studio_id)

        # No automatic fallback: a failed calibrated capture is invalid evidence.
        res = self.obs.take_screenshot(save_path=save_path)
        res['provider'] = 'OBS'
        return res

    def _capture_native_mcp(self, save_path, camera_position, look_at_position, studio_id):
        if not self.mcp_client:
            raise RuntimeError("未配置有效的 RobloxMCPClient，无法调用原生截屏。")

        args: Dict[str, Any] = {
            "capture_id": f"Capture_{int(time.time())}"
        }
        if camera_position:
            args["camera_position"] = camera_position
        if look_at_position:
            args["look_at_position"] = look_at_position
        if studio_id:
            args["studio_id"] = studio_id

        res = self.mcp_client.call_tool("screen_capture", args)
        return {
            "success": True,
            "provider": "RobloxMCP",
            "raw_result": res,
            "save_path": save_path
        }

    def start_recording(self) -> bool:
        """开始视频录制"""
        return self.obs.start_record()

    def stop_recording(self) -> str:
        """停止视频录制并返回绝对路径"""
        return self.obs.stop_record()

    def record_session(self, session_name: str, max_duration_sec: int = 300) -> RobloxRecordSession:
        """创建录制上下文管理器"""
        return RobloxRecordSession(session_name, max_duration_sec, self.obs)


if __name__ == "__main__":
    bridge = RobloxMediaBridge()
    print(f"[MediaBridge] OBS 可用状态: {bridge.obs.is_connected()}")
    if bridge.obs.is_connected():
        print(f"[MediaBridge] 正在抓取 OBS 测试截图...")
        snap_res = bridge.capture_screenshot(save_path="Assets/Studio/obs_test_preview.png")
        print(f"[MediaBridge] 截屏结果: {snap_res}")

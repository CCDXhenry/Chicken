"""
Roblox Studio & OBS Media Bridge
统一多媒体桥接层，将 OBS 录像/截屏能力与 Roblox MCP 自动化测试深度融合。
支持自动化测试录制上下文管理器 (RobloxRecordSession) 与多源截屏优雅降级机制。
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
            # 1. 启动 Play 模式
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
        if not self.obs.is_connected():
            print(f"[RecordSession] 警告: 未检测到 OBS WebSocket，跳过录像。")
            return self

        try:
            self.obs.ensure_roblox_window_attached()
            self.obs.start_record()
            self.is_recording = True
            self.start_timestamp = time.time()
            # 插入首个标记点
            self.obs.create_record_chapter(f"Start_{self.session_name}")
            print(f"[RecordSession] 已开启 OBS 视频录制: 【{self.session_name}】")
        except Exception as e:
            print(f"[RecordSession] 启动录制失败: {e}")

        return self

    def snapshot(self, save_path: str, chapter_mark: Optional[str] = None) -> Optional[str]:
        """在录制过程中抓取高清快照并可打入章节标记"""
        if chapter_mark and self.is_recording:
            self.obs.create_record_chapter(chapter_mark)

        if self.obs.is_connected():
            res = self.obs.take_screenshot(save_path=save_path)
            return res.get("save_path")
        return None

    def mark_chapter(self, chapter_name: str):
        """插入章节标记，方便后续在播放器中按章节跳转"""
        if self.is_recording:
            self.obs.create_record_chapter(chapter_name)

    def __exit__(self, exc_type, exc_val, exc_tb):
        if not self.is_recording:
            return False

        try:
            # 等待 0.5s 确保尾帧写入
            time.sleep(0.5)
            self.video_output_path = self.obs.stop_record()
            duration = time.time() - self.start_timestamp
            self.is_recording = False

            if exc_type is not None:
                print(f"[RecordSession] 测试过程中出现异常 [{exc_type.__name__}: {exc_val}]！")
                print(f"[RecordSession] 故障录像已完好留存用于排查分析: {self.video_output_path} (录制时长: {duration:.1f}s)")
            else:
                print(f"[RecordSession] 录像正常结束，视频文件已落地: {self.video_output_path} (时长: {duration:.1f}s)")
        except Exception as e:
            print(f"[RecordSession] 停止录像时发生异常: {e}")

        return False  # 不吞没原有的业务异常


class RobloxMediaBridge:
    """
    Roblox Studio 多媒体统一门面：
    支持 OBS 高保真截屏/录像与 Roblox 原生 MCP screen_capture 自由切换与自动降级。
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
        :param prefer_obs: 优先使用 OBS 窗口截屏；若 OBS 不在线或指定了自定义镜头坐标，降级使用原生 MCP
        :param camera_position: 原生 MCP 的临时镜头坐标 [x, y, z]
        :param look_at_position: 原生 MCP 的临时注视目标 [x, y, z]
        """
        # 如果指定了特定镜头角度，使用原生 MCP 的镜头位移截屏
        if camera_position is not None or look_at_position is not None or not prefer_obs:
            return self._capture_native_mcp(save_path, camera_position, look_at_position, studio_id)

        # 尝试 OBS 截屏
        if self.obs.is_connected():
            try:
                res = self.obs.take_screenshot(save_path=save_path)
                res["provider"] = "OBS"
                return res
            except Exception as e:
                logger.warning(f"OBS 截屏失败，尝试降级原生 MCP: {e}")

        # 降级到原生 MCP
        return self._capture_native_mcp(save_path, camera_position, look_at_position, studio_id)

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

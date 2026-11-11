"""
OBS WebSocket v5 Controller for Roblox Studio
通过本地 OBS WebSocket (端口 4455，无认证) 实现高保真视口截图、视频录制与窗口自动捕获。
"""

import asyncio
import base64
import json
import logging
import os
import sys
import time
from typing import Optional, Dict, Any, Tuple
import websockets

logger = logging.getLogger("OBSController")

DEFAULT_OBS_HOST = "127.0.0.1"
DEFAULT_OBS_PORT = 4455
DEFAULT_SCENE_NAME = "RobloxTest"
DEFAULT_SOURCE_NAME = "RobloxStudio"
MAX_RECORDING_DURATION_SEC = 300  # 单次录制最长 5 分钟安全熔断


class OBSController:
    """OBS Studio WebSocket v5 控制器"""

    def __init__(self, host: str = DEFAULT_OBS_HOST, port: int = DEFAULT_OBS_PORT, password: Optional[str] = None):
        self.ws_url = f"ws://{host}:{port}"
        self.password = password
        self.req_id_counter = 0
        self._record_start_time: Optional[float] = None
        self._last_record_file: Optional[str] = None

    def _get_next_req_id(self) -> str:
        self.req_id_counter += 1
        return f"obs_req_{int(time.time() * 1000)}_{self.req_id_counter}"

    async def _send_request_async(self, request_type: str, request_data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """通过 WebSocket 执行单次 OBS 请求"""
        async with websockets.connect(self.ws_url, open_timeout=3.0, close_timeout=3.0) as ws:
            # 1. 接收 Hello 消息 (OpCode 0)
            hello_raw = await ws.recv()
            hello = json.loads(hello_raw)
            if hello.get("op") != 0:
                raise RuntimeError(f"Unexpected initial OpCode: {hello.get('op')}")

            # 2. 发送 Identify (OpCode 1)
            identify_payload = {
                "op": 1,
                "d": {
                    "rpcVersion": 1,
                    "eventSubscriptions": 0
                }
            }
            # 如果有认证需求可在此补充鉴权，当前无密码
            await ws.send(json.dumps(identify_payload))

            # 3. 接收 Identified (OpCode 2)
            identified_raw = await ws.recv()
            identified = json.loads(identified_raw)
            if identified.get("op") != 2:
                raise RuntimeError(f"Handshake failed: {identified}")

            # 4. 发送 Request (OpCode 6)
            req_id = self._get_next_req_id()
            request_payload = {
                "op": 6,
                "d": {
                    "requestType": request_type,
                    "requestId": req_id,
                    "requestData": request_data or {}
                }
            }
            await ws.send(json.dumps(request_payload))

            # 5. 等待 RequestResponse (OpCode 7)
            resp_raw = await ws.recv()
            resp = json.loads(resp_raw)
            if resp.get("op") != 7:
                raise RuntimeError(f"Unexpected response OpCode: {resp.get('op')}")

            d = resp.get("d", {})
            status = d.get("requestStatus", {})
            if not status.get("result", False):
                code = status.get("code")
                comment = status.get("comment", "No details")
                raise RuntimeError(f"OBS Request [{request_type}] Failed (code {code}): {comment}")

            return d.get("responseData") or {}

    def send_request(self, request_type: str, request_data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """同步包装方法"""
        return asyncio.run(self._send_request_async(request_type, request_data))

    def is_connected(self) -> bool:
        """探活 OBS WebSocket 服务是否可用"""
        try:
            res = self.send_request("GetVersion")
            return bool(res.get("obsVersion"))
        except Exception:
            return False

    def get_obs_info(self) -> Dict[str, Any]:
        """获取 OBS 与 WebSocket 版本信息"""
        return self.send_request("GetVersion")

    def get_record_directory(self) -> str:
        """获取当前配置的录像输出目录"""
        res = self.send_request("GetRecordDirectory")
        return res.get("recordDirectory", "")

    def find_active_roblox_window(self) -> Optional[str]:
        """枚举 Windows 窗口，查找当前处于活动状态的 Roblox Studio 窗口标题"""
        if sys.platform != "win32":
            return None

        import ctypes
        from ctypes import wintypes

        user32 = ctypes.windll.user32
        EnumWindows = user32.EnumWindows
        EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
        GetWindowTextW = user32.GetWindowTextW
        GetWindowTextLengthW = user32.GetWindowTextLengthW
        IsWindowVisible = user32.IsWindowVisible

        found_titles = []

        def foreach_window(hwnd, lParam):
            if IsWindowVisible(hwnd):
                length = GetWindowTextLengthW(hwnd)
                if length > 0:
                    buff = ctypes.create_unicode_buffer(length + 1)
                    GetWindowTextW(hwnd, buff, length + 1)
                    title = buff.value
                    if "Roblox Studio" in title:
                        found_titles.append(title)
            return True

        EnumWindows(EnumWindowsProc(foreach_window), 0)

        if found_titles:
            # 优先返回带有项目名称的主编辑窗口
            for t in found_titles:
                if " - Roblox Studio" in t:
                    return t
            return found_titles[0]
        return None

    def ensure_roblox_window_attached(self, source_name: str = DEFAULT_SOURCE_NAME) -> bool:
        """
        检查并自适应更新 OBS 中 RobloxStudio 窗口采集源所绑定的窗口。
        解决 Roblox Studio 重启或打开新工程后窗口句柄失效的问题。
        """
        try:
            current_settings = self.send_request("GetInputSettings", {"inputName": source_name})
            settings = current_settings.get("inputSettings", {})
            current_window = settings.get("window", "")

            active_window_title = self.find_active_roblox_window()
            if not active_window_title:
                return False

            # OBS window_capture 格式规范为: "窗口标题:窗口类名:进程名"
            target_window_pattern = f"{active_window_title}:Qt5159QWindowIcon:RobloxStudioBeta.exe"

            if current_window != target_window_pattern:
                self.send_request("SetInputSettings", {
                    "inputName": source_name,
                    "inputSettings": {
                        "window": target_window_pattern
                    }
                })
            return True
        except Exception as e:
            logger.warning(f"Failed to auto-attach Roblox window: {e}")
            return False

    def take_screenshot(
        self,
        source_name: str = DEFAULT_SOURCE_NAME,
        save_path: Optional[str] = None,
        image_format: str = "png",
        image_width: Optional[int] = None,
        image_height: Optional[int] = None,
        quality: int = -1
    ) -> Dict[str, Any]:
        """
        截取指定源的画面。
        :param source_name: OBS 来源名称，默认为 'RobloxStudio'
        :param save_path: 若提供本地文件路径，则直接落盘保存
        :param image_format: 格式 ('png', 'jpg', 'webp')
        :param image_width: 目标宽度 (可选，默认保持源分辨率)
        :param image_height: 目标高度 (可选)
        :param quality: 压缩质量 1-100，默认 -1
        :return: 包含 'image_data' (Base64) 与 'save_path' 的字典
        """
        self.ensure_roblox_window_attached(source_name)

        if save_path:
            abs_path = os.path.abspath(save_path)
            os.makedirs(os.path.dirname(abs_path), exist_ok=True)
            req_data = {
                "sourceName": source_name,
                "imageFormat": image_format,
                "imageFilePath": abs_path,
                "imageQuality": quality
            }
            if image_width:
                req_data["imageWidth"] = image_width
            if image_height:
                req_data["imageHeight"] = image_height

            self.send_request("SaveSourceScreenshot", req_data)
            return {
                "success": True,
                "save_path": abs_path,
                "source_name": source_name,
                "format": image_format
            }
        else:
            req_data = {
                "sourceName": source_name,
                "imageFormat": image_format,
                "imageQuality": quality
            }
            if image_width:
                req_data["imageWidth"] = image_width
            if image_height:
                req_data["imageHeight"] = image_height

            res = self.send_request("GetSourceScreenshot", req_data)
            raw_base64 = res.get("imageData", "")
            # 去除 data:image/png;base64, 前缀以便直接进行二进制操作
            pure_base64 = raw_base64.split(",", 1)[-1] if "," in raw_base64 else raw_base64

            return {
                "success": True,
                "image_data": pure_base64,
                "data_uri": raw_base64,
                "source_name": source_name,
                "format": image_format
            }

    def start_record(self) -> bool:
        """开始录制视频"""
        status = self.get_record_status()
        if status.get("outputActive", False):
            # 已经在录制中
            return True

        self.ensure_roblox_window_attached()
        self.send_request("StartRecord")
        self._record_start_time = time.time()
        return True

    def stop_record(self, wait_finished: bool = True, timeout_sec: float = 5.0) -> str:
        """
        停止录制并返回生成的视频文件绝对路径。
        :param wait_finished: 是否等待 OBS 编码器完全写入文件并关闭句柄
        :param timeout_sec: 最大等待超时时间 (秒)
        """
        status = self.get_record_status()
        if not status.get("outputActive", False):
            return self._last_record_file or ""

        res = self.send_request("StopRecord")
        output_path = res.get("outputPath", "")
        self._last_record_file = output_path
        self._record_start_time = None

        if wait_finished:
            # 1. 轮询直到 OBS 输出处于非激活状态
            t_start = time.time()
            while time.time() - t_start < timeout_sec:
                cur_status = self.get_record_status()
                if not cur_status.get("outputActive", False):
                    break
                time.sleep(0.2)

            # 2. 轮询直到文件落盘且大小大于 0 且句柄释放
            if output_path:
                t_file = time.time()
                last_size = -1
                stable_count = 0
                while time.time() - t_file < timeout_sec:
                    if os.path.exists(output_path):
                        cur_size = os.path.getsize(output_path)
                        if cur_size > 0:
                            if cur_size == last_size:
                                stable_count += 1
                                if stable_count >= 2:
                                    break
                            else:
                                stable_count = 0
                            last_size = cur_size
                    time.sleep(0.2)

        return output_path

    def get_record_status(self) -> Dict[str, Any]:
        """
        获取当前录制状态
        返回字典包含：
        - outputActive: bool (是否在录制)
        - outputPaused: bool (是否暂停)
        - outputTimecode: str (当前时长 00:00:00.000)
        - outputDuration: int (毫秒数)
        - outputBytes: int (已写入字节)
        """
        res = self.send_request("GetRecordStatus")
        if self._record_start_time and res.get("outputActive"):
            elapsed = time.time() - self._record_start_time
            if elapsed > MAX_RECORDING_DURATION_SEC:
                logger.warning(f"录像时间超出安全阈值 ({MAX_RECORDING_DURATION_SEC}s)，执行自动熔断停止！")
                self.stop_record()
        return res

    def toggle_record_pause(self) -> bool:
        """暂停或恢复录制"""
        self.send_request("ToggleRecordPause")
        status = self.get_record_status()
        return status.get("outputPaused", False)

    def create_record_chapter(self, chapter_name: str) -> bool:
        """在当前录像文件中打入章节关键帧标记，便于故障排查快速跳转"""
        try:
            self.send_request("CreateRecordChapter", {"chapterName": chapter_name})
            return True
        except Exception:
            return False


if __name__ == "__main__":
    controller = OBSController()
    if not controller.is_connected():
        print("[OBSController] 无法连接到 127.0.0.1:4455，请确认 OBS WebSocket 服务器已启动。")
        sys.exit(1)

    info = controller.get_obs_info()
    print(f"[OBSController] 已连接 OBS v{info.get('obsVersion')}, WebSocket v{info.get('obsWebSocketVersion')}")
    print(f"[OBSController] 录像目录: {controller.get_record_directory()}")

    # 测试窗口吸附
    attached = controller.ensure_roblox_window_attached()
    print(f"[OBSController] 窗口自动绑定状态: {'成功' if attached else '未找到活跃的 Roblox Studio 窗口'}")

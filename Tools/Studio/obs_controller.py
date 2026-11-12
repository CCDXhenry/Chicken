# OBS 本地控制器：认证连接、校准视口截图与持续守卫的录像生命周期。
"""
OBS WebSocket v5 Controller for Roblox Studio
通过本地 OBS WebSocket（支持密码认证）实现严格校准的视口截图与录像。
"""

import asyncio
import base64
import json
import logging
import os
import sys
import time
import hashlib
import io
import threading
from pathlib import Path
from typing import Optional, Dict, Any, Tuple
import websockets
from PIL import Image, ImageStat
from obs_viewport import CaptureInvalid, ViewportGuard, SCENE, SOURCE, utc_now, write_json

logger = logging.getLogger("OBSController")

DEFAULT_OBS_HOST = "127.0.0.1"
DEFAULT_OBS_PORT = 4455
DEFAULT_SCENE_NAME = SCENE
DEFAULT_SOURCE_NAME = SCENE  # Public screenshots always use the final scene, not the raw window.
MAX_RECORDING_DURATION_SEC = 300  # 单次录制最长 5 分钟安全熔断


class OBSController:
    """OBS Studio WebSocket v5 控制器"""

    def __init__(self, host: str = DEFAULT_OBS_HOST, port: int = DEFAULT_OBS_PORT, password: Optional[str] = None, calibration_path=None):
        self.ws_url = f"ws://{host}:{port}"
        self.password = password if password is not None else os.environ.get('OBS_WEBSOCKET_PASSWORD')
        self.req_id_counter = 0
        self._record_start_time: Optional[float] = None
        self._last_record_file: Optional[str] = None
        self.guard = ViewportGuard(self, calibration_path)
        self._guard_stop = threading.Event()
        self._guard_thread = None
        self._record_error = None
        self._record_stats = None
        self._owns_recording = False
        self._expect_motion = False
        self._record_samples = []
        self._finalize_lock = threading.Lock()

    def _get_next_req_id(self) -> str:
        self.req_id_counter += 1
        return f"obs_req_{int(time.time() * 1000)}_{self.req_id_counter}"

    async def _send_request_async(self, request_type: str, request_data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """通过 WebSocket 执行单次 OBS 请求"""
        async with websockets.connect(self.ws_url, open_timeout=3.0, close_timeout=3.0, max_size=64 * 1024 * 1024) as ws:
            # 1. 接收 Hello 消息 (OpCode 0)
            hello_raw = await asyncio.wait_for(ws.recv(), timeout=5)
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
            auth = hello.get('d', {}).get('authentication')
            if auth:
                if not self.password:
                    raise RuntimeError('OBS 需要认证，请设置 OBS_WEBSOCKET_PASSWORD；密码不会写入校准记录。')
                secret = base64.b64encode(hashlib.sha256((self.password + auth['salt']).encode()).digest()).decode()
                identify_payload['d']['authentication'] = base64.b64encode(
                    hashlib.sha256((secret + auth['challenge']).encode()).digest()).decode()
            await ws.send(json.dumps(identify_payload))

            # 3. 接收 Identified (OpCode 2)
            identified_raw = await asyncio.wait_for(ws.recv(), timeout=5)
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
            resp_raw = await asyncio.wait_for(ws.recv(), timeout=5)
            resp = json.loads(resp_raw)
            if resp.get("op") != 7:
                raise RuntimeError(f"Unexpected response OpCode: {resp.get('op')}")

            d = resp.get("d", {})
            if d.get('requestId') != req_id:
                raise RuntimeError('OBS response requestId mismatch')
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
        兼容旧接口名称：只验证已校准窗口，不自动重绑。
        """
        # Compatibility name retained; capture must never silently reattach a window.
        self.guard.validate()
        return True

    def _scene_image(self, sample=False):
        args = {'sourceName': SCENE, 'imageFormat': 'png'}
        if sample:
            args['imageWidth'] = 256
        result = self.send_request('GetSourceScreenshot', args)
        return Image.open(io.BytesIO(base64.b64decode(result['imageData'].split(',', 1)[-1]))).convert('RGB')

    def _validate_image(self, image, data, sample=False):
        if not sample and list(image.size) != data['layout']['viewport'][2:]:
            raise CaptureInvalid('截图尺寸与已校准视口不符。')
        stats = ImageStat.Stat(image.resize((64, 64)))
        if max(stats.mean) < 2 or max(stats.stddev) < 0.5:
            raise CaptureInvalid('捕获画面为黑屏或近乎纯色，不能作为有效证据。')

    def calibration_preview(self, directory):
        data = self.guard.validate(require_review=False)
        directory = Path(directory).resolve()
        directory.mkdir(parents=True, exist_ok=True)
        image = self._scene_image()
        self._validate_image(image, data)
        image.save(directory / 'viewport.png')
        self.send_request('SaveSourceScreenshot', dict(sourceName=SOURCE, imageFormat='png',
                                                       imageFilePath=str(directory / 'window-reference.png')))
        return {'viewport': str(directory / 'viewport.png'), 'reference': str(directory / 'window-reference.png')}

    def approve_boundaries(self):
        data = self.guard.validate(require_review=False)
        self._validate_image(self._scene_image(), data)
        data.update(status='approved', boundary_reviewed_at=utc_now())
        write_json(self.guard.path, data)
        return data

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
        if source_name != SCENE or image_width or image_height:
            raise CaptureInvalid('准确采集仅允许最终视口场景的原始分辨率截图。')
        data = self.guard.validate()
        image = self._scene_image()
        try:
            self._validate_image(image, data)
        except CaptureInvalid as error:
            self.guard.invalidate(error)
            raise
        self.guard.validate()  # Discard the image if layout changed while OBS rendered it.
        captured_at = utc_now()
        if save_path:
            path = Path(save_path).resolve()
            path.parent.mkdir(parents=True, exist_ok=True)
            options = {} if image_format == 'png' or quality == -1 else {'quality': quality}
            image.save(path, format='JPEG' if image_format == 'jpg' else image_format.upper(), **options)
            result = dict(success=True, save_path=str(path), source_name=SCENE, format=image_format,
                          dimensions=list(image.size), captured_at=captured_at, calibration=str(self.guard.path))
            write_json(str(path) + '.json', result)
            return result
        buffer = io.BytesIO()
        image.save(buffer, format='JPEG' if image_format == 'jpg' else image_format.upper())
        encoded = base64.b64encode(buffer.getvalue()).decode()
        return dict(success=True, image_data=encoded, data_uri=f'data:image/{image_format};base64,{encoded}',
                    source_name=SCENE, format=image_format, dimensions=list(image.size), captured_at=captured_at)
    def start_record(self, expect_motion=False, max_duration_sec=MAX_RECORDING_DURATION_SEC) -> bool:
        """Start only a calibrated recording; a non-daemon watchdog remains alive until stop."""
        if self.get_record_status().get('outputActive'):
            raise CaptureInvalid('OBS 已有录像，不接管或停止其他录像。')
        data = self.guard.validate()
        self._validate_image(self._scene_image(), data)
        self._record_calibration = data
        self._record_stats = self.send_request('GetStats')
        self._record_error = None
        self._record_samples = []
        self._expect_motion = expect_motion
        self._max_duration = min(max_duration_sec, MAX_RECORDING_DURATION_SEC)
        if self._max_duration <= 0:
            raise ValueError('录像时长必须大于 0。')
        self.send_request('StartRecord')
        self._owns_recording = True
        deadline = time.monotonic() + 15
        while not self.get_record_status().get('outputActive'):
            if time.monotonic() >= deadline:
                self._record_error = 'OBS 启动录像超时，不能视为已开始采集。'
                raise CaptureInvalid(self._record_error)
            time.sleep(0.1)
        self._record_start_time = time.monotonic()
        self._guard_stop.clear()
        self._guard_thread = threading.Thread(target=self._watch_record, name='OBSViewportGuard', daemon=False)
        self._guard_thread.start()
        return True

    def _watch_record(self):
        try:
            while not self._guard_stop.wait(0.5):
                if time.monotonic() - self._record_start_time >= self._max_duration:
                    break
                data = self.guard.validate()
                image = self._scene_image(sample=True)
                self._validate_image(image, data, sample=True)
                self._record_samples.append(hashlib.sha256(image.resize((128, 80)).tobytes()).hexdigest())
                if self._expect_motion and len(self._record_samples) >= 6 and len(set(self._record_samples[-6:])) == 1:
                    raise CaptureInvalid('预期运动期间画面连续多次完全不变，疑似冻结。')
                if not self.get_record_status().get('outputActive'):
                    raise CaptureInvalid('录像被外部停止。')
        except Exception as error:
            self._record_error = str(error)
            try:
                self.guard.invalidate(error)
            except Exception:
                logger.exception('无法保存校准失效状态')
        finally:
            if not self._guard_stop.is_set():
                try:
                    self.stop_record()
                except Exception:
                    logger.exception('守卫停止录像失败')

    def stop_record(self, wait_finished=True, timeout_sec=10.0) -> str:
        self._guard_stop.set()
        if self._guard_thread and self._guard_thread is not threading.current_thread():
            self._guard_thread.join(timeout=20)
            if self._guard_thread.is_alive():
                self._record_error = '采集守卫未及时退出，录像无效。'
        with self._finalize_lock:
            return self._finish_record(wait_finished, timeout_sec)

    def _finish_record(self, wait_finished, timeout_sec):
        if not self._owns_recording:
            if self._record_error:
                raise CaptureInvalid(self._record_error)
            return self._last_record_file or ''
        # Re-check at stop to catch a layout change in the final sampling interval.
        try:
            self.guard.validate()
        except Exception as error:
            self._record_error = self._record_error or str(error)
        output_path = ''
        try:
            response = self.send_request('StopRecord')
            output_path = response.get('outputPath', '')
            self._last_record_file = output_path
            self._owns_recording = False
            deadline = time.monotonic() + timeout_sec
            while wait_finished and self.get_record_status().get('outputActive'):
                if time.monotonic() >= deadline:
                    raise CaptureInvalid('OBS 停止录像超时。')
                time.sleep(0.1)
            after = self.send_request('GetStats')
            stats = {key: after.get(key, 0) - self._record_stats.get(key, 0)
                     for key in ('renderSkippedFrames', 'renderTotalFrames', 'outputSkippedFrames', 'outputTotalFrames')}
            if stats['renderSkippedFrames'] > 0 or stats['outputSkippedFrames'] > 0:
                self._record_error = self._record_error or 'OBS 报告渲染/编码丢帧，连续性验收未通过。'
            if not output_path or not Path(output_path).is_file() or Path(output_path).stat().st_size == 0:
                self._record_error = self._record_error or '录像文件未正确落盘。'
            report = dict(status='invalid' if self._record_error else 'pending_video_review',
                          error=self._record_error, video=output_path, finished_at=utc_now(),
                          calibration=str(self.guard.path), stats_delta=stats,
                          calibration_snapshot=self._record_calibration,
                          sampled_frames=len(self._record_samples), distinct_samples=len(set(self._record_samples)),
                          expect_motion=self._expect_motion)
            write_json(self.guard.path.parent / 'last-recording.json', report)
            if output_path:
                write_json(output_path + '.json', report)
        except Exception as error:
            self._record_error = self._record_error or str(error)
            write_json(self.guard.path.parent / 'last-recording.json',
                       dict(status='invalid', error=self._record_error, video=output_path, finished_at=utc_now()))
            raise
        if self._record_error:
            raise CaptureInvalid(self._record_error)
        return output_path

    def get_record_status(self) -> Dict[str, Any]:
        return self.send_request('GetRecordStatus')

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

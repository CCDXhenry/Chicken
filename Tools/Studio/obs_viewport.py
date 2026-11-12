# Studio 视口校准与只读守卫：按物理像素识别客户端视口，布局变化后拒绝采集。
"""Windows-only, read-only Win32/UI Automation inspection; no Studio MCP required."""

import ctypes
from ctypes import wintypes as W
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CALIBRATION = ROOT / '.cache' / 'obs-viewport' / 'calibration.json'
SCENE = 'Chicken_Studio_Viewport'
SOURCE = 'Chicken_Studio_Window'


class CaptureInvalid(RuntimeError):
    """Evidence must not be accepted after this error."""


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
    temp.replace(path)


def inspect_studio(hwnd=None, project='开发者鸡'):
    """Identify an unambiguous Studio client and its native QEngineWidget rectangle."""
    if sys.platform != 'win32':
        raise CaptureInvalid('视口校准仅支持 Windows。')
    import comtypes
    import comtypes.client
    u = ctypes.windll.user32
    k = ctypes.windll.kernel32
    u.SetThreadDpiAwarenessContext.argtypes = [W.HANDLE]
    u.SetThreadDpiAwarenessContext.restype = W.HANDLE
    previous_dpi = u.SetThreadDpiAwarenessContext(W.HANDLE(-4))
    u.GetWindowRect.argtypes = [W.HWND, ctypes.POINTER(W.RECT)]
    u.GetClientRect.argtypes = [W.HWND, ctypes.POINTER(W.RECT)]
    u.ClientToScreen.argtypes = [W.HWND, ctypes.POINTER(W.POINT)]
    u.GetWindowThreadProcessId.argtypes = [W.HWND, ctypes.POINTER(W.DWORD)]
    u.GetWindowTextW.argtypes = [W.HWND, W.LPWSTR, ctypes.c_int]
    u.GetClassNameW.argtypes = [W.HWND, W.LPWSTR, ctypes.c_int]
    u.GetDpiForWindow.argtypes = [W.HWND]
    u.IsWindowVisible.argtypes = [W.HWND]
    u.IsIconic.argtypes = [W.HWND]
    u.IsChild.argtypes = [W.HWND, W.HWND]
    k.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
    k.OpenProcess.restype = W.HANDLE
    k.QueryFullProcessImageNameW.argtypes = [W.HANDLE, W.DWORD, W.LPWSTR, ctypes.POINTER(W.DWORD)]
    k.CloseHandle.argtypes = [W.HANDLE]

    def title(h):
        text = ctypes.create_unicode_buffer(2048)
        u.GetWindowTextW(h, text, len(text))
        return text.value

    def process(h):
        pid = W.DWORD()
        u.GetWindowThreadProcessId(h, ctypes.byref(pid))
        handle = k.OpenProcess(0x1000, False, pid.value)
        if not handle:
            return pid.value, ''
        try:
            buf = ctypes.create_unicode_buffer(32768)
            size = W.DWORD(len(buf))
            if not k.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size)):
                return pid.value, ''
            return pid.value, buf.value
        finally:
            k.CloseHandle(handle)

    def rect(h):
        r = W.RECT()
        if not u.GetWindowRect(h, ctypes.byref(r)):
            raise CaptureInvalid('窗口边界读取失败。')
        return [r.left, r.top, r.right, r.bottom]

    comtypes.CoInitialize()
    try:
        candidates = []
        same_title = []
        callback_type = ctypes.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)

        @callback_type
        def visit(h, _):
            if u.IsWindowVisible(h):
                name = title(h)
                if name.startswith(project + ' - ') and name.endswith('Roblox Studio'):
                    candidates.append(h)
                if hwnd and name == title(hwnd):
                    same_title.append(h)
            return True

        u.EnumWindows(visit, 0)
        if hwnd is None:
            candidates = [h for h in candidates if Path(process(h)[1]).name.lower() == 'robloxstudiobeta.exe']
            if len(candidates) != 1:
                raise CaptureInvalid(f'需要唯一的 {project} Studio 窗口，实际找到 {len(candidates)} 个。')
            hwnd = candidates[0]
            # Reject duplicate titles because OBS title matching is not process-specific.
            return inspect_studio(hwnd, project)
        if hwnd not in candidates or len(same_title) != 1 or u.IsIconic(hwnd):
            raise CaptureInvalid('目标窗口丢失、最小化、标题改变或存在重名窗口。')
        pid, executable = process(hwnd)
        if Path(executable).name.lower() != 'robloxstudiobeta.exe':
            raise CaptureInvalid('目标进程不是 RobloxStudioBeta.exe。')
        comtypes.client.GetModule('UIAutomationCore.dll')
        from comtypes.gen import UIAutomationClient as U
        automation = comtypes.client.CreateObject(U.CUIAutomation, interface=U.IUIAutomation)
        root = automation.ElementFromHandle(hwnd)
        engines = root.FindAll(U.TreeScope_Descendants,
                              automation.CreatePropertyCondition(U.UIA_AutomationIdPropertyId, 'QEngineWidget'))
        visible = [engines.GetElement(i) for i in range(engines.Length)
                   if not engines.GetElement(i).CurrentIsOffscreen]
        if len(visible) != 1:
            raise CaptureInvalid('无法唯一识别可见的 QEngineWidget 游戏视口。')
        engine = visible[0]
        viewport_hwnd = engine.CurrentNativeWindowHandle
        if not viewport_hwnd or not u.IsChild(hwnd, viewport_hwnd) or not u.IsWindowVisible(viewport_hwnd):
            raise CaptureInvalid('游戏视口原生窗口无效。')
        # The selected document tab must be a client, not server, edit viewport or script.
        tabs = root.FindAll(U.TreeScope_Descendants,
                           automation.CreatePropertyCondition(U.UIA_ControlTypePropertyId, U.UIA_TabControlTypeId))
        client_selected = False
        for i in range(tabs.Length):
            tab = tabs.GetElement(i)
            if tab.CurrentName not in ('客户端', 'Client') or tab.CurrentIsOffscreen:
                continue
            # Qt exposes the active document name on the tab control, but does not
            # expose SelectionItemPattern on its tab items in this Studio build.
            client_selected = True
        if not client_selected:
            raise CaptureInvalid('未选中 Play 客户端标签：请进入 Play 并显示客户端视口。')
        client = W.RECT()
        origin = W.POINT(0, 0)
        u.GetClientRect(hwnd, ctypes.byref(client))
        u.ClientToScreen(hwnd, ctypes.byref(origin))
        viewport = rect(viewport_hwnd)
        relative = [viewport[0] - origin.x, viewport[1] - origin.y,
                    viewport[2] - viewport[0], viewport[3] - viewport[1]]
        x, y, width, height = relative
        if min(width, height) < 64 or x < 0 or y < 0 or x + width > client.right or y + height > client.bottom:
            raise CaptureInvalid('游戏视口超出窗口客户区或尺寸无效。')
        cls = ctypes.create_unicode_buffer(256)
        u.GetClassNameW(hwnd, cls, len(cls))
        return dict(hwnd=hwnd, pid=pid, executable=executable, title=title(hwnd),
                    window_class=cls.value, dpi=u.GetDpiForWindow(hwnd),
                    client_size=[client.right, client.bottom], client_origin=[origin.x, origin.y],
                    window_rect=rect(hwnd), viewport_hwnd=viewport_hwnd, viewport=relative)
    finally:
        comtypes.CoUninitialize()
        u.SetThreadDpiAwarenessContext(previous_dpi)


def compare_layout(expected, current):
    for key in ('hwnd', 'pid', 'executable', 'title', 'window_class', 'dpi', 'client_size',
                'client_origin', 'window_rect', 'viewport_hwnd', 'viewport'):
        if expected[key] != current[key]:
            raise CaptureInvalid(f'校准失效：{key} 改变；请重新校准。')


def obs_window_pattern(layout):
    def encode(value):
        return value.replace('#', '#22').replace(':', '#3A')
    return ':'.join(encode(value) for value in
                    (layout['title'], layout['window_class'], Path(layout['executable']).name))


class ViewportGuard:
    def __init__(self, controller, calibration_path=None):
        self.obs = controller
        self.path = Path(calibration_path or DEFAULT_CALIBRATION)

    def load(self):
        if not self.path.exists():
            raise CaptureInvalid('尚未校准：先运行 obs_media_tool.py calibrate。')
        return json.loads(self.path.read_text(encoding='utf-8'))

    def invalidate(self, reason):
        data = self.load()
        data.update(status='invalid', invalid_reason=str(reason), invalidated_at=utc_now())
        write_json(self.path, data)

    def validate(self, require_review=True):
        data = self.load()
        if data['status'] not in (('approved',) if require_review else ('pending_review', 'approved')):
            raise CaptureInvalid(f"校准状态为 {data['status']}，需重新校准/核验边界。")
        try:
            compare_layout(data['layout'], inspect_studio(data['layout']['hwnd'], data['project']))
            self.validate_obs(data)
        except Exception as error:
            self.invalidate(error)
            raise CaptureInvalid(str(error)) from error
        return data

    def validate_obs(self, data):
        request = self.obs.send_request
        if request('GetCurrentProgramScene')['currentProgramSceneName'] != SCENE:
            raise CaptureInvalid('OBS 当前输出场景已改变。')
        video = request('GetVideoSettings')
        if video != data['video']:
            raise CaptureInvalid('OBS 画布、输出尺寸或帧率改变。')
        inputs = request('GetInputSettings', {'inputName': SOURCE})
        if inputs['inputKind'] != 'window_capture':
            raise CaptureInvalid('捕获源类型改变。')
        settings = inputs['inputSettings']
        for key, value in data['input_settings'].items():
            if settings.get(key) != value:
                raise CaptureInvalid(f'捕获源设置改变：{key}。')
        if request('GetSourceFilterList', {'sourceName': SOURCE})['filters']:
            raise CaptureInvalid('原始捕获源出现额外滤镜。')
        if request('GetSourceFilterList', {'sourceName': SCENE})['filters']:
            raise CaptureInvalid('输出场景出现额外滤镜。')
        items = request('GetSceneItemList', {'sceneName': SCENE})['sceneItems']
        if len(items) != 1 or items[0]['sourceName'] != SOURCE or not items[0]['sceneItemEnabled']:
            raise CaptureInvalid('场景内容、来源或可见性改变。')
        transform = request('GetSceneItemTransform', {'sceneName': SCENE, 'sceneItemId': items[0]['sceneItemId']})['sceneItemTransform']
        for key, value in data['transform'].items():
            if transform.get(key) != value:
                raise CaptureInvalid(f'场景裁剪或变换改变：{key}。')
        if [transform['sourceWidth'], transform['sourceHeight']] != data['layout']['client_size']:
            raise CaptureInvalid('OBS 原始捕获尺寸与校准客户区不符。')

    def calibrate(self, project='开发者鸡'):
        request = self.obs.send_request
        try:
            replay_active = request('GetReplayBufferStatus')['outputActive']
        except RuntimeError as error:
            if 'code 604' not in str(error):
                raise
            replay_active = False
        if request('GetRecordStatus')['outputActive'] or request('GetStreamStatus')['outputActive'] or request('GetVirtualCamStatus')['outputActive'] or replay_active:
            raise CaptureInvalid('先停止 OBS 当前录像、直播、虚拟摄像头和回放缓冲，再校准。')
        layout = inspect_studio(project=project)
        x, y, width, height = layout['viewport']
        if width % 2 or height % 2:
            raise CaptureInvalid('视口像素宽高须为偶数以兼容当前录像编码器；请微调固定布局后重新校准，禁止裁掉一列/行凑数。')
        transitions = request('GetSceneTransitionList')['transitions']
        cuts = [t for t in transitions if t['transitionKind'] == 'cut_transition']
        if not cuts:
            raise CaptureInvalid('OBS 缺少直接切换转场。')
        self.path.parent.mkdir(parents=True, exist_ok=True)
        scene_list = request('GetSceneList')
        scene_items = {s['sceneName']: request('GetSceneItemList', {'sceneName': s['sceneName']})
                       for s in scene_list['scenes']}
        input_list = request('GetInputList')
        write_json(self.path.parent / ('backup-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.json'),
                   dict(video=request('GetVideoSettings'), scene=request('GetCurrentProgramScene'),
                        scenes=scene_list, scene_items=scene_items, inputs=input_list,
                        transition=request('GetCurrentSceneTransition'),
                        input_settings={i['inputName']: request('GetInputSettings', {'inputName': i['inputName']})
                                        for i in input_list['inputs'] if i['inputKind'] == 'window_capture'}))
        scenes = scene_list['scenes']
        if SCENE not in [s['sceneName'] for s in scenes]:
            request('CreateScene', {'sceneName': SCENE})
        settings = dict(window=obs_window_pattern(layout), priority=0, method=2,
                        client_area=True, cursor=False, force_sdr=True)
        if SOURCE not in [i['inputName'] for i in request('GetInputList')['inputs']]:
            request('CreateInput', dict(sceneName=SCENE, inputName=SOURCE, inputKind='window_capture', inputSettings=settings, sceneItemEnabled=True))
        else:
            request('SetInputSettings', dict(inputName=SOURCE, inputSettings=settings, overlay=False))
        items = request('GetSceneItemList', {'sceneName': SCENE})['sceneItems']
        if len(items) != 1 or items[0]['sourceName'] != SOURCE:
            raise CaptureInvalid('专用场景存在额外内容，请人工检查；不会删除已有场景内容。')
        item_id = items[0]['sceneItemId']
        transform = dict(positionX=0.0, positionY=0.0, rotation=0.0, scaleX=1.0, scaleY=1.0,
                         alignment=5, boundsType='OBS_BOUNDS_NONE', cropToBounds=False,
                         cropLeft=x, cropTop=y, cropRight=layout['client_size'][0]-x-width,
                         cropBottom=layout['client_size'][1]-y-height)
        request('SetSceneItemTransform', dict(sceneName=SCENE, sceneItemId=item_id, sceneItemTransform=transform))
        request('SetSceneItemEnabled', dict(sceneName=SCENE, sceneItemId=item_id, sceneItemEnabled=True))
        request('SetSceneItemLocked', dict(sceneName=SCENE, sceneItemId=item_id, sceneItemLocked=True))
        request('SetCurrentSceneTransition', {'transitionName': cuts[0]['transitionName']})
        request('SetCurrentProgramScene', {'sceneName': SCENE})
        request('SetVideoSettings', dict(baseWidth=width, baseHeight=height, outputWidth=width,
                                         outputHeight=height, fpsNumerator=60, fpsDenominator=1))
        # Changing the base canvas makes OBS rescale existing scene items. Reapply
        # the physical-pixel transform after the video reset, never before it only.
        request('SetSceneItemTransform', dict(sceneName=SCENE, sceneItemId=item_id, sceneItemTransform=transform))
        # Canvas reset also rescales other scenes; preserve their original transforms.
        for scene_name, original in scene_items.items():
            if scene_name == SCENE:
                continue
            for item in original['sceneItems']:
                original_transform = item['sceneItemTransform']
                writable = {key: original_transform[key] for key in
                            ('positionX', 'positionY', 'rotation', 'scaleX', 'scaleY', 'alignment',
                             'boundsType', 'boundsAlignment', 'boundsWidth', 'boundsHeight',
                             'cropLeft', 'cropTop', 'cropRight', 'cropBottom', 'cropToBounds')}
                request('SetSceneItemTransform', dict(sceneName=scene_name, sceneItemId=item['sceneItemId'],
                                                     sceneItemTransform=writable))
        import time
        time.sleep(1.2)  # WGC must have delivered frames before the dimensions are checked.
        data = dict(version=1, status='pending_review', calibrated_at=utc_now(), project=project,
                    scene=SCENE, source=SOURCE, layout=layout, input_settings=settings,
                    transform=transform, video=request('GetVideoSettings'))
        write_json(self.path, data)
        self.validate(require_review=False)
        return data

# OBS 采集回归：验证失效拒绝、错误传播与录像所有权；实机测试需显式开启。
import copy
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

from PIL import Image
from obs_controller import OBSController
from obs_studio_bridge import RobloxMediaBridge, RobloxRecordSession
from obs_viewport import CaptureInvalid, ViewportGuard, compare_layout, obs_window_pattern, write_json


class TestCaptureSafety(unittest.TestCase):
    def test_every_layout_change_invalidates(self):
        keys = ('hwnd', 'pid', 'executable', 'title', 'window_class', 'dpi', 'client_size',
                'client_origin', 'window_rect', 'viewport_hwnd', 'viewport')
        expected = dict.fromkeys(keys, 'original')
        for key in keys:
            with self.subTest(key=key):
                actual = dict(expected, **{key: 'changed'})
                with self.assertRaises(CaptureInvalid):
                    compare_layout(expected, actual)
        compare_layout(expected, expected)

    def test_window_pattern_escapes_obs_delimiters(self):
        self.assertEqual(obs_window_pattern(dict(title='Chicken:#1', window_class='Qt', executable='RobloxStudioBeta.exe')),
                         'Chicken#3A#221:Qt:RobloxStudioBeta.exe')

    def test_layout_failure_is_sticky_until_recalibration(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'calibration.json'
            write_json(path, dict(status='approved', layout={'hwnd': 123}, project='Chicken'))
            guard = ViewportGuard(Mock(), path)
            with patch('obs_viewport.inspect_studio', side_effect=CaptureInvalid('window gone')):
                with self.assertRaises(CaptureInvalid):
                    guard.validate()
            self.assertEqual(guard.load()['status'], 'invalid')
            with patch('obs_viewport.inspect_studio') as inspect:
                with self.assertRaises(CaptureInvalid):
                    guard.validate()
                inspect.assert_not_called()

    def test_pending_boundary_review_blocks_capture(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'calibration.json'
            write_json(path, dict(status='pending_review'))
            guard = ViewportGuard(Mock(), path)
            with self.assertRaises(CaptureInvalid):
                guard.validate()

    def test_wrong_scene_stops_obs_validation(self):
        obs = Mock()
        obs.send_request.return_value = {'currentProgramSceneName': 'Other'}
        with self.assertRaises(CaptureInvalid):
            ViewportGuard(obs).validate_obs({})

    def test_screenshot_rejects_black_or_wrong_size(self):
        obs = OBSController()
        data = {'layout': {'viewport': [0, 0, 100, 80]}}
        with self.assertRaises(CaptureInvalid):
            obs._validate_image(Image.new('RGB', (100, 80)), data)
        with self.assertRaises(CaptureInvalid):
            obs._validate_image(Image.new('RGB', (80, 80), 'red'), data)

    def test_layout_change_during_screenshot_does_not_write_file(self):
        obs = OBSController()
        obs.guard = Mock()
        obs.guard.validate.side_effect = [{'layout': {'viewport': [0, 0, 100, 80]}}, CaptureInvalid('resized')]
        image = Image.new('RGB', (100, 80), 'red')
        image.paste('blue', (0, 0, 50, 40))
        obs._scene_image = Mock(return_value=image)
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'capture.png'
            with self.assertRaises(CaptureInvalid):
                obs.take_screenshot(save_path=str(path))
            self.assertFalse(path.exists())

    def test_obs_failure_never_falls_back_to_mcp(self):
        obs = Mock()
        obs.take_screenshot.side_effect = CaptureInvalid('invalid capture')
        native = Mock()
        with self.assertRaises(CaptureInvalid):
            RobloxMediaBridge(native, obs).capture_screenshot()
        native.call_tool.assert_not_called()

    def test_does_not_take_over_existing_recording(self):
        obs = OBSController()
        obs.get_record_status = Mock(return_value={'outputActive': True})
        obs.send_request = Mock()
        with self.assertRaises(CaptureInvalid):
            obs.start_record()
        obs.send_request.assert_not_called()
        obs.stop_record()
        obs.send_request.assert_not_called()

    def test_watchdog_stops_owned_recording_after_layout_failure(self):
        obs = OBSController()
        obs._owns_recording = True
        obs._record_start_time = time.monotonic()
        obs._max_duration = 300
        obs._guard_stop = Mock()
        obs._guard_stop.wait.return_value = False
        obs._guard_stop.is_set.return_value = False
        obs.guard = Mock()
        obs.guard.validate.side_effect = CaptureInvalid('Play stopped or viewport changed')
        obs.stop_record = Mock()
        obs._watch_record()
        obs.stop_record.assert_called_once()
        obs.guard.invalidate.assert_called_once()
        self.assertIn('Play stopped', obs._record_error)

    def test_odd_viewport_fails_before_obs_configuration_changes(self):
        obs = Mock()
        def request(kind, args=None):
            return {'outputActive': False}
        obs.send_request.side_effect = request
        guard = ViewportGuard(obs)
        with patch('obs_viewport.inspect_studio', return_value={'viewport': [0, 0, 101, 80]}):
            with self.assertRaises(CaptureInvalid):
                guard.calibrate()
        self.assertFalse(any(call.args[0].startswith(('Set', 'Create', 'Remove'))
                             for call in obs.send_request.call_args_list))

    def test_session_start_and_stop_errors_propagate(self):
        obs = Mock()
        obs.start_record.side_effect = CaptureInvalid('bad calibration')
        with self.assertRaises(CaptureInvalid):
            with RobloxRecordSession(obs_controller=obs):
                self.fail('should not enter')
        obs.start_record.side_effect = None
        obs.stop_record.side_effect = CaptureInvalid('bad video')
        with self.assertRaises(CaptureInvalid):
            with RobloxRecordSession(obs_controller=obs):
                pass


@unittest.skipUnless(os.environ.get('OBS_LIVE_TESTS') == '1', 'Set OBS_LIVE_TESTS=1 after Play calibration/review')
class TestOBSIntegration(unittest.TestCase):
    def test_live_scene_screenshot_and_guarded_recording(self):
        obs = OBSController()
        obs.guard.validate()
        with tempfile.TemporaryDirectory() as temp:
            result = obs.take_screenshot(save_path=str(Path(temp) / 'viewport.png'))
            self.assertEqual(result['dimensions'], obs.guard.load()['layout']['viewport'][2:])
        with RobloxRecordSession(max_duration_sec=4, obs_controller=obs) as session:
            import time
            time.sleep(2)
        self.assertTrue(Path(session.video_output_path).is_file())


if __name__ == '__main__':
    unittest.main()

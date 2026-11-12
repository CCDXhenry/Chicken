# OBS 视口采集命令行：校准、边界复核、原尺寸截图与受守卫录像。
"""All successful capture commands require an approved, unchanged Play viewport."""
import argparse
import json
from pathlib import Path
import sys
import time

from obs_controller import OBSController, DEFAULT_SOURCE_NAME
from obs_viewport import CaptureInvalid, DEFAULT_CALIBRATION
from websockets.exceptions import WebSocketException


def main():
    parser = argparse.ArgumentParser(description='OBS Studio 准确视口采集')
    parser.add_argument('--calibration', default=str(DEFAULT_CALIBRATION))
    sub = parser.add_subparsers(dest='command', required=True)
    cal = sub.add_parser('calibrate', help='识别当前 Play 客户端并生成边界预览，等待复核')
    cal.add_argument('--project', default='开发者鸡')
    cal.add_argument('--preview-dir', default='.cache/obs-viewport/acceptance')
    sub.add_parser('approve', help='查看预览并确认四边完整后，批准当前校准')
    sub.add_parser('check', help='只读验证校准；无效时返回非零退出码')
    shot = sub.add_parser('screenshot')
    shot.add_argument('--save')
    shot.add_argument('--source', default=DEFAULT_SOURCE_NAME)
    shot.add_argument('--width', type=int, default=0, help='准确采集不允许缩放；保留参数以明确拒绝旧调用')
    shot.add_argument('--format', default='png', choices=['png', 'jpg', 'webp'])
    shot.add_argument('--quality', type=int, default=-1)
    rec = sub.add_parser('record')
    rec.add_argument('action', choices=['start', 'status', 'chapter'])
    rec.add_argument('--duration', type=float, default=10, help='本命令持续守卫并自动停止，最大 300 秒')
    rec.add_argument('--expect-motion', action='store_true')
    rec.add_argument('--name', default='Mark')
    args = parser.parse_args()
    controller = OBSController(calibration_path=args.calibration)
    try:
        if args.command == 'calibrate':
            controller.guard.calibrate(args.project)
            result = controller.calibration_preview(args.preview_dir)
            result['status'] = 'pending_boundary_review'
        elif args.command == 'approve':
            result = controller.approve_boundaries()
        elif args.command == 'check':
            result = controller.guard.validate()
        elif args.command == 'screenshot':
            path = args.save or str(Path('.cache/obs-viewport') / f'capture_{time.time_ns()}.{args.format}')
            result = controller.take_screenshot(source_name=args.source, save_path=path,
                                                image_format=args.format, image_width=args.width or None, quality=args.quality)
        elif args.action == 'status':
            result = controller.get_record_status()
        elif args.action == 'chapter':
            controller.guard.validate()
            result = {'marked': controller.create_record_chapter(args.name)}
        else:
            controller.start_record(expect_motion=args.expect_motion, max_duration_sec=args.duration)
            print(json.dumps({'status': 'recording', 'duration_limit': min(args.duration, 300)}), flush=True)
            try:
                deadline = time.monotonic() + min(args.duration, 300)
                while time.monotonic() < deadline and not controller._guard_stop.wait(0.2):
                    pass
            finally:
                result = {'video': controller.stop_record(), 'status': 'pending_video_review'}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (CaptureInvalid, RuntimeError, OSError, ValueError, WebSocketException) as error:
        print(json.dumps({'status': 'invalid', 'error': str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())

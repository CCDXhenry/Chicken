# OBS 录像文件核验：完整解码、尺寸帧率核对与首中尾关键帧导出。
import argparse
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import cv2
from obs_viewport import CaptureInvalid, write_json, utc_now


def verify_video(video, output_dir):
    video = Path(video).resolve()
    report_path = Path(str(video) + '.json')
    report = json.loads(report_path.read_text(encoding='utf-8'))
    if report['status'] == 'invalid':
        raise CaptureInvalid(f"录像守卫未通过：{report.get('error')}")
    calibration = report.get('calibration_snapshot') or json.loads(Path(report['calibration']).read_text(encoding='utf-8'))
    output_dir = Path(output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    meta = json.loads(subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
                                     '-show_entries', 'stream=width,height,avg_frame_rate,nb_frames:format=duration',
                                     '-of', 'json', str(video)], check=True, capture_output=True, text=True).stdout)
    stream = meta['streams'][0]
    if [stream['width'], stream['height']] != calibration['layout']['viewport'][2:] or Fraction(stream['avg_frame_rate']) != 60:
        raise CaptureInvalid('录像尺寸或帧率不符合校准。')
    decode = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(video), '-map', '0:v:0', '-f', 'null', '-'],
                            capture_output=True, text=True, timeout=180)
    if decode.returncode or decode.stderr.strip():
        raise CaptureInvalid('录像完整解码失败：' + decode.stderr[-1000:])
    cap = cv2.VideoCapture(str(video))
    count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if count < 3:
        raise CaptureInvalid('录像帧数不足。')
    hashes = []
    frames = []
    try:
        for label, index in [('head', min(6, count-1)), ('middle', count//2), ('tail', max(0, count-7))]:
            cap.set(cv2.CAP_PROP_POS_FRAMES, index)
            ok, frame = cap.read()
            if not ok or frame.max() < 3 or frame.std() < 0.5:
                raise CaptureInvalid(f'{label} 关键帧不可用或黑屏。')
            path = output_dir / f'{label}.png'
            # imwrite does not reliably accept Unicode Windows paths.
            path.write_bytes(cv2.imencode('.png', frame)[1].tobytes())
            hashes.append(hashlib.sha256(cv2.resize(frame, (128, 80)).tobytes()).hexdigest())
            frames.append(dict(position=label, frame=index, image=str(path)))
    finally:
        cap.release()
    if report.get('expect_motion') and len(set(hashes)) < 3:
        raise CaptureInvalid('预期运动的录像首中尾画面未全部变化。')
    report.update(status='pending_visual_review', decoded_at=utc_now(), metadata=meta,
                  decoded_frames=count, keyframes=frames)
    write_json(report_path, report)
    write_json(output_dir / 'video-verification.json', report)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('video')
    parser.add_argument('--output-dir', default='.cache/obs-viewport/acceptance/video')
    args = parser.parse_args()
    try:
        print(json.dumps(verify_video(args.video, args.output_dir), ensure_ascii=False, indent=2))
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)

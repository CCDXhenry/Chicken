"""
OBS Media CLI Tool
为开发者与 Agent 提供针对 Roblox Studio 视口的快捷多媒体命令行工具。
用法:
  python Tools/Studio/obs_media_tool.py screenshot [--save PATH] [--source NAME] [--width W]
  python Tools/Studio/obs_media_tool.py record start
  python Tools/Studio/obs_media_tool.py record stop
  python Tools/Studio/obs_media_tool.py record status
  python Tools/Studio/obs_media_tool.py record chapter <chapter_name>
  python Tools/Studio/obs_media_tool.py check
"""

import argparse
import os
import sys
import json

from obs_controller import OBSController, DEFAULT_SOURCE_NAME


def handle_screenshot(args, controller: OBSController):
    save_path = args.save
    if not save_path:
        default_dir = os.path.join("Assets", "Studio")
        os.makedirs(default_dir, exist_ok=True)
        save_path = os.path.join(default_dir, f"capture_{int(os.times().system * 1000)}.png")

    source = args.source or DEFAULT_SOURCE_NAME
    width = args.width if args.width > 0 else None

    print(f"[CLI] 正在对源【{source}】执行截屏...")
    res = controller.take_screenshot(
        source_name=source,
        save_path=save_path,
        image_format=args.format,
        image_width=width,
        quality=args.quality
    )
    if res.get("success"):
        print(f"[CLI] 截屏成功！文件已保存至: {res.get('save_path')}")
        file_size = os.path.getsize(res.get('save_path'))
        print(f"[CLI] 图像尺寸/大小: {file_size / 1024:.1f} KB")
    else:
        print(f"[CLI] 截屏失败: {res}")


def handle_record(args, controller: OBSController):
    action = args.action.lower()
    if action == "start":
        controller.ensure_roblox_window_attached()
        controller.start_record()
        print(f"[CLI] 已发送开始录制指令。当前状态: 录制中")
        status = controller.get_record_status()
        print(f"[CLI] 录制状态: Active={status.get('outputActive')}, Timecode={status.get('outputTimecode')}")

    elif action == "stop":
        video_path = controller.stop_record()
        if video_path:
            print(f"[CLI] 已停止录制！视频输出路径: {video_path}")
            if os.path.exists(video_path):
                size_mb = os.path.getsize(video_path) / (1024 * 1024)
                print(f"[CLI] 文件大小: {size_mb:.2f} MB")
        else:
            print(f"[CLI] 当前未处于录制状态或未获取到输出路径。")

    elif action == "status":
        status = controller.get_record_status()
        print("[CLI] OBS 录制状态:")
        print(f"  - 正在录制: {status.get('outputActive')}")
        print(f"  - 已暂停:   {status.get('outputPaused')}")
        print(f"  - 录制时间: {status.get('outputTimecode')}")
        print(f"  - 写入字节: {status.get('outputBytes', 0) / 1024 / 1024:.2f} MB")

    elif action == "pause":
        paused = controller.toggle_record_pause()
        print(f"[CLI] 录像已{'暂停' if paused else '恢复'}。")

    elif action == "chapter":
        cname = args.name or "Mark"
        controller.create_record_chapter(cname)
        print(f"[CLI] 已在录像中标记章节: 【{cname}】")
    else:
        print(f"[CLI] 未知录像指令: {action}")


def handle_check(args, controller: OBSController):
    connected = controller.is_connected()
    print("================ OBS 服务状态体检 ================")
    print(f"1. WebSocket (127.0.0.1:4455): {'[在线]' if connected else '[离线]'}")
    if not connected:
        print("   -> 请确认 OBS 已启动，并已在【工具 -> obs-websocket 设置】中开启 WebSocket 服务（端口 4455）。")
        return

    info = controller.get_obs_info()
    print(f"2. OBS Studio 版本:           v{info.get('obsVersion')}")
    print(f"3. obs-websocket 协议版本:    v{info.get('obsWebSocketVersion')}")
    print(f"4. 默认录像目录:              {controller.get_record_directory()}")

    attached = controller.ensure_roblox_window_attached()
    active_win = controller.find_active_roblox_window()
    print(f"5. Roblox Studio 活跃窗口:    {active_win or '未检测到活跃窗口'}")
    print(f"6. 窗口源自动绑定状态:        {'已成功绑定最新窗口' if attached else '保持默认/需开启 Studio'}")
    print("==================================================")


def main():
    parser = argparse.ArgumentParser(description="OBS Media CLI for Roblox Studio")
    subparsers = parser.add_subparsers(dest="command", help="子命令")

    # 截屏命令
    p_shot = subparsers.add_parser("screenshot", help="截取 Roblox Studio 视口画面")
    p_shot.add_argument("--save", type=str, help="图片保存路径")
    p_shot.add_argument("--source", type=str, default=DEFAULT_SOURCE_NAME, help="OBS 捕获来源名称")
    p_shot.add_argument("--width", type=int, default=0, help="目标图像宽度")
    p_shot.add_argument("--format", type=str, default="png", choices=["png", "jpg", "webp"], help="图像格式")
    p_shot.add_argument("--quality", type=int, default=-1, help="图像压缩质量 (1-100)")

    # 录制命令
    p_rec = subparsers.add_parser("record", help="控制 OBS 录制生命周期")
    p_rec.add_argument("action", choices=["start", "stop", "status", "pause", "chapter"], help="录制动作")
    p_rec.add_argument("--name", type=str, default="", help="章节标记名称")

    # 体检命令
    subparsers.add_parser("check", help="检查 OBS 连通性与 Studio 窗口捕获状态")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)

    controller = OBSController()

    if args.command == "check":
        handle_check(args, controller)
    elif args.command == "screenshot":
        handle_screenshot(args, controller)
    elif args.command == "record":
        handle_record(args, controller)


if __name__ == "__main__":
    main()

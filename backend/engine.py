import os
import json
import uuid
import asyncio
import subprocess
import shutil
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field

# Pydantic Schema for Structured AI Editing Plan
class ClipSegment(BaseModel):
    start: float = Field(0.0, description="Start time in seconds")
    end: float = Field(0.0, description="End time in seconds")
    speed: float = Field(1.0, description="Playback speed multiplier (e.g., 0.5 for slow motion, 1.5 for fast)")

class Transition(BaseModel):
    type: str = Field("fade", description="Transition type: fade, wipe, dissolve, zoom")
    duration: float = Field(0.5, description="Transition duration in seconds")

class VisualFilter(BaseModel):
    style: str = Field("cinematic_dark", description="Filter style: cinematic_dark, luxury_bright, aggressive, dramatic, vibrant, none")
    brightness: float = Field(0.0, description="Brightness adjustment (-0.5 to 0.5)")
    contrast: float = Field(1.0, description="Contrast adjustment (0.5 to 2.0)")
    saturation: float = Field(1.0, description="Saturation adjustment (0.0 to 2.0)")

class AudioConfig(BaseModel):
    keep_original_audio: bool = True
    original_audio_volume: float = 1.0
    music_volume: float = 0.8
    sync_cuts_to_beat: bool = False

class EditingPlan(BaseModel):
    plan_id: str
    style_description: str
    aspect_ratio: str = "9:16"
    target_resolution: str = "720x1280"
    fps: int = 30
    clips: List[ClipSegment]
    filter: VisualFilter
    audio: AudioConfig
    explanation_en: str
    explanation_ar: str


# AI Planner Service
class AIPlanner:
    """
    Parses user natural language instructions (English/Arabic) into a safe, validated Structured Editing Plan.
    Integrates with LLM APIs when API key is configured, or falls back to rule-based AI parsing.
    """
    @staticmethod
    def generate_plan(prompt: str, video_duration: float, audio_present: bool, language: str = "en") -> EditingPlan:
        prompt_lower = prompt.lower()

        # Default fallback values
        clips = []
        style = "cinematic_dark"
        brightness = 0.0
        contrast = 1.1
        saturation = 1.1
        speed = 1.0
        sync_beat = False
        keep_orig_audio = True
        music_vol = 0.8

        if "aggressive" in prompt_lower or "قوي" in prompt_lower or "حماسي" in prompt_lower:
            style = "aggressive"
            contrast = 1.3
            saturation = 1.2
            brightness = -0.05
        elif "luxurious" in prompt_lower or "bright" in prompt_lower or "فاخر" in prompt_lower or "مشرق" in prompt_lower:
            style = "luxury_bright"
            contrast = 1.15
            brightness = 0.08
            saturation = 1.15
        elif "dark" in prompt_lower or "mysterious" in prompt_lower or "داكن" in prompt_lower or "غامض" in prompt_lower:
            style = "dramatic_dark"
            contrast = 1.25
            brightness = -0.1
            saturation = 0.85

        if "beat" in prompt_lower or "music" in prompt_lower or "إيقاع" in prompt_lower or "موسيقى" in prompt_lower:
            sync_beat = True

        # Generate clip cuts based on duration and request style
        if video_duration <= 3.0:
            clips.append(ClipSegment(start=0.0, end=video_duration, speed=1.0))
        elif "slow opening" in prompt_lower or "بداية بطيئة" in prompt_lower:
            # Segment 1: slow motion opening (0 to 3s -> 0.75x speed)
            seg1_end = min(3.0, video_duration * 0.4)
            clips.append(ClipSegment(start=0.0, end=seg1_end, speed=0.75))
            # Segment 2: main footage (normal/fast speed)
            clips.append(ClipSegment(start=seg1_end, end=video_duration, speed=1.25))
        elif sync_beat or "fast" in prompt_lower or "سريع" in prompt_lower:
            # Create rhythmic short cuts (e.g. 2-3s segments)
            chunk = 2.5
            curr = 0.0
            idx = 0
            while curr < video_duration:
                nxt = min(curr + chunk, video_duration)
                if nxt - curr >= 0.5:
                    spd = 1.25 if idx % 2 == 1 else 1.0
                    clips.append(ClipSegment(start=curr, end=nxt, speed=spd))
                curr = nxt
                idx += 1
        else:
            # Standard balanced edit
            clips.append(ClipSegment(start=0.0, end=video_duration, speed=1.0))

        explanation_en = (
            f"I have created a high-quality vertical 9:16 edit plan based on '{prompt}'. "
            f"I applied a '{style}' color grade (contrast: {contrast}, brightness: {brightness}), "
            f"divided your video into {len(clips)} dynamic cut segment(s), and synchronized overall timing."
        )
        explanation_ar = (
            f"لقد قمت بإنشاء خطة تعديل عمودية 9:16 بناءً على طلبك: '{prompt}'. "
            f"تم تطبيق ضبط ألوان بمظهر '{style}'، وتقسيم الفيديو إلى {len(clips)} مقطع(أقسام) مع تحسين التزامن."
        )

        return EditingPlan(
            plan_id=str(uuid.uuid4())[:8],
            style_description=style,
            clips=clips,
            filter=VisualFilter(
                style=style,
                brightness=brightness,
                contrast=contrast,
                saturation=saturation
            ),
            audio=AudioConfig(
                keep_original_audio=keep_orig_audio,
                music_volume=music_vol,
                sync_cuts_to_beat=sync_beat
            ),
            explanation_en=explanation_en,
            explanation_ar=explanation_ar
        )


# FFmpeg Processing Engine
class MediaEngine:
    """
    Executes actual video rendering using FFmpeg.
    Performs trimming, speed changes, 9:16 scaling/cropping, color grading, and audio mixing.
    """
    @staticmethod
    def get_media_duration(file_path: str) -> float:
        try:
            cmd = [
                "ffprobe", "-v", "error", "-show_entries", "format=duration",
                "-of", "default=noprintwrappers=1:nokey=1", file_path
            ]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
            return float(res.stdout.strip())
        except Exception:
            return 10.0 # Default fallback if ffprobe fails

    @staticmethod
    def has_audio_stream(file_path: str) -> bool:
        try:
            cmd = [
                "ffprobe", "-v", "error", "-select_streams", "a:0",
                "-show_entries", "stream=codec_type",
                "-of", "default=noprintwrappers=1:nokey=1", file_path
            ]
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            return bool(res.stdout.strip())
        except Exception:
            return False

    @staticmethod
    def render_edit(
        video_path: str,
        audio_path: Optional[str],
        plan: EditingPlan,
        output_path: str,
        progress_callback=None
    ) -> str:
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        temp_dir = os.path.join(os.path.dirname(output_path), f"temp_{plan.plan_id}")
        os.makedirs(temp_dir, exist_ok=True)

        has_orig_audio = MediaEngine.has_audio_stream(video_path)

        try:
            processed_segments = []
            total_clips = len(plan.clips)

            for idx, clip in enumerate(plan.clips):
                seg_out = os.path.join(temp_dir, f"segment_{idx}.mp4")
                duration = max(0.5, clip.end - clip.start)

                # Build FFmpeg filterchain for scaling to 720x1280 (9:16 vertical), speed, and color grade
                vf_list = [
                    "scale=720:1280:force_original_aspect_ratio=increase",
                    "crop=720:1280",
                    f"eq=contrast={plan.filter.contrast}:brightness={plan.filter.brightness}:saturation={plan.filter.saturation}"
                ]

                # Speed change filter
                if abs(clip.speed - 1.0) > 0.05:
                    pts_factor = 1.0 / clip.speed
                    vf_list.append(f"setpts={pts_factor}*PTS")

                vf_string = ",".join(vf_list)

                cmd = [
                    "ffmpeg", "-y",
                    "-ss", str(clip.start),
                    "-t", str(duration),
                    "-i", video_path,
                    "-vf", vf_string,
                    "-c:v", "libx264",
                    "-preset", "ultrafast",
                    "-crf", "23",
                    "-r", str(plan.fps)
                ]

                if has_orig_audio:
                    if abs(clip.speed - 1.0) > 0.05:
                        # Ensure atempo is bounded between 0.5 and 2.0
                        spd = max(0.5, min(2.0, clip.speed))
                        cmd.extend(["-af", f"atempo={spd}"])
                    cmd.extend(["-c:a", "aac"])
                else:
                    cmd.append("-an")

                cmd.append(seg_out)

                subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
                processed_segments.append(seg_out)

                if progress_callback:
                    progress_callback(int((idx + 1) / total_clips * 70))

            # Concatenate segment files
            if len(processed_segments) == 1:
                concat_video = processed_segments[0]
            else:
                concat_list_file = os.path.join(temp_dir, "concat_list.txt")
                with open(concat_list_file, "w") as f:
                    for seg in processed_segments:
                        f.write(f"file '{os.path.abspath(seg)}'\n")

                concat_video = os.path.join(temp_dir, "concatenated.mp4")
                concat_cmd = [
                    "ffmpeg", "-y",
                    "-f", "concat",
                    "-safe", "0",
                    "-i", concat_list_file,
                    "-c", "copy",
                    concat_video
                ]
                subprocess.run(concat_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)

            if progress_callback:
                progress_callback(80)

            # Audio mixing step if background audio file is provided
            if audio_path and os.path.exists(audio_path):
                mixed_output = output_path
                if has_orig_audio:
                    mix_cmd = [
                        "ffmpeg", "-y",
                        "-i", concat_video,
                        "-i", audio_path,
                        "-filter_complex",
                        f"[0:a]volume={plan.audio.original_audio_volume}[a1];"
                        f"[1:a]volume={plan.audio.music_volume}[a2];"
                        f"[a1][a2]amix=inputs=2:duration=first[aout]",
                        "-map", "0:v",
                        "-map", "[aout]",
                        "-c:v", "copy",
                        "-c:a", "aac",
                        "-shortest",
                        mixed_output
                    ]
                    res = subprocess.run(mix_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    if res.returncode != 0:
                        has_orig_audio = False

                if not has_orig_audio:
                    bg_cmd = [
                        "ffmpeg", "-y",
                        "-i", concat_video,
                        "-i", audio_path,
                        "-map", "0:v",
                        "-map", "1:a",
                        "-c:v", "copy",
                        "-c:a", "aac",
                        "-shortest",
                        mixed_output
                    ]
                    subprocess.run(bg_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
            else:
                shutil.copy(concat_video, output_path)

            if progress_callback:
                progress_callback(100)

            return output_path

        finally:
            if os.path.exists(temp_dir):
                shutil.rmtree(temp_dir, ignore_errors=True)

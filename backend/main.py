import os
import uuid
import asyncio
from typing import Dict, Any, Optional
from fastapi import FastAPI, UploadFile, File, Form, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .engine import AIPlanner, MediaEngine, EditingPlan

app = FastAPI(title="AI Video Editing Backend", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Directories
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOADS_DIR = os.path.join(BASE_DIR, "uploads")
OUTPUTS_DIR = os.path.join(BASE_DIR, "outputs")

os.makedirs(UPLOADS_DIR, exist_ok=True)
os.makedirs(OUTPUTS_DIR, exist_ok=True)

# Static file serving for rendered output videos
app.mount("/static/outputs", StaticFiles(directory=OUTPUTS_DIR), name="outputs")

# In-memory storage for jobs & project state
projects_db: Dict[str, Dict[str, Any]] = {}
jobs_db: Dict[str, Dict[str, Any]] = {}

def process_editing_job(job_id: str, video_path: str, audio_path: Optional[str], plan: EditingPlan, output_path: str):
    try:
        jobs_db[job_id]["status"] = "processing"
        jobs_db[job_id]["message"] = "Executing FFmpeg rendering operations..."
        jobs_db[job_id]["progress"] = 0.1

        def progress_cb(prog: int):
            jobs_db[job_id]["progress"] = round(prog / 100.0, 2)

        MediaEngine.render_edit(
            video_path=video_path,
            audio_path=audio_path,
            plan=plan,
            output_path=output_path,
            progress_callback=progress_cb
        )

        output_filename = os.path.basename(output_path)
        jobs_db[job_id]["status"] = "completed"
        jobs_db[job_id]["progress"] = 1.0
        jobs_db[job_id]["message"] = "Edit rendering completed successfully."
        jobs_db[job_id]["output_url"] = f"/static/outputs/{output_filename}"

    except Exception as e:
        jobs_db[job_id]["status"] = "failed"
        jobs_db[job_id]["error"] = str(e)
        jobs_db[job_id]["message"] = f"Rendering error: {e}"


@app.get("/")
def read_root():
    return {"message": "AI Video Editor Backend API is running."}


@app.post("/api/projects")
async def create_or_update_project(
    background_tasks: BackgroundTasks,
    prompt: str = Form(...),
    language: str = Form("en"),
    project_id: Optional[str] = Form(None),
    video: Optional[UploadFile] = File(None),
    audio: Optional[UploadFile] = File(None)
):
    if not project_id:
        project_id = str(uuid.uuid4())[:8]

    project = projects_db.get(project_id, {
        "id": project_id,
        "video_path": None,
        "audio_path": None,
        "prompts": [],
        "history": []
    })

    # Handle Video Upload
    if video:
        v_ext = os.path.splitext(video.filename)[1] or ".mp4"
        v_save_path = os.path.join(UPLOADS_DIR, f"{project_id}_video{v_ext}")
        with open(v_save_path, "wb") as f:
            f.write(await video.read())
        project["video_path"] = v_save_path

    # Handle Audio Upload
    if audio:
        a_ext = os.path.splitext(audio.filename)[1] or ".mp3"
        a_save_path = os.path.join(UPLOADS_DIR, f"{project_id}_audio{a_ext}")
        with open(a_save_path, "wb") as f:
            f.write(await audio.read())
        project["audio_path"] = a_save_path

    if not project["video_path"] or not os.path.exists(project["video_path"]):
        raise HTTPException(status_code=400, detail="No video file associated with this project.")

    project["prompts"].append(prompt)
    projects_db[project_id] = project

    # Analyze media duration
    video_duration = MediaEngine.get_media_duration(project["video_path"])
    has_audio = project["audio_path"] is not None

    # Generate Structured Editing Plan via AI Planner
    plan = AIPlanner.generate_plan(
        prompt=prompt,
        video_duration=video_duration,
        audio_present=has_audio,
        language=language
    )

    # Create Background Rendering Job
    job_id = str(uuid.uuid4())[:8]
    output_filename = f"{project_id}_edited.mp4"
    output_path = os.path.join(OUTPUTS_DIR, output_filename)

    jobs_db[job_id] = {
        "job_id": job_id,
        "project_id": project_id,
        "status": "queued",
        "progress": 0.0,
        "message": "Job queued for video rendering.",
        "output_url": None,
        "error": None
    }

    background_tasks.add_task(
        process_editing_job,
        job_id,
        project["video_path"],
        project["audio_path"],
        plan,
        output_path
    )

    ai_explanation = plan.explanation_ar if language == "ar" else plan.explanation_en

    return {
        "project_id": project_id,
        "job_id": job_id,
        "plan": plan.dict(),
        "ai_explanation": ai_explanation
    }


@app.get("/api/jobs/{job_id}")
def get_job_status(job_id: str):
    job = jobs_db.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    return job

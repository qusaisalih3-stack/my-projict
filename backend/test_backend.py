import os
import pytest
from .engine import AIPlanner, EditingPlan

def test_ai_planner_cinematic_car_prompt():
    plan = AIPlanner.generate_plan("Make my car video look cinematic and aggressive", 10.0, False, "en")
    assert isinstance(plan, EditingPlan)
    assert plan.filter.style == "aggressive"
    assert len(plan.clips) > 0
    assert plan.explanation_en != ""

def test_ai_planner_arabic_prompt():
    plan = AIPlanner.generate_plan("اجعل الفيديو مظلم ودرامي مع إيقاع الموسيقى", 8.0, True, "ar")
    assert plan.audio.sync_cuts_to_beat is True
    assert plan.explanation_ar != ""

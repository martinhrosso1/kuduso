"""
SiteFit House Placement Solver v1.0.0 (Grasshopper Python Script)

Inputs (GH component names must match exactly):
  parcel_polygon : Curve
  house_polygon  : Curve
  rotation_spec  : String (JSON: {"min":0,"max":180,"step":5})
  grid_step      : Number
  seed           : Integer

Outputs:
  placed_transforms : list[str]  (JSON transform objects)
  placement_scores  : list[float]
  kpis              : list[str]  (JSON metrics objects)

Usage:
  - Drop a Python component on the Grasshopper canvas.
  - Set the component to use this script (copy/paste).
  - Configure five inputs (C, C, S, N, I) and three outputs (generic).
  - Ensure `json` is available (built-in in IronPython 3 / Rhino 8).
"""

import json
import random
from typing import List, Tuple

import Rhino
from Rhino.Geometry import Curve, Point3d, Vector3d, Transform, Plane
from Rhino.Geometry import AreaMassProperties, BoundingBox
from Rhino.Geometry import PointContainment
from Grasshopper.Kernel import GH_RuntimeMessageLevel

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

class PlacementMetrics(object):
    __slots__ = ("yard_area", "house_area", "min_setback", "parcel_utilization")

    def __init__(self, yard_area: float, house_area: float, min_setback: float, parcel_utilization: float):
        self.yard_area = yard_area
        self.house_area = house_area
        self.min_setback = min_setback
        self.parcel_utilization = parcel_utilization


class PlacementResult(object):
    __slots__ = ("translation", "rotation", "score", "metrics")

    def __init__(self, translation: Vector3d, rotation: float, score: float, metrics: PlacementMetrics):
        self.translation = translation
        self.rotation = rotation
        self.score = score
        self.metrics = metrics


def _is_polygon_inside(parcel: Curve, house: Curve, sample_count: int = 20) -> bool:
    params = house.DivideByCount(sample_count, True)
    if params is None:
        return False

    for t in params:
        pt = house.PointAt(t)
        containment = parcel.Contains(pt, Plane.WorldXY, 0.01)
        if containment == PointContainment.Outside:
            return False
    return True


def _calculate_min_distance(parcel: Curve, house: Curve, sample_count: int = 20) -> float:
    min_dist = float("inf")
    params = house.DivideByCount(sample_count, True)
    if params is None:
        return min_dist

    for t in params:
        pt = house.PointAt(t)
        success, u = parcel.ClosestPoint(pt)
        if not success:
            continue
        closest = parcel.PointAt(u)
        dist = pt.DistanceTo(closest)
        if dist < min_dist:
            min_dist = dist
    return min_dist if min_dist != float("inf") else 0.0


def _calculate_metrics(parcel: Curve, house: Curve) -> PlacementMetrics:
    parcel_props = AreaMassProperties.Compute(parcel)
    house_props = AreaMassProperties.Compute(house)

    parcel_area = parcel_props.Area if parcel_props else 0.0
    house_area = house_props.Area if house_props else 0.0
    yard_area = parcel_area - house_area

    min_setback = _calculate_min_distance(parcel, house)
    utilization = (house_area / parcel_area) if parcel_area > 0 else 0.0

    return PlacementMetrics(yard_area, house_area, min_setback, utilization)


def _calculate_score(metrics: PlacementMetrics) -> float:
    score = 0.0
    score += (metrics.yard_area / 1000.0) * 0.3
    score += metrics.min_setback * 0.4

    ideal_util = 0.4
    util_score = 1.0 - abs(metrics.parcel_utilization - ideal_util) * 2.0
    if util_score < 0.0:
        util_score = 0.0
    score += util_score * 0.3
    return score


# ----------------------------------------------------------------------------
# Main solver (expects to be called inside Grasshopper Python component)
# ----------------------------------------------------------------------------

def solve_sitefit(parcel_polygon, house_polygon, rotation_spec, grid_step, seed):
    if parcel_polygon is None or not parcel_polygon.IsClosed:
        raise ValueError("parcel_polygon must be a closed curve")
    if house_polygon is None or not house_polygon.IsClosed:
        raise ValueError("house_polygon must be a closed curve")

    try:
        rot_data = json.loads(rotation_spec) if rotation_spec else {}
    except ValueError:
        rot_data = {}

    min_rot = float(rot_data.get("min", 0.0))
    max_rot = float(rot_data.get("max", 180.0))
    step_rot = float(rot_data.get("step", 5.0))
    step_rot = max(step_rot, 0.1)

    random.seed(seed)

    parcel_bounds = parcel_polygon.GetBoundingBox(True)
    house_props = AreaMassProperties.Compute(house_polygon)
    if house_props is None:
        raise ValueError("Cannot compute house properties")
    house_centroid = house_props.Centroid

    grid_step = max(grid_step, 0.1)
    results = []

    x = parcel_bounds.Min.X
    while x <= parcel_bounds.Max.X + 1e-6:
        y = parcel_bounds.Min.Y
        while y <= parcel_bounds.Max.Y + 1e-6:
            test_pt = Point3d(x, y, 0.0)
            containment = parcel_polygon.Contains(test_pt, Plane.WorldXY, 0.01)
            if containment == PointContainment.Inside:
                angle = min_rot
                while angle <= max_rot + 1e-6:
                    translation = Vector3d(test_pt - house_centroid)
                    t_translate = Transform.Translation(translation)
                    pivot = house_centroid + translation
                    t_rotate = Transform.Rotation(Rhino.RhinoMath.ToRadians(angle), Vector3d.ZAxis, pivot)
                    t_combined = t_rotate * t_translate

                    transformed_house = house_polygon.DuplicateCurve()
                    transformed_house.Transform(t_combined)

                    if _is_polygon_inside(parcel_polygon, transformed_house):
                        metrics = _calculate_metrics(parcel_polygon, transformed_house)
                        score = _calculate_score(metrics)
                        results.append(PlacementResult(translation, angle, score, metrics))

                    angle += step_rot
            y += grid_step
        x += grid_step

    if not results:
        return [], [], []

    results.sort(key=lambda r: r.score, reverse=True)
    results = results[:20]

    transforms_json = []
    scores = []
    kpis_json = []
    for res in results:
        transform_obj = {
            "rotation": {
                "axis": "z",
                "value": res.rotation,
                "units": "deg",
            },
            "translation": {
                "x": res.translation.X,
                "y": res.translation.Y,
                "z": 0.0,
                "units": "m",
            },
            "scale": {
                "uniform": 1.0,
            },
        }
        transforms_json.append(json.dumps(transform_obj, separators=(",", ":")))

        scores.append(res.score)

        metrics_obj = {
            "yard_area_m2": res.metrics.yard_area,
            "min_setback_m": res.metrics.min_setback,
            "house_area_m2": res.metrics.house_area,
            "orientation_deg": res.rotation,
            "parcel_utilization": res.metrics.parcel_utilization,
        }
        kpis_json.append(json.dumps(metrics_obj, separators=(",", ":")))

    return transforms_json, scores, kpis_json


# ----------------------------------------------------------------------------
# Grasshopper entry point
# ----------------------------------------------------------------------------

if __name__ == "__main__":
    try:
        result_transforms, result_scores, result_kpis = solve_sitefit(
            parcel_polygon,
            house_polygon,
            rotation_spec,
            grid_step,
            seed,
        )

        placed_transforms = result_transforms
        placement_scores = result_scores
        kpis = result_kpis

    except Exception as exc:
        ghenv.Component.AddRuntimeMessage(GH_RuntimeMessageLevel.Error, str(exc))

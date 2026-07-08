# Fills the hospital with furniture props (the glb files in assets/props).
#
# Works like page_manager: the placement list lives HERE, so you can move,
# add or remove props by editing PLACES below - no map rebuild needed.
#
# How it works:
#  - Each glb is loaded ONCE at level start (GLTFDocument, same trick as the
#    entity model - no editor import needed). Copies are cheap duplicates.
#  - Every prop is auto-scaled (some files are giant - the bed is 188 m long),
#    auto-centered, and its feet are put at the y you give in PLACES.
#  - Solid props get a box collider on LAYER 1: the player bumps into them
#    AND the navmesh carves around them, so the entity walks around beds
#    instead of through them. (Props spawn in _enter_tree, which runs
#    BEFORE nav_baker bakes - that's what makes the carving work.)
#
# PLACES entry: [prop name, Vector3(x, feet_y, z), yaw in degrees].
# feet_y: 0 = floor 1, 4.1 = floor 2, 1.05 = on a counter, 1.3/5.4 = wall mount.

extends Node3D

const DIR := "res://assets/props/"

# name -> [file, scale, collide, collider footprint shrink]
# Scale numbers come from tools/prop_probe.tscn (real measured sizes).
const DEFS := {
	"table":        ["basic_table.glb", 0.22, true, 1.0],        # -> ~1.2 x 0.76 x 2.0
	"chair":        ["chair_hospital.glb", 1.0, true, 0.7],
	"bed_a":        ["hospital_bed.glb", 0.0106, true, 1.0],     # giant file -> ~2 m long (runs along X)
	"bed_b":        ["hospital_bed (1).glb", 1.15, true, 1.0],   # -> ~2 m long (runs along Z)
	"cupboard":     ["hospital_cupboard.glb", 1.0, true, 1.0],   # 2 m tall, depth along X
	"trolley":      ["hospital_trolley.glb", 1.0, true, 1.0],
	"lab_trolley":  ["laboratory__hospital_troly.glb", 1.0, true, 0.35],  # bounding box is inflated, shrink collider
	"wall_cabinet": ["medicine_wall_cupboard_hospital.glb", 1.2, false, 1.0],  # wall mounted, front faces +Z at yaw 0
	"radiator":     ["radiator_-_11mb.glb", 0.009, true, 1.0],   # giant file -> ~0.64 m wide, 0.71 tall
	"saline":       ["saline_stand_hospital_equipment._blender.glb", 0.207, true, 0.6],  # -> 1.8 m IV stand
}

# ------------------------------------------------------------------ FLOOR 1
const PLACES := [
	# Dining Room (x -55..-40)
	["table", Vector3(-50, 0, -34), 90.0],
	["table", Vector3(-46, 0, -31.5), 90.0],
	["table", Vector3(-43, 0, -34.5), 84.0],
	["chair", Vector3(-50, 0, -32.6), 90.0],
	["chair", Vector3(-46.5, 0, -30.2), 95.0],
	["radiator", Vector3(-44, 0, -37.24), 0.0],
	# Gift Shop (x -40..-31)
	["cupboard", Vector3(-39.5, 0, -32), 0.0],
	["cupboard", Vector3(-39.5, 0, -34), 0.0],
	["table", Vector3(-35, 0, -33.5), 10.0],
	# Restrooms (x -31..-21)
	["trolley", Vector3(-29, 0, -36), 120.0],
	["radiator", Vector3(-21.6, 0, -33), -90.0],
	# Lobby (x -21..3) - two bench rows facing the reception counter, with
	# an aisle in the middle (the player spawns at x -11).
	# Bench facing: the backrest sits on +X, so yaw -90 = facing north.
	["chair", Vector3(-17.0, 0, -33.3), -90.0],
	["chair", Vector3(-14.8, 0, -33.3), -86.0],
	["chair", Vector3(-7.5, 0, -33.3), -90.0],
	["chair", Vector3(-5.3, 0, -33.3), -94.0],
	["chair", Vector3(-17.3, 0, -35.5), -90.0],
	["chair", Vector3(-15.2, 0, -35.5), -88.0],
	["chair", Vector3(-6.7, 0, -35.5), -92.0],
	["chair", Vector3(-4.6, 0, -35.5), -90.0],
	["saline", Vector3(-16, 0, -29), 0.0],
	# Chapel (x 3..12) - pew rows facing the altar table (north wall)
	["chair", Vector3(5.7, 0, -34.4), -90.0],
	["chair", Vector3(8.2, 0, -34.4), -92.0],
	["chair", Vector3(5.7, 0, -32.4), -90.0],
	["chair", Vector3(8.2, 0, -32.4), -88.0],
	["table", Vector3(7.5, 0, -36.5), 0.0],
	# Waiting Area (x 12..30) - both rows face the corridor opening (south)
	["chair", Vector3(16, 0, -34), 90.0],
	["chair", Vector3(18.2, 0, -34), 90.0],
	["chair", Vector3(20.4, 0, -34), 88.0],
	["chair", Vector3(16, 0, -31.5), 90.0],
	["chair", Vector3(18.2, 0, -31.5), 92.0],
	["chair", Vector3(20.4, 0, -31.5), 90.0],
	["radiator", Vector3(29.7, 0, -33), 90.0],
	["trolley", Vector3(25, 0, -29.5), 45.0],
	# ER Registration (x 30..40) - bench aimed at the counter
	["chair", Vector3(32, 0, -34.5), 127.0],
	["wall_cabinet", Vector3(37, 1.3, -37.22), 0.0],
	# ER Waiting (x 40..55) - two columns facing the registration door (west)
	["chair", Vector3(44, 0, -35), 0.0],
	["chair", Vector3(44, 0, -33), 0.0],
	["chair", Vector3(44, 0, -31), 4.0],
	["chair", Vector3(46.5, 0, -35), 0.0],
	["chair", Vector3(46.5, 0, -33), 2.0],
	["radiator", Vector3(54.7, 0, -32), -90.0],
	# Serving Area (x -55..-38, z -25..-14)
	["table", Vector3(-48, 0, -20), 90.0],
	["table", Vector3(-44, 0, -18.5), 85.0],
	["trolley", Vector3(-51, 0, -16), 10.0],
	["trolley", Vector3(-41, 0, -23), 170.0],
	# Offices (x -35..-25 and -25..-15)
	["table", Vector3(-30, 0, -20), 0.0],
	["chair", Vector3(-30.8, 0, -18.4), -117.0],
	["cupboard", Vector3(-28, 0, -24.5), 90.0],
	["table", Vector3(-20, 0, -19), 90.0],
	["chair", Vector3(-19, 0, -20.6), 58.0],
	["radiator", Vector3(-15.26, 0, -18), -90.0],
	# Main Patient Registration (x -15..-1.5)
	["trolley", Vector3(-5, 0, -17), 30.0],
	["saline", Vector3(-12, 0, -22), 0.0],
	["wall_cabinet", Vector3(-14.72, 1.3, -18), 90.0],
	# Ultrasound (x 1.5..14, z -25..-14)
	["bed_a", Vector3(7, 0, -19), 0.0],
	["saline", Vector3(8.5, 0, -17.6), 0.0],
	["trolley", Vector3(5.5, 0, -17.5), -30.0],
	["cupboard", Vector3(11, 0, -14.5), 90.0],
	# Lab (x 14..24)
	["lab_trolley", Vector3(19, 0, -19.5), 30.0],
	["wall_cabinet", Vector3(16, 1.3, -24.72), 0.0],
	["trolley", Vector3(22, 0, -16), 100.0],
	# EKG (x 24..32)
	["bed_a", Vector3(28, 0, -19.5), 90.0],
	["trolley", Vector3(26, 0, -22), 45.0],
	["radiator", Vector3(24.3, 0, -17), 90.0],
	# Pass-through room (x 35..44)
	["chair", Vector3(37, 0, -20), 90.0],
	["chair", Vector3(37, 0, -18.4), 95.0],
	["saline", Vector3(42, 0, -16), 0.0],
	# Triage (x 47..55)
	["bed_b", Vector3(53.6, 0, -19.5), -90.0],
	["saline", Vector3(52.3, 0, -18.2), 0.0],
	["trolley", Vector3(49, 0, -16), -15.0],
	["wall_cabinet", Vector3(54.72, 1.3, -22), -90.0],
	# Physician Dining (x -55..-38, z -11..3)
	["table", Vector3(-48, 0, -6), 0.0],
	["table", Vector3(-43, 0, -2), 15.0],
	["chair", Vector3(-46.6, 0, -6), 0.0],
	["chair", Vector3(-49.6, 0, -4.5), -137.0],
	["radiator", Vector3(-54.7, 0, -2), 90.0],
	# X-Ray (x -35..-18)
	["bed_a", Vector3(-26, 0, -7.5), 0.0],
	["trolley", Vector3(-30, 0, -9), 60.0],
	["cupboard", Vector3(-34.5, 0, -8), 0.0],
	["saline", Vector3(-22, 0, -6), 0.0],
	# Dark Room (x -18..-10)
	["table", Vector3(-14, 0, -8), 90.0],
	["wall_cabinet", Vector3(-17.72, 1.3, -7), 90.0],
	# Nuclear Medicine (x -10..-1.5)
	["bed_b", Vector3(-7.5, 0, -8), 0.0],
	["saline", Vector3(-6.2, 0, -6.6), 0.0],
	["cupboard", Vector3(-4, 0, -10.5), 90.0],
	# Small rooms by the central stairs (x 7.5..24, z -11..-4)
	["table", Vector3(10.5, 0, -7.5), 5.0],
	["chair", Vector3(9.5, 0, -6), -124.0],
	["trolley", Vector3(18, 0, -9), 80.0],
	# ER Fast Track (x 24..32, z -11..3)
	["bed_b", Vector3(25.5, 0, -8), 90.0],
	["bed_b", Vector3(30.5, 0, -8), -88.0],
	["saline", Vector3(27, 0, -5.8), 0.0],
	# ER bay (x 35..44)
	["bed_a", Vector3(39.5, 0, -7), 0.0],
	["trolley", Vector3(37, 0, -2), 120.0],
	["saline", Vector3(41, 0, -5.5), 0.0],
	# ER east bay (x 47..55)
	["bed_b", Vector3(53.5, 0, -8), -90.0],
	["bed_b", Vector3(53.5, 0, -2), -90.0],
	["saline", Vector3(52, 0, -6), 0.0],
	["trolley", Vector3(49.5, 0, 0), 20.0],
	["wall_cabinet", Vector3(54.72, 1.3, -5), -90.0],
	# Office row south of the courtyard band (x -20..-1.5, z -4..3)
	["table", Vector3(-12, 0, -0.5), 170.0],
	["chair", Vector3(-13.5, 0, 0.8), 60.0],
	["radiator", Vector3(-6, 0, -3.74), 180.0],
	# Courtyard (open air) - one lone chair in the grass
	["chair", Vector3(18.5, 0.01, -1), 140.0],
	# MRI (x -35..-14, z 6..20)
	["bed_a", Vector3(-24, 0, 12), 0.0],
	["cupboard", Vector3(-34.5, 0, 10), 0.0],
	["trolley", Vector3(-28, 0, 15), -70.0],
	# MRI control + hot lab (x -14..-1.5)
	["table", Vector3(-8, 0, 10), 90.0],
	["chair", Vector3(-6.5, 0, 11.5), -45.0],
	["wall_cabinet", Vector3(-1.78, 1.3, 9), -90.0],
	["lab_trolley", Vector3(-7, 0, 15), 20.0],
	# Ward A (x 1.5..16, z 6..13)
	["bed_b", Vector3(4, 0, 6.7), 180.0],
	["bed_b", Vector3(7, 0, 6.7), 178.0],
	["saline", Vector3(5.5, 0, 7.9), 0.0],
	["cupboard", Vector3(15.5, 0, 9), 0.0],
	# Ward B (x 1.5..16, z 13..20)
	["bed_b", Vector3(4, 0, 19.4), 0.0],
	["bed_b", Vector3(7, 0, 19.4), 3.0],
	["trolley", Vector3(10, 0, 16), 60.0],
	["radiator", Vector3(1.8, 0, 15), 90.0],
	# Ward C (x 16..32, z 6..13)
	["bed_b", Vector3(19, 0, 6.7), 180.0],
	["bed_b", Vector3(22, 0, 6.7), 175.0],
	["saline", Vector3(20.5, 0, 8), 0.0],
	# Ward D (x 16..32, z 13..20)
	["bed_b", Vector3(28, 0, 19.4), 0.0],
	["trolley", Vector3(25, 0, 15.5), -40.0],
	# Storage rooms (x 35..44, z 6..20)
	["cupboard", Vector3(35.5, 0, 9), 0.0],
	["cupboard", Vector3(35.5, 0, 11), 2.0],
	["trolley", Vector3(40, 0, 8), 150.0],
	["table", Vector3(39.5, 0, 16.5), 95.0],
	["chair", Vector3(38, 0, 17), -161.0],
	# ER rooms 10-15 (x 47..55, east edge)
	["bed_b", Vector3(52, 0, 7.4), 90.0],
	["bed_b", Vector3(52, 0, 10.25), -90.0],
	["bed_b", Vector3(52, 0, 15.9), 90.0],
	["bed_b", Vector3(52, 0, 21.6), -90.0],
	["saline", Vector3(50, 0, 13.1), 0.0],
	["trolley", Vector3(50, 0, 18.7), -120.0],
	# Laundry (x -41..-24, z 23..37.5)
	["trolley", Vector3(-34, 0, 27), 20.0],
	["trolley", Vector3(-33, 0, 28.2), 200.0],
	["table", Vector3(-28, 0, 30), 90.0],
	["radiator", Vector3(-30, 0, 37.24), 180.0],
	# Boiler (x -24..-8)
	["cupboard", Vector3(-23.5, 0, 27), 0.0],
	["trolley", Vector3(-18, 0, 30), 75.0],
	["radiator", Vector3(-12, 0, 37.24), 180.0],
	# Central Stores (x -8..8) - cupboard row
	["cupboard", Vector3(-4, 0, 37.0), 90.0],
	["cupboard", Vector3(-2.7, 0, 37.0), 90.0],
	["cupboard", Vector3(-1.4, 0, 37.0), 88.0],
	["table", Vector3(3, 0, 30), 90.0],
	["trolley", Vector3(5, 0, 26), -60.0],
	# Morgue (x 8..24)
	["bed_a", Vector3(13, 0, 31), 0.0],
	["bed_a", Vector3(19, 0, 33), 20.0],
	["trolley", Vector3(11, 0, 27), 140.0],
	["cupboard", Vector3(23.5, 0, 32), 0.0],
	# Utility room (x 24..40)
	["table", Vector3(30, 0, 28), 0.0],
	["chair", Vector3(31.5, 0, 29), -34.0],
	["radiator", Vector3(39.74, 0, 30), -90.0],
	# Ambulance Bay (x 40..55) - keep the entity spawn (48, 30) clear
	["bed_b", Vector3(43, 0, 32), -30.0],
	["trolley", Vector3(52, 0, 26), 80.0],
	["saline", Vector3(44, 0, 26), 0.0],
	# Extra radiators, floor 1 (one per room, against a wall)
	["radiator", Vector3(-36, 0, -37.25), 0.0],       # gift shop, north wall
	["radiator", Vector3(-20.75, 0, -31), 90.0],      # lobby, west wall
	["radiator", Vector3(5, 0, -37.25), 0.0],         # chapel, north wall
	["radiator", Vector3(30.25, 0, -31), 90.0],       # ER registration, west wall
	["radiator", Vector3(-54.75, 0, -20), 90.0],      # serving area, west wall
	["radiator", Vector3(-32, 0, -14.25), 180.0],     # office 1, south wall
	["radiator", Vector3(4, 0, -24.75), 0.0],         # ultrasound, north wall
	["radiator", Vector3(21, 0, -14.25), 180.0],      # lab, south wall
	["radiator", Vector3(52, 0, -24.75), 0.0],        # triage, north wall
	["radiator", Vector3(-31, 0, -4.25), 180.0],      # x-ray, south wall
	["radiator", Vector3(-9.75, 0, -6), 90.0],        # nuclear medicine, west wall
	["radiator", Vector3(-34.75, 0, 16), 90.0],       # MRI, west wall
	["radiator", Vector3(11, 0, 6.25), 0.0],          # ward A, north wall
	["radiator", Vector3(26, 0, 6.25), 0.0],          # ward C, north wall
	["radiator", Vector3(20, 0, 19.75), 180.0],       # ward D, south wall
	["radiator", Vector3(14, 0, 37.25), 180.0],       # morgue, south wall
	["radiator", Vector3(54.75, 0, 34), -90.0],       # ambulance bay, east wall
	# Floor-1 corridor dressing (kept close to walls, away from page spots)
	["trolley", Vector3(-5, 0, -27.5), 100.0],
	["chair", Vector3(30, 0, -25.7), 170.0],
	["saline", Vector3(-30, 0, -11.6), 0.0],
	["trolley", Vector3(10, 0, -13.5), -80.0],
	["bed_b", Vector3(38, 0, -12.8), 110.0],
	["trolley", Vector3(-33, 0, 4), 20.0],
	["chair", Vector3(12, 0, 5.2), -140.0],
	["trolley", Vector3(28, 0, 21), 60.0],
	["saline", Vector3(-8, 0, 22.3), 0.0],
	["bed_b", Vector3(45.2, 0, 16), 10.0],
	["trolley", Vector3(-37.5, 0, -8), 95.0],
	["trolley", Vector3(32.7, 0, 10), 95.0],

	# -------------------------------------------------------------- FLOOR 2
	# North patient rooms (z -37.5..-28, beds against the north wall)
	["bed_b", Vector3(-50, 4.1, -36.9), 180.0],
	["saline", Vector3(-48.7, 4.1, -35.8), 0.0],
	["bed_b", Vector3(-39, 4.1, -36.9), 177.0],
	["cupboard", Vector3(-33.5, 4.1, -33), 0.0],
	["bed_b", Vector3(-28, 4.1, -36.9), 182.0],
	["chair", Vector3(-25, 4.1, -34), 140.0],
	["bed_b", Vector3(-7, 4.1, -36.9), 180.0],
	["radiator", Vector3(-1.76, 4.1, -32), -90.0],
	["bed_b", Vector3(5, 4.1, -36.9), 178.0],
	["saline", Vector3(6.3, 4.1, -35.7), 0.0],
	["trolley", Vector3(15, 4.1, -33), 60.0],
	["bed_b", Vector3(27, 4.1, -36.9), 180.0],
	["bed_b", Vector3(49, 4.1, -36.9), 183.0],
	["saline", Vector3(50.4, 4.1, -35.9), 0.0],
	# Nurse station (counters at +-8.25, -19.5)
	["chair", Vector3(-8, 4.1, -21), 81.0],
	["trolley", Vector3(2, 4.1, -16), -45.0],
	["wall_cabinet", Vector3(14.72, 5.4, -18), -90.0],
	# Day Room (x -35..-15, z -25..-14)
	["table", Vector3(-28, 4.1, -19), 0.0],
	["chair", Vector3(-26.5, 4.1, -19.5), 18.0],
	["chair", Vector3(-29.5, 4.1, -18), -146.0],
	["table", Vector3(-22, 4.1, -21), 85.0],
	["chair", Vector3(-21, 4.1, -19.5), -56.0],
	["radiator", Vector3(-30, 4.1, -24.74), 180.0],
	# Treatment (x 15..32, z -25..-14)
	["bed_b", Vector3(18, 4.1, -14.62), 0.0],
	["saline", Vector3(19.3, 4.1, -15.8), 0.0],
	["trolley", Vector3(25, 4.1, -20), 30.0],
	["cupboard", Vector3(28, 4.1, -24.52), 90.0],
	# East rooms (x 35..55, z -25..-14)
	["bed_b", Vector3(39.5, 4.1, -14.62), 0.0],
	["saline", Vector3(41, 4.1, -16), 0.0],
	["trolley", Vector3(51, 4.1, -18), -70.0],
	# Operating Theatre 1 (x -18..-1.5, z -11..-4)
	["bed_a", Vector3(-10, 4.1, -7.5), 0.0],
	["saline", Vector3(-8.4, 4.1, -6.2), 0.0],
	["lab_trolley", Vector3(-14, 4.1, -6), 40.0],
	["trolley", Vector3(-6, 4.1, -9.5), -120.0],
	["wall_cabinet", Vector3(-4, 5.4, -10.72), 0.0],
	# Operating Theatre 2 (x 7.5..13.5, z -11..-4)
	["bed_a", Vector3(10.5, 4.1, -7.5), 90.0],
	["saline", Vector3(12, 4.1, -6), 0.0],
	# Scrub/Sterile (x 13.5..24, z -11..-4)
	["cupboard", Vector3(14, 4.1, -7), 0.0],
	["trolley", Vector3(17, 4.1, -6), 10.0],
	# Pharmacy (x 24..32, z -11..3)
	["cupboard", Vector3(26, 4.1, -10.52), 90.0],
	["cupboard", Vector3(27.3, 4.1, -10.52), 90.0],
	["cupboard", Vector3(28.6, 4.1, -10.52), 92.0],
	["wall_cabinet", Vector3(31.72, 5.4, -6), -90.0],
	["table", Vector3(28, 4.1, -1), 90.0],
	# ICU open bay (x 47..55, z -11..3) - page spot on the east wall at z -7
	["bed_b", Vector3(53.5, 4.1, -9), -90.0],
	["bed_b", Vector3(53.5, 4.1, -3), -90.0],
	["saline", Vector3(52, 4.1, -7.5), 0.0],
	["trolley", Vector3(49, 4.1, -1), 60.0],
	# Physio hall (x -35..-14, z 6..20)
	["bed_a", Vector3(-30, 4.1, 10), 0.0],
	["bed_a", Vector3(-20, 4.1, 14), 90.0],
	["chair", Vector3(-25, 4.1, 12), -60.0],
	["radiator", Vector3(-28, 4.1, 19.74), 0.0],
	["saline", Vector3(-18, 4.1, 9), 0.0],
	# Iso wards (x 47..55, z 6..23)
	["bed_b", Vector3(52, 4.1, 9), 90.0],
	["saline", Vector3(53, 4.1, 11), 0.0],
	["bed_b", Vector3(52, 4.1, 20), 90.0],
	["cupboard", Vector3(54.5, 4.1, 17), 0.0],
	# South patient rooms (z 23..37.5, beds against the south wall)
	["bed_b", Vector3(-24, 4.1, 36.9), 0.0],
	["saline", Vector3(-22.7, 4.1, 35.8), 0.0],
	["bed_b", Vector3(-16, 4.1, 36.9), 2.0],
	["chair", Vector3(-11, 4.1, 34), 170.0],
	["bed_b", Vector3(-3, 4.1, 36.9), -4.0],
	["radiator", Vector3(-7.74, 4.1, 32), 90.0],
	["trolley", Vector3(8, 4.1, 33), -20.0],
	["bed_b", Vector3(19, 4.1, 36.9), 183.0],
	["cupboard", Vector3(24.5, 4.1, 33), 0.0],
	["bed_b", Vector3(30, 4.1, 36.9), 178.0],
	["saline", Vector3(31.3, 4.1, 35.7), 0.0],
	["bed_b", Vector3(51, 4.1, 36.9), 180.0],
	["radiator", Vector3(54.7, 4.1, 32), -90.0],
	# Extra radiators, floor 2
	["radiator", Vector3(-16, 4.1, -37.25), 0.0],     # north patient room 4
	["radiator", Vector3(16, 4.1, -37.25), 0.0],      # north patient room 7
	["radiator", Vector3(38, 4.1, -37.25), 0.0],      # north patient room 9
	["radiator", Vector3(15.25, 4.1, -18), 90.0],     # treatment, west wall
	["radiator", Vector3(24.25, 4.1, -4), 90.0],      # pharmacy, west wall
	["radiator", Vector3(50, 4.1, -10.75), 0.0],      # ICU, north wall
	["radiator", Vector3(54.75, 4.1, 21), -90.0],     # iso ward 2, east wall
	["radiator", Vector3(10, 4.1, 37.25), 180.0],     # south patient room, south wall
	["radiator", Vector3(41, 4.1, 37.25), 180.0],     # south patient room, south wall
	# Floor-2 corridor dressing
	["bed_b", Vector3(38, 4.1, -12.8), 95.0],
	["trolley", Vector3(5, 4.1, -13.4), 70.0],
	["chair", Vector3(-10, 4.1, -27.6), 20.0],
	["saline", Vector3(15, 4.1, -25.7), 0.0],
	["trolley", Vector3(-25, 4.1, 21.5), -30.0],
]

# One loaded template per prop: { node, size, center }
var lib := {}
var library_holder: Node3D


# _enter_tree (NOT _ready) so all props exist before nav_baker bakes the
# navmesh - that's what makes the entity path around the furniture.
func _enter_tree() -> void:
	var nav := get_parent().get_node_or_null("Nav")
	if nav == null:
		push_warning("PROPS: no Nav node found - props not spawned")
		return

	# Hidden shelf that holds one loaded template of each prop.
	library_holder = Node3D.new()
	library_holder.name = "PropLibrary"
	library_holder.visible = false
	add_child(library_holder)

	var count := 0
	for p in PLACES:
		if _spawn(nav, p[0], p[1], deg_to_rad(p[2])):
			count += 1
	print("PROPS: ", count, " props placed")


# Loads one glb template and measures it (only happens once per file).
func _get_template(def_name: String) -> Dictionary:
	if lib.has(def_name):
		return lib[def_name]
	var def: Array = DEFS[def_name]
	var doc := GLTFDocument.new()
	var gltf := GLTFState.new()
	if doc.append_from_file(DIR + def[0], gltf) != OK:
		push_warning("PROPS: couldn't read " + def[0])
		lib[def_name] = {}
		return {}
	var scene := doc.generate_scene(gltf)
	if scene == null:
		push_warning("PROPS: no scene in " + def[0])
		lib[def_name] = {}
		return {}
	library_holder.add_child(scene)

	# One big box around all its meshes = real size + where its middle is.
	var total := AABB()
	var first := true
	var stack: Array = [scene]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			var ab: AABB = n.global_transform * n.mesh.get_aabb()
			total = ab if first else total.merge(ab)
			first = false
		for c in n.get_children():
			stack.append(c)

	lib[def_name] = {"node": scene, "size": total.size, "center": total.get_center(), "min_y": total.position.y}
	return lib[def_name]


# Puts one prop copy in the world: centered on x/z, feet at pos.y, plus a
# box collider (layer 1) if this prop is solid.
func _spawn(nav: Node, def_name: String, pos: Vector3, yaw: float) -> bool:
	var t := _get_template(def_name)
	if t.is_empty():
		return false
	var def: Array = DEFS[def_name]
	var s: float = def[1]

	var root := Node3D.new()
	root.name = "Prop_" + def_name + "_" + str(nav.get_child_count())
	root.position = pos
	root.rotation.y = yaw

	# The visual copy, scaled and shifted so the prop's middle sits on the
	# root and its feet sit at y 0.
	var model: Node3D = t.node.duplicate()
	model.scale = Vector3.ONE * s
	model.position = Vector3(-t.center.x * s, -t.min_y * s, -t.center.z * s)
	model.visible = true
	root.add_child(model)

	if def[2]:  # solid: box collider the size of the prop
		var body := StaticBody3D.new()
		body.name = "Solid"
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		var shrink: float = def[3]
		shape.size = Vector3(t.size.x * s * shrink, t.size.y * s, t.size.z * s * shrink)
		cs.shape = shape
		cs.position = Vector3(0, t.size.y * s * 0.5, 0)
		body.add_child(cs)
		root.add_child(body)

	nav.add_child(root)
	return true

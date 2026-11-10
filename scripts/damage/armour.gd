class_name Armour
extends RefCounted
## Armour rules: impact angle, effective thickness, ricochet and penetration.
## Pure functions so they can be tested without a scene.

## Effective thickness is capped at this multiple of the plate (avoids 1/cos(90°)).
const MAX_ANGLE_FACTOR: float = 10.0


## Angle between the shell's path and the plate's normal (radians, 0 = straight on).
static func impact_angle(velocity: Vector3, normal: Vector3) -> float:
	if velocity.length_squared() < 0.0001:
		return 0.0
	return (-velocity.normalized()).angle_to(normal.normalized())


## Thickness the shell has to go through at `angle` (radians).
static func effective_thickness(thickness_mm: float, angle: float) -> float:
	return thickness_mm * minf(1.0 / maxf(cos(angle), 0.0001), MAX_ANGLE_FACTOR)


## Penetration at impact speed: falls off in proportion to remaining speed.
static func penetration_at(shell: ShellData, speed: float) -> float:
	if shell.muzzle_velocity_mps <= 0.0:
		return 0.0
	return shell.penetration_mm * speed / shell.muzzle_velocity_mps


## Angle (degrees from the normal) above which a round of `caliber_mm` glances off a
## plate `plate_mm` thick (worn thickness): the chassis' angle, rising towards 90° as the
## round overmatches the plate. Above 90 = never bounces.
static func ricochet_angle(armour: ArmourData, caliber_mm: float, plate_mm: float) -> float:
	if plate_mm <= 0.0:
		return armour.ricochet_angle_deg
	var span: float = maxf(armour.overmatch_full_ratio - armour.overmatch_start_ratio, 0.001)
	var t: float = (caliber_mm / plate_mm - armour.overmatch_start_ratio) / span
	if t >= 1.0:
		return 180.0
	return lerpf(armour.ricochet_angle_deg, 90.0, clampf(t, 0.0, 1.0))


## Decides what a shell does to a plate. Fills everything but part, face and target.
static func resolve(shell: ShellData, speed: float, thickness_mm: float, angle: float,
		ricochet_angle_deg: float) -> HitResult:
	var result := HitResult.new()
	result.armour_mm = thickness_mm
	result.angle_deg = rad_to_deg(angle)
	result.effective_mm = effective_thickness(thickness_mm, angle)
	result.penetration_mm = penetration_at(shell, speed)
	if result.angle_deg > ricochet_angle_deg and not shell.is_explosive():
		result.outcome = HitResult.Outcome.RICOCHET   # HE bursts on the plate instead
	elif result.penetration_mm >= result.effective_mm:
		result.outcome = HitResult.Outcome.PENETRATION
	else:
		result.outcome = HitResult.Outcome.NO_PENETRATION
	return result

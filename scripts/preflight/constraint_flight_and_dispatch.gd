class_name PreflightConstraintFlightAndDispatch
extends RefCounted

## FlightTime math and Dispatch cluster packing/tier boundaries.

func constraint_name() -> String:
	return "flight_and_dispatch"

func requires_scene() -> bool:
	return false


func run(ctx: PreflightContext) -> bool:
	if not ctx.check(is_equal_approx(FlightTime.seconds_for(100.0, 1), 8.0), "flight time baseline is wrong"):
		return false
	if not ctx.check(is_equal_approx(FlightTime.seconds_for(100.0, 2), 8.4), "flight time unit load is wrong"):
		return false
	if not ctx.check(is_equal_approx(FlightTime.seconds_for(200.0, 5), 17.6), "flight time medium load is wrong"):
		return false
	if not ctx.check(FlightTime.seconds_for(100.0, 6) > FlightTime.seconds_for(100.0, 5), "flight time unit scaling is wrong"):
		return false
	if not ctx.check(Dispatch.cluster_groups(1) == [1] and Dispatch.cluster_groups(4) == [1, 1, 1, 1] and Dispatch.cluster_groups(5) == [5] and Dispatch.cluster_groups(7) == [5, 1, 1] and Dispatch.cluster_groups(100) == [100], "cluster packing thresholds are wrong"):
		return false
	if not ctx.check(Dispatch.cluster_tier(4) == &"k" and Dispatch.cluster_tier(5) == &"m" and Dispatch.cluster_tier(99) == &"m" and Dispatch.cluster_tier(100) == &"l", "cluster tier boundaries are wrong"):
		return false
	if not ctx.check(Dispatch.cluster_tier(1, null, 1) == &"m" and Dispatch.cluster_tier(5, null, 1) == &"l" and Dispatch.cluster_tier(100, null, 1) == &"l", "cluster tier bonus does not unlock heavier visible tiers"):
		return false
	if not ctx.check(Dispatch.cluster_tier(1, null, -1) == &"k", "negative cluster tier bonus should not lower a tier"):
		return false
	if not ctx.check(Dispatch.amount_range(3) == Vector2i(1, 3), "dispatch range for three units is wrong"):
		return false
	if not ctx.check(Dispatch.amount_range(1) == Vector2i(1, 1), "dispatch range for one unit is wrong"):
		return false
	if not ctx.check(Dispatch.amount_range(0) == Vector2i.ZERO, "dispatch range for empty planet is wrong"):
		return false
	if not ctx.check(Dispatch.amount_range(-1) == Vector2i.ZERO, "dispatch range for negative count is wrong"):
		return false
	if not ctx.check(Dispatch.launch_amount(3, 2) == 2, "launch amount should match request"):
		return false
	if not ctx.check(Dispatch.launch_amount(2, 5) == 2, "launch amount should clamp to available"):
		return false
	if not ctx.check(Dispatch.launch_amount(0, 3) == 0, "launch amount from empty planet should be zero"):
		return false
	if not ctx.check(Dispatch.launch_amount(3, 0) == 0, "launch amount with zero requested should be zero"):
		return false
	return true

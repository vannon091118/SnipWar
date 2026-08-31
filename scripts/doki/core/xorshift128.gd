class_name DOKI_XorShift128
extends RefCounted
## Deterministischer PRNG, Port aus dem XBridge.DOKI-System (RngEngine.cs).
## 32-Bit-Zustand (s0, s1), integer-basierter Next → exakte 32-Bit-Emulation.
## GDScript-int ist 64-bit: JEDE Operation wird auf 32 Bit maskiert (<<< 32),
## damit die uint-Umdrehung von C# exakt nachgebildet wird (V8-001).

var _s0: int = 0
var _s1: int = 0


func _init(seed: int) -> void:
	_s0 = seed & 0xFFFFFFFF
	_s1 = (seed * 1812433253 + 1) & 0xFFFFFFFF
	# Aufwärmphase: 10 Iterationen (wie im Original)
	for _i in 10:
		_step()


func _step() -> int:
	var s1: int = _s0
	var s0: int = _s1
	_s0 = s0
	s1 = (s1 ^ ((s1 << 23) & 0xFFFFFFFF)) & 0xFFFFFFFF
	s1 = (s1 ^ (s1 >> 17)) & 0xFFFFFFFF
	s1 = (s1 ^ s0) & 0xFFFFFFFF
	s1 = (s1 ^ (s0 >> 26)) & 0xFFFFFFFF
	_s1 = s1
	return (s0 + _s1) & 0xFFFFFFFF


## Integer in [0, 2^32).
func next_uint32() -> int:
	return _step()


## Float in [0, 1).
func next() -> float:
	return float(next_uint32()) / 4294967296.0


## Integer in [min, max) — integer arithmetic, no float (V8-003).
func next_int(min: int, max: int) -> int:
	var range_size: int = max - min
	if range_size <= 0:
		return min
	# Rejection sampling to avoid modulo bias
	var threshold: int = (0x100000000 / range_size) * range_size
	var r: int
	while true:
		r = next_uint32()
		if r < threshold:
			break
	return min + (r % range_size)
class_name DOKI_XorShift128
extends RefCounted
## Deterministischer PRNG, Port aus dem XBridge.DOKI-System (RngEngine.cs).
## 32-Bit-Zustand (s0, s1), Double-basierter Next → keine Low-Bit-Korrelation.
## GDScript-int ist 64-bit: JEDE Operation wird auf 32 Bit maskiert, damit die
## uint-Umdrehung von C# exakt nachgebildet wird.

var _s0: int = 0
var _s1: int = 0

func _init(seed: int) -> void:
	_s0 = seed & 0xFFFFFFFF
	_s1 = (seed * 1812433253 + 1) & 0xFFFFFFFF
	# Aufwärmphase: 10 Iterationen (wie im Original)
	for _i in 10:
		_step()


func _step() -> float:
	var s1: int = _s0
	var s0: int = _s1
	_s0 = s0
	s1 = (s1 ^ (s1 << 23)) & 0xFFFFFFFF
	s1 = (s1 ^ (s1 >> 17)) & 0xFFFFFFFF
	s1 = (s1 ^ s0) & 0xFFFFFFFF
	s1 = (s1 ^ (s0 >> 26)) & 0xFFFFFFFF
	_s1 = s1
	return float((s0 + _s1) & 0xFFFFFFFF) / 4294967296.0


## Float in [0, 1).
func next() -> float:
	return _step()


## Integer in [min, max).
func next_int(min: int, max: int) -> int:
	var range_size: float = float(max - min)
	return min + int(next() * range_size)
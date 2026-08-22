class_name PreflightConstraintPaperStyle
extends RefCounted

## Validates the paper-comic style assets: shader presence and config integrity.

const PAPER_STYLE: PaperStyleConfig = preload("res://resources/config/paper_style_default.tres")

func constraint_name() -> String:
	return "paper_style"

func run(ctx: PreflightContext) -> bool:
	if not ctx.check(ResourceLoader.exists("res://assets/shaders/paper_cell_shading.gdshader"), "paper_cell_shading shader is missing"):
		return false
	if not ctx.check(ResourceLoader.exists("res://assets/shaders/paper_outline.gdshader"), "paper_outline shader is missing"):
		return false
	if not ctx.check(ResourceLoader.exists("res://assets/shaders/paper_grain_overlay.gdshader"), "paper_grain_overlay shader is missing"):
		return false
	if not ctx.check(PAPER_STYLE != null and PAPER_STYLE.validate().is_empty(), "default paper style must validate"):
		return false
	if not ctx.check(PAPER_STYLE.cell_shading_levels >= 2, "cell_shading_levels must be at least two"):
		return false
	return true

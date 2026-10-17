class_name CosmeticColours
extends RefCounted
## Shared garment palette and readable ink, independent of lighting and UI.


static func fabric(colour: Color) -> Color:
	return Color.from_hsv(
		clampf(colour.h, 0, 1), clampf(colour.s * 1.4 + 0.12, 0.25, 0.95), minf(colour.v * 0.9, 0.9)
	)


static func logo_ink(background: Color) -> Color:
	# Compare actual sRGB relative luminance against black and white contrast ratios.
	var luminance := background.srgb_to_linear().get_luminance()
	var white_contrast := 1.05 / (luminance + 0.05)
	var black_contrast := (luminance + 0.05) / 0.05
	return Color.WHITE if white_contrast > black_contrast else Color.BLACK

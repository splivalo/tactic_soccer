# Selection Indicator

`scenes/selection_indicator.tscn` is a reusable `Node3D` framework for showing
the active footballer and legal movement directions. It contains no gameplay
rules and no baked artwork: rings, arrows, glow, line style, animation, opacity,
and decorations are generated from Inspector properties.

## Scene

```text
SelectionIndicator
+-- Glow
+-- Ring
+-- DirectionArrows
+-- Decorations
```

## Gameplay API

```gdscript
indicator.global_position = selected_player.global_position
indicator.set_allowed_directions([Vector2i(1, 0), Vector2i(0, -1)])
indicator.show_indicator()

indicator.hide_indicator()
```

`set_allowed_directions()` accepts `Vector2i`, `Vector2`, or string compass
names: `N`, `NE`, `E`, `SE`, `S`, `SW`, `W`, `NW`.

## Inspector Styling

All visual decisions are exposed on the `SelectionIndicator` node:

- `Global Visuals`: opacity, segment count, corner rounding, corner segments.
- `Colors`: ring, glow, legal arrows, illegal arrows, decorations.
- `Rings`: count, radius, thickness, spacing, line style, dash count, dash fill, opacity falloff.
- `Arrows`: visibility, illegal visibility, style, length, width, spacing, notch depth, rotation offset.
- `Glow`: visibility, intensity, size, center opacity.
- `Decorations`: style, count, radius, length, width, rotation offset.
- `Animation`: pulse speed, pulse amount, rotation speed, duration, select scale, selected scale, rotating parts.

The gameplay layer should only decide which directions are legal. Everything
about how those directions look belongs to these exported style properties.

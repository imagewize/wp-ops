# Logo candidates

Alternates for the wp-ops mark. **`a-windrose.svg` is the one in use**: it is
`assets/logo.svg` (WordPress blue `#21759B`, for light backgrounds) and
`assets/logo-dark.svg` (lifted to `#4DA9CE`, because `#21759B` only makes
3.7:1 against GitHub's dark canvas where `#4DA9CE` makes 7.2:1). The README
header picks between them with `<picture>` and `prefers-color-scheme`, the
same way mshin does. The rest are kept here as the alternates considered.

All are original drawings rather than adaptations of an existing icon set,
so there is no third-party licence to carry. They follow the same drawing
conventions as the rest of the Imagewize marks (Aviendha, Nynaeve, Aludra):
a 24×24 viewBox, a single flat colour, 2px round-capped strokes or a flat
fill, and no background box. The candidates here are all drawn in WordPress
blue `#21759B`; only the mark in use carries a second, lifted colour for
dark backgrounds.

## The two directions

**Windfinder (a–e).** The Windfinders are the Sea Folk's channelers: they
find the wind and bind it to work, and their ships make port wherever the
bargain takes them. That is the shape of this CLI — `search`, `docs` and
`list` find a command; then it runs. The star-shaped diagram of wind
direction is itself called a *wind rose*, so navigation, wind and the
botanical naming the other repos use all land on the same figure.

It also rhymes with [Machin Shin](https://github.com/imagewize/mshin)
without colliding: Machin Shin is the wind that hunts in the dark, the
Windfinder is the wind that carries you where you meant to go. Same
element, opposite intent.

**Wheel (f–j).** The Wheel of Time has seven spokes, one for each Age — a
detail no icon set ships, which is why these are drawn rather than
borrowed. The case for it is that operations are cyclical and that the
Wheel is the parent symbol of a repo family otherwise named for
characters. The case against is that a wheel is a gear-adjacent shape: at
favicon size it reads as a settings icon, which is the generic trap the
current mark already falls into.

## The candidates

| File | Mark | Notes |
|------|------|-------|
| `a-windrose.svg` | Wind rose | **In use.** Four long cardinal points, four lighter intercardinals. The recognisable wind rose; holds at 32px in both themes. |
| `b-windrose-ring.svg` | Wind rose in a horizon ring | Outlined, more compass-like. The interior collapses below ~48px. |
| `c-windrose-star.svg` | Eight equal points | Reads as a star or sparkle more than a rose. |
| `d-windrose-four.svg` | Four points | The least busy and the most legible small, at the cost of the wind-rose reading. |
| `e-compass-needle.svg` | Compass needle in a ring | Finding the bearing rather than the whole rose. Mushes at 32px. |
| `f-wheel-seven.svg` | Seven-spoked wheel | Spokes from hub to rim. |
| `g-wheel-handles.svg` | Wheel with handles | Spokes overshoot the rim, ship's-wheel style. The most characterful wheel, but reads as a nautical helm. |
| `h-wheel-floating.svg` | Floating spokes | Spokes stop short of the rim. |
| `j-wheel-flat.svg` | Flat wheel | Filled rather than stroked, for favicon sizes. |

Rendered previews are not committed; regenerate them with

```bash
rsvg-convert -w 200 -h 200 -b white assets/logos/a-windrose.svg -o /tmp/a.png
```

## Dropped

A tenth candidate paired the seven-spoked wheel with the Great Serpent — the
snake eating its own tail, the emblem the books themselves use. It was
dropped rather than refined: without a head or a tapering tail the outer arc
reads as a ring someone forgot to close, not as a serpent, and there is no
room to draw either inside a 24×24 box at 2px strokes. The lore was in the
intent, not in what you could see.

# guiprev: headless GUI previews from the real UI tree

Builds the game's real GUI inside `harness/mock.luau`, dumps the instance tree, then lays it out and draws it with PIL.
Every image has a footer: **"approximate preview rendered from the real UI tree — not a Studio screenshot"**.

```bash
# any Computer app, any state of the client scene (about 3 s)
python3 tools/guiprev/guiprev.py --scene tools/guiprev/scenes/client.luau --state catalog \
    --viewport desktop --out out/guiprev/x.png [app=market] [--strip ShopScroll] [--dpr 2] [--report] [--debug]
tools/guiprev/render_shop.sh            # regenerates every Robux-shop image in out/guiprev/
```

| option | meaning |
|---|---|
| `--viewport desktop\|phone\|WxH` | desktop = 1280x720, insets 58,0,0,0 (Roblox top bar). phone = 844x390, insets 58,47,21,47 (iPhone 12-14 landscape: notch + home bar) |
| `--insets t,r,b,l` | override the CoreUISafeInsets area. `0,0,0,0` = the whole viewport |
| `--strip NAME` | also writes `<out>_strip_NAME.png`, the full canvas of that ScrollingFrame (the whole scroll list) |
| `--dpr N` | output pixel ratio (same layout, sharper; use 2 for phone shots) |
| `--passes N` | AbsoluteSize feedback passes (default 3, stops early once the sizes stop changing) |
| `--report` | text wider or taller than its box, elements clipped outside a scroll area, overlapping text |
| `--save-dump F` / `--from-json F` | keep the raw `@@GUI` dump, or render a saved one |
| `app=<id>` (after the options) | client scene: which Computer app to open (`empire lab data compute market studio arena campus shop`), `app=none` = HUD only |

Client scene states (`scenes/client.luau`): `soon` (shop as shipped), `catalog` (test ids and suggested prices),
`wired` (catalog plus the headhunter handler and investor multiplier), `owned` (VIP owned, a party voucher to redeem),
`toast` (owned, captured with the grant toast), `decor` (VIP BillboardGui, party banner and Founder Suite SurfaceGuis).
Ids and prices are injected only into the mock's in-memory ShopConfig. `work/src` is never written.

## A scene for another UI
A scene is a Luau script next to `scenes/client.luau`. It gets the args
`<genDir> <state> <vw> <vh> <t,r,b,l> <feedbackModule|-> [extra...]`, builds the UI with the mock, then:
```lua
local GuiDump = require("../guidump"); GuiDump.init(M)
GuiDump.setViewport(playerGui, vw, vh, insets)          -- ScreenGui.AbsoluteSize -> viewport-scaling code runs
GuiDump.applyFeedback({ playerGui }, feedback); M.settle(0.3)  -- AbsoluteSize/Position from guiprev.py
GuiDump.dump({ playerGui, aPartWithABillboard })        -- prints @@GUI lines
```
ScreenGuis are composed into the viewport image. BillboardGuis and SurfaceGuis are drawn standalone on a sheet
(`--ppstud` sets the pixels per stud for scale-sized BillboardGuis).

## What the layout follows
UDim2 against the parent's content box, `SizeConstraint`, AnchorPoint, UIPadding (scale and offset), UIListLayout
(direction, Padding, SortOrder LayoutOrder/Name/Custom, both alignments, Wraps), UIGridLayout (CellSize, CellPadding,
FillDirection, MaxCells, StartCorner, alignment), AutomaticSize from text metrics and children (list/grid extent plus
padding), UISizeConstraint, UIAspectRatioConstraint, UITextSizeConstraint, UIScale (around the anchor point; it
multiplies down the tree, text and strokes included), ScrollingFrame (canvas = max(CanvasSize, window), Automatic-
CanvasSize, ScrollBarInset, CanvasPosition, clipping, a drawn scrollbar), Visible, ClipsDescendants, ZIndexBehavior
Sibling/Global with ZIndex then child order, and DisplayOrder between ScreenGuis.
Drawing covers rounded corners, UIStroke (Border outside the box, Contextual around the glyphs), UIGradient (colour and
transparency keypoints, Rotation, Offset; also on strokes), text (wrapping, TextScaled that never splits a word,
truncation with an ellipsis, X/Y alignment, LineHeight, simple RichText `b i u s font br`, text stroke), BorderSizePixel,
and TextBox placeholders. Images are grey placeholder boxes labelled with their asset id.

Where the mock's typed default differs from Roblox and code never set the property, guidump uses the Roblox default:
TextX/YAlignment Center, UIScale 1, UIStroke black with Thickness 1, UICorner 0,8, UIListLayout Vertical/Left/Top/
LayoutOrder, TextStrokeTransparency 1, UISizeConstraint MaxSize inf, and so on (`ROBLOX_DEFAULTS` in guidump.luau).

## Approximations and what is ignored
* Fonts: Liberation Sans Regular/Bold, with DejaVu for missing glyphs (✓ ×). Builder Sans is not in the container,
  so widths are off by a few percent. Medium draws as Regular and ExtraBold as Bold plus a slight stroke.
  TextSize is treated as em px, and one line is TextSize × LineHeight tall.
* Not rendered: Rotation, UIFlexItem / flex fill, UIPageLayout / UITableLayout, CanvasGroup isolation, ViewportFrames,
  9-slice images, tweens in flight (the mock applies tween goals at once), the 3D world (a plain backdrop), BlurEffect,
  the Roblox top bar itself (only its inset is marked).
* Assumptions to check in Studio: AbsoluteSize/AbsolutePosition fed back to code are post-UIScale screen px, as in
  Roblox. Constraints and padding work in local pre-UIScale units. The phone preset's insets are values for one
  device.
* Rounding: layout is in float px, drawn at 2x supersampling, then downsampled.

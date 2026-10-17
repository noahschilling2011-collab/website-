export const meta = {
  name: 'ai-empire-gui-preview',
  description: 'Build a headless Roblox GUI snapshot renderer (dump real UI tree from the mock, lay out and draw with PIL) and render the Robux ShopApp states; independent fidelity check',
  phases: [
    { title: 'Build', detail: 'GUI dump + renderer + shop renders' },
    { title: 'Verify', detail: 'independent fidelity review against the UI code' },
    { title: 'Fix', detail: 'apply review fixes, final renders' },
  ],
}
const ROOT = '/tmp/claude-0/-home-user-website-/b11d0a70-15ce-5721-a0e0-6adea8266453/scratchpad'
const TASK = `Project: Roblox game "AI Empire". Sources in ${ROOT}/work/src (Roblox tree as files). Headless Roblox mock: ${ROOT}/harness/mock.luau (README ${ROOT}/harness/README.md), Luau runtime ${ROOT}/tools/luau, manifests via python3 ${ROOT}/harness/make_manifest.py --src ${ROOT}/work/src --gen ${ROOT}/harness/.gen_guiprev. The Robux shop UI is ${ROOT}/work/src/StarterPlayer/StarterPlayerScripts/Client/UI/Apps/ShopApp.module.luau (mounted inside UI/Screens/Computer.module.luau; styling from UI/Kit.module.luau and UI/Theme.module.luau; the shop package's client test ${ROOT}/tests/shop/test_client.luau already mounts it in the mock with a MarketplaceService test double — reuse its setup). NEVER modify anything under ${ROOT}/work or ${ROOT}/src or other packages' tests; work only in ${ROOT}/tools/guiprev/ and ${ROOT}/out/guiprev/.`
const BUILD = `${TASK}
GOAL: a reusable headless GUI preview tool, then preview images of the shop.
1. guidump.luau: helper that, inside the mock, walks a ScreenGui/GuiObject tree and prints JSON per GuiObject: class, name, path, Visible, Size/Position (UDim2 scale+offset), AnchorPoint, Rotation, ZIndex, LayoutOrder, BackgroundColor3/Transparency, BorderSizePixel, ClipsDescendants, AutomaticSize, Text/TextColor3/TextSize/TextScaled/TextWrapped/TextXAlignment/TextYAlignment/Font/FontFace(weight)/RichText, Image (just mark as image), ImageColor3/Transparency, ScrollingFrame CanvasSize/CanvasPosition, plus child modifiers UICorner(CornerRadius), UIStroke(Color,Thickness,Transparency), UIPadding, UIListLayout(FillDirection, Padding, SortOrder, alignments, Wraps), UIGridLayout(CellSize, CellPadding, FillDirectionMaxCells), UIScale(Scale), UIAspectRatioConstraint, UISizeConstraint, UIGradient (colour keypoints). Read the mock to see which properties it stores.
2. guiprev.py: lays out the dumped tree for a given viewport (e.g. 1280×720 and a phone 844×390): UDim2 resolution against the parent's absolute size, AnchorPoint, UIPadding, UIListLayout/UIGridLayout stacking (honour SortOrder LayoutOrder/Name, padding, alignment), AutomaticSize (approximate with text metrics), UIScale, ScrollingFrame clipping, Visible/ClipsDescendants, ZIndex/sibling order; draws with PIL: rounded rectangles (UICorner), strokes, gradients, text (use a bundled TTF font available in the container, e.g. DejaVuSans / Bold for bold weights; scale Roblox TextSize ≈ px), images as neutral placeholder boxes labelled with the image name. Label the output corner "approximate preview rendered from the real UI tree — not a Studio screenshot".
3. Render the real ShopApp (the Computer screen with the Shop app open) in these states and save PNGs to ${ROOT}/out/guiprev/: (a) the real config as shipped (all ids 0 → "Shop coming soon"), (b) a TEST configuration with placeholder ids injected ONLY in the mock (never in work/src) and the MarketplaceService test double returning plausible PriceInRobux values, showing the full catalogue (cash packs, vouchers, game passes), (c) same with one game pass owned ("Owned") and a voucher ready to redeem, (d) the phone-size viewport of (b). Also render the VIP name tag / any other shop-related GUI if it is a GUI (BillboardGui can be drawn standalone).
4. LOOK at every PNG with the Read tool; compare against the UI code; fix layout bugs in your renderer until the previews match the code's intent (you must not change the game UI itself). If the game UI itself has a real bug you notice (overlapping text, clipped buttons, unreadable contrast), list it precisely for the lead (file, line, problem) — do not fix it.
Final message: the PNG paths with one-line descriptions, how to run the tool for other UIs (one command), what the renderer approximates or ignores, and any real UI bugs found.`
const SCHEMA = { type: 'object', properties: {
  faithful: { type: 'boolean' },
  renderer_issues: { type: 'array', items: { type: 'string' } },
  game_ui_bugs: { type: 'array', items: { type: 'string' } } },
  required: ['faithful', 'renderer_issues', 'game_ui_bugs'] }
phase('Build')
const built = await agent(BUILD, { label: 'build:guiprev', phase: 'Build' })
phase('Verify')
const review = await agent(`${TASK}
You are an independent reviewer. Do NOT edit files. A colleague built a headless GUI preview tool in ${ROOT}/tools/guiprev/ and rendered the shop to ${ROOT}/out/guiprev/*.png. Their report: ${JSON.stringify(built).slice(0, 4000)}
Read the ShopApp/Computer/Kit/Theme code and the PNGs (Read tool). Judge whether the images faithfully represent what the code would show (positions, sizes, stacking, colours, texts, which items appear in each state). List renderer issues (wrong layout/colour/text vs code) and genuine game UI bugs (overlaps, clipping, contrast, missing states) with file:line.`, { label: 'verify:guiprev', phase: 'Verify', schema: SCHEMA })
phase('Fix')
const fixed = (review && !review.faithful && review.renderer_issues.length) ? await agent(`${BUILD}
CONTINUATION: you (or a colleague) already built the tool and first renders in ${ROOT}/tools/guiprev/ and ${ROOT}/out/guiprev/. An independent reviewer found these renderer issues — fix them all, re-render, LOOK again:
${JSON.stringify(review, null, 1)}`, { label: 'fix:guiprev', phase: 'Fix' }) : 'no fixes needed'
return { built, review, fixed }

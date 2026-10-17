# contact sheet of phone previews: python3 tests/phone/sheet.py out.png crop(x0,y0,x1,y1|full) cols img...
import sys
from PIL import Image, ImageDraw
out, crop, cols, files = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4:]
ims = []
for f in files:
    im = Image.open(f).convert("RGB")
    if crop != "full":
        x0, y0, x1, y1 = [int(v) for v in crop.split(",")]
        im = im.crop((x0, y0, x1, y1))
    ims.append((f.split("/")[-1], im))
w = max(i.width for _, i in ims); h = max(i.height for _, i in ims)
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * (h + 18)), (30, 30, 30))
d = ImageDraw.Draw(sheet)
for k, (name, im) in enumerate(ims):
    x, y = (k % cols) * w, (k // cols) * (h + 18)
    sheet.paste(im, (x, y + 18)); d.text((x + 4, y + 3), name, fill=(255, 255, 0))
sheet.save(out)
print(out, sheet.size)

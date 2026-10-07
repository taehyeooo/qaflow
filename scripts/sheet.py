# 캡처 여러 장을 라벨과 함께 한 장으로 붙인다(가로 한 줄 또는 격자). PIL이 없으면 붙이지 않고 파일 목록만 남긴다.
#   python3 sheet.py <출력.png> <열 수> <라벨1> <이미지1> [<라벨2> <이미지2> ...]
import sys, os
out, cols, pairs = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
items = list(zip(pairs[0::2], pairs[1::2]))
try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("PIL 없음 — 붙이지 않음:", *[p for _, p in items]); sys.exit(0)
imgs = [Image.open(p).convert("RGB") for _, p in items]
scale = 0.5  # 시뮬레이터 캡처(px)는 크다 — 절반으로 줄여 한눈에
imgs = [im.resize((int(im.width * scale), int(im.height * scale))) for im in imgs]
w = max(im.width for im in imgs); h = max(im.height for im in imgs)
pad, label_h = 24, 44
rows = (len(imgs) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w + (cols + 1) * pad, rows * (h + label_h) + (rows + 1) * pad), "white")
font = None
for f in ["/System/Library/Fonts/AppleSDGothicNeo.ttc", "/System/Library/Fonts/Supplemental/AppleGothic.ttf"]:
    if os.path.exists(f):
        font = ImageFont.truetype(f, 22); break
d = ImageDraw.Draw(sheet)
for i, ((label, _), im) in enumerate(zip(items, imgs)):
    r, c = divmod(i, cols)
    x = pad + c * (w + pad); y = pad + r * (h + label_h + pad)
    d.text((x, y), label, fill=(30, 30, 30), font=font)
    sheet.paste(im, (x, y + label_h))
    d.rectangle([x - 1, y + label_h - 1, x + im.width, y + label_h + im.height], outline=(210, 210, 205))
sheet.save(out)
print(out)

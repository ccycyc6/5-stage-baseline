import sys, re
from pypdf import PdfReader

path = sys.argv[1]
pats = [p.lower() for p in sys.argv[2:]]
r = PdfReader(path)
hits = 0
for i, page in enumerate(r.pages):
    try:
        t = page.extract_text() or ""
    except Exception as e:
        continue
    tl = t.lower()
    if any(p in tl for p in pats):
        hits += 1
        print(f"===== page {i+1} =====")
        print(t[:2500])
        if hits > 12:
            print("... more hits truncated")
            break
print("pages:", len(r.pages), "hits:", hits)

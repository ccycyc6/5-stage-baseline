import sys
from pypdf import PdfReader
path=sys.argv[1]; pats=sys.argv[2:]
r=PdfReader(path)
n=0
for i,p in enumerate(r.pages):
    t=p.extract_text() or ""
    if any(x in t for x in pats):
        n+=1
        print(f"===== page {i+1} =====")
        print(t[:3000])
print("pages",len(r.pages),"hits",n)

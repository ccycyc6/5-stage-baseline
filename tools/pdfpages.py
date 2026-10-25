import sys
from pypdf import PdfReader
path=sys.argv[1]; a=int(sys.argv[2]); b=int(sys.argv[3])
r=PdfReader(path)
for i in range(a-1,min(b,len(r.pages))):
    print(f"===== page {i+1} =====")
    print((r.pages[i].extract_text() or "")[:3500])

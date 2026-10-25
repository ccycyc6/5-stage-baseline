import re, io, collections
p = r"E:/qs/self_pro/fpga/pango/syn/synthesize/apm_drm_lutram_utilization.log"
lines = io.open(p, encoding="utf-8", errors="replace").read().split("\n")
tot = collections.Counter()
cur = None
for ln in lines:
    m = re.match(r"^\|\s*(\S.*?)\s*\|\s*(\d+)\s*x\s*(\d+)\s*\|\s*\|\s*\|\s*$", ln)
    if m:
        cur = m.group(1)
        continue
    m2 = re.match(r"^\|\s*\|\s*(\d+)\s*x\s*(\d+)\s*\|\s*(GTP_RAM\w+)\s*\|\s*(\d+)\s*\|", ln)
    if m2 and cur:
        bits = int(m2.group(1)) * int(m2.group(2)) * int(m2.group(4))
        mod = cur.split("/")
        key = "/".join(mod[:4]) if len(mod) > 4 else "/".join(mod)
        tot[key] += int(m2.group(4))
        cur = None
print("LUTRAM primitives (each = 1 LUT) by instance group:")
for k, v in tot.most_common(20):
    print("  %6d  %s" % (v, k))
print("  total  %d" % sum(tot.values()))

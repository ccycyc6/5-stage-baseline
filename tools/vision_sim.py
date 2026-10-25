W=H=32; N=W*H; G=16; F=G*G

def render(cls, cx, cy, r, noise, seed):
    st=[seed & 0xFFFFFFFF or 1]
    def rnd(rng):
        st[0]=(st[0]*1664525+1013904223)&0xFFFFFFFF
        return ((st[0]>>16)%rng)
    img=[0]*N
    rin=(r*55)//100
    for y in range(H):
        for x in range(W):
            dx=x-cx; dy=y-cy
            if cls==0: on = dx*dx+dy*dy <= r*r
            elif cls==1: on = (-r<=dx<=r and -r<=dy<=r)
            elif cls==2:
                h=y-(cy-r); on=False
                if 0<=h<=2*r:
                    half=(h*r)//(2*r); on = -half<=dx<=half
            elif cls==3:
                on = ((-r//3<=dx<=r//3 and -r<=dy<=r) or (-r//3<=dy<=r//3 and -r<=dx<=r))
            else:
                on = (rin*rin <= dx*dx+dy*dy <= r*r)
            img[y*W+x]=255 if on else 0
    if noise:
        for i in range(N):
            v=img[i]+rnd(2*noise+1)-noise
            img[i]=max(0,min(255,v))
    return img

def extract(img):
    lo=min(img); hi=max(img)
    if hi-lo<24: return None
    thr=(lo+hi)//2
    xs=[x for y in range(H) for x in range(W) if img[y*W+x]>thr]
    ys=[y for y in range(H) for x in range(W) if img[y*W+x]>thr]
    if not xs: return None
    x0,x1,y0,y1=min(xs),max(xs),min(ys),max(ys)
    bw,bh=x1-x0+1,y1-y0+1
    m=max(bw,bh)
    cx=(x0+x1)//2; cy=(y0+y1)//2
    # normalised 32x32 canvas: shape scaled so max(bw,bh) -> 24 px, centred
    tmp=[0]*N
    for y in range(H):
        sy=cy+((y-16)*m)//24
        for x in range(W):
            sx=cx+((x-16)*m)//24
            if 0<=sx<W and 0<=sy<H: tmp[y*W+x]=img[sy*W+sx]
    out=[0]*F
    for gy in range(G):
        for gx in range(G):
            acc=(tmp[(2*gy)*W+2*gx]+tmp[(2*gy)*W+2*gx+1]+
                 tmp[(2*gy+1)*W+2*gx]+tmp[(2*gy+1)*W+2*gx+1])
            out[gy*G+gx]=acc//4
    s=sum(out)//F
    out=[v-s for v in out]
    l1=sum(abs(v) for v in out)
    if l1==0: return None
    return [(v*256)//l1 for v in out]

classes=["circle","square","triangle","cross","ring"]
protos=[extract(render(c,16,16,12,0,7)) for c in range(5)]
print("protos ok:", all(p is not None for p in protos))
variants=[(12,0,0,0),(12,0,0,24),(11,3,-2,8),(13,-3,3,16)]
allpass=0; total=0; worst=0
for c in range(5):
    for v,(r,dx,dy,noise) in enumerate(variants):
        img=render(c,16+dx,16+dy,r,noise,0x1234+(c*7+v))
        f=extract(img)
        if f is None:
            print(f"  {classes[c]:9s} v{v} -> EMPTY"); total+=1; continue
        ds=[sum(abs(a-b) for a,b in zip(f,p)) for p in protos]
        best=min(range(5),key=lambda i:ds[i])
        total+=1; ok=(best==c); allpass+=ok
        worst=max(worst,ds[best])
        print(f"  {classes[c]:9s} v{v} -> {classes[best]:9s} {'ok' if ok else 'XX'} d={ds[best]:4d} all={ds}")
print(f"self test: {allpass}/{total}  worst best-distance {worst}")

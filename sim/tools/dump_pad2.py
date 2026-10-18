import sys, numpy as np
sys.path.insert(0, 'miniTensor/integration/tools')
import pack_weights as pw
d=np.load('miniTensor/integration/tools/detector_float.npz'); w1,w2,w3=d['w1'],d['w2'],d['w3']; wh,bh=d['wh'],d['bh']; xte=d['xte']
mx=[0.0]*4
for i in range(xte.shape[0]):
    a=xte[i]
    for li in range(3):
        L=pw.LAYERS[li]; a=pw.conv_float(a,[w1,w2,w3][li],[np.zeros(8),np.zeros(16),np.zeros(16)][li],L['pad'])
        if L['relu']: a=np.maximum(a,0)
        mx[li]=max(mx[li],float(np.max(np.abs(a))))
        if li<2: a=pw.pool2(a)
    mx[3]=max(mx[3],float(np.max(np.abs(pw.conv_float(a,wh.reshape(8,16,1,1),bh,0)))))
s_in=[1.0/127.0]+[m/127.0 for m in mx]
img=np.round(xte[0,:,:,0]/s_in[0]).astype(np.int32); img=np.clip(img,-128,127).reshape(32,32,1)
flat=np.zeros((32,32,4),dtype=np.int32); flat[:,:,0]=img[:,:,0]
im=(flat.reshape(-1)&0xFF).astype(np.uint8)
x=pw.from_mem(im,32,32,4)
pad=pw.pad_group(x,pw.LAYERS[0]).reshape(-1)
b=(pad&0xFF).astype(np.uint8)
print('PAD0B', bytes(b[256:768]).hex())

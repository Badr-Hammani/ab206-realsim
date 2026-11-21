import json,cv2,numpy as np,sys
from skimage.segmentation import watershed
pm=np.load(sys.argv[1]).astype(np.float32); T=float(sys.argv[2]) if len(sys.argv)>2 else 0.5
a=cv2.imread('area_sr.png');L=cv2.cvtColor(a,cv2.COLOR_BGR2LAB)[...,0].astype(np.float32)
m=(pm>T).astype(np.uint8)
dark=(L<cv2.blur(L,(21,21))-18).astype(np.uint8)          # wall lines / shadows split houses
m=m&(1-cv2.dilate(dark,np.ones((2,2),np.uint8)))
m=cv2.morphologyEx(m,cv2.MORPH_OPEN,np.ones((5,5),np.uint8))
m=cv2.morphologyEx(m,cv2.MORPH_CLOSE,np.ones((5,5),np.uint8))
dist=cv2.distanceTransform(m,cv2.DIST_L2,3)
pk=(dist>=7)&(dist==cv2.dilate(dist,np.ones((31,31),np.uint8)))
mk=cv2.connectedComponents(pk.astype(np.uint8))[1]
ws=watershed(-dist,mk,mask=m>0)
out=[]
for i in range(1,ws.max()+1):
    r=(ws==i).astype(np.uint8);ar=int(r.sum())
    if ar<4*40: continue            # < 10 m2
    cs,_=cv2.findContours(r,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE);c=max(cs,key=cv2.contourArea)
    rect=cv2.minAreaRect(c);box=cv2.boxPoints(rect);fill=ar/max(rect[1][0]*rect[1][1],1)
    poly=box if fill>0.72 else cv2.approxPolyDP(c,2.0,True).reshape(-1,2)
    if len(poly)<3: continue
    out.append({'poly':(np.asarray(poly,float)/2).round(1).tolist(),'area_m2':ar*0.0625,'shadow_px':0,'col':a[r>0].mean(0).tolist()})
json.dump(out,open(sys.argv[3] if len(sys.argv)>3 else 'pieces_rf.json','w'));print(len(out))

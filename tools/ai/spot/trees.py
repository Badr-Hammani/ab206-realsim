import os
import cv2,numpy as np,json
a=cv2.imread('area.png');H,W=a.shape[:2]
lab=cv2.cvtColor(a,cv2.COLOR_BGR2LAB).astype(np.float32);L=lab[...,0];A=lab[...,1]-128;B=lab[...,2]-128
mm=cv2.blur(L,(7,7)); sd=np.sqrt(np.maximum(cv2.blur(L*L,(7,7))-mm*mm,0))
veg=((((A<-6)&(L<130))|((A<-3)&(L<95)))&((L<100)|(sd>9))).astype(np.uint8)
veg=cv2.morphologyEx(veg,cv2.MORPH_OPEN,np.ones((3,3),np.uint8))
veg=cv2.morphologyEx(veg,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))
Z=json.load(open(os.environ.get('ZONES','zones.json')))
for q in Z.get('manual',[]): cv2.fillPoly(veg,[np.array(q['poly'],np.int32)],0)
d=cv2.distanceTransform(veg,cv2.DIST_L2,5)
pk=(d>=2.5)&(d==cv2.dilate(d,np.ones((9,9),np.uint8)))
n,lb,st,cen=cv2.connectedComponentsWithStats(pk.astype(np.uint8))
T=[]
for i in range(1,n):
    x,y=cen[i]; r=float(d[int(y),int(x)])
    # merge peaks too close
    if any((x-t[0])**2+(y-t[1])**2<(0.8*max(r,t[2]))**2 for t in T): continue
    T.append([float(x),float(y),r])
json.dump(T,open('trees.json','w'))
o=a.copy()
for x,y,r in T: cv2.circle(o,(int(x),int(y)),int(r+0.5),(0,255,255),1)
cv2.imwrite('trees_ov.png',o)
for i,(y,x) in enumerate([(600,0),(0,600)]):
  cv2.imwrite(f'tq{i}.jpg',np.hstack([a[y:y+400,x:x+400],o[y:y+400,x:x+400]]),[cv2.IMWRITE_JPEG_QUALITY,88])
r=np.array([t[2] for t in T])*0.5
print(len(T),'crown radius m pct',np.percentile(r,[10,50,90]))

import os
import cv2,numpy as np,json
a=cv2.imread('area.png');H,W=a.shape[:2]
lab=cv2.cvtColor(a,cv2.COLOR_BGR2LAB).astype(np.float32);L=lab[...,0];A=lab[...,1]-128;B=lab[...,2]-128
def sdk(k):
    m=cv2.blur(L,(k,k));return np.sqrt(np.maximum(cv2.blur(L*L,(k,k))-m*m,0))
sd=sdk(9)
Z=json.load(open(os.environ.get('ZONES','zones.json')))
inf=np.zeros((H,W),np.uint8);cv2.fillPoly(inf,[np.array(Z['include'][2],np.int32)],1)
veg=((A<-6)&(L<130))|((A<-3)&(L<90))
ground=(B>14)&(A>-4)&(L>140)&(sd<10)
ground=cv2.morphologyEx(ground.astype(np.uint8),cv2.MORPH_OPEN,np.ones((5,5),np.uint8))
ground=cv2.dilate(ground,np.ones((3,3),np.uint8))
for q in Z.get('remove',[]): cv2.fillPoly(inf,[np.array(q,np.int32)],0)
comp=((ground==0)&(inf>0)).astype(np.uint8)
comp=cv2.morphologyEx(comp,cv2.MORPH_OPEN,np.ones((7,7),np.uint8))
comp=cv2.morphologyEx(comp,cv2.MORPH_CLOSE,np.ones((5,5),np.uint8))
n,lb,st,_=cv2.connectedComponentsWithStats(comp,8)
keep=np.isin(lb,[i for i in range(1,n) if st[i,4]>=200])
# roof = compound minus trees/dark shadows
roof=keep&~veg&~(L<85)
roof=cv2.morphologyEx(roof.astype(np.uint8),cv2.MORPH_OPEN,np.ones((5,5),np.uint8))
cv2.imwrite('inf_roof.png',roof*255)
ov=a.copy();ov[roof>0]=(255,0,255);out=cv2.addWeighted(a,0.55,ov,0.45,0)
cs,_=cv2.findContours(roof,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
cv2.drawContours(out,cs,-1,(255,255,0),1)
cv2.imwrite('inf_ov.png',out)
def pair(y0,x0,n,o):
  cv2.imwrite(o,np.hstack([cv2.resize(a[y0:y0+n,x0:x0+n],(600,600)),cv2.resize(out[y0:y0+n,x0:x0+n],(600,600))]))
pair(900,200,250,'i_t1.png');pair(600,0,300,'i_t2.png')
loc=cv2.blur(L,(21,21))
dark=((L<loc-12)|(L<95)).astype(np.uint8)
cell=(roof>0)&(dark==0)
cell=cv2.morphologyEx(cell.astype(np.uint8),cv2.MORPH_OPEN,np.ones((3,3),np.uint8))
sd15=sdk(15)
sandy=(B>13)&(A>-4)&(L>135)&(sd15<16)
n,lb,st,_=cv2.connectedComponentsWithStats(cell,4)
cells=[]
out2=a.copy()
for i in range(1,n):
    if st[i,4]<60: continue
    m=(lb==i)
    if sandy[m].mean()>0.45: continue
    m8=m.astype(np.uint8)
    cs,_=cv2.findContours(m8,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    c=max(cs,key=cv2.contourArea)
    poly=cv2.approxPolyDP(c,1.5,True).reshape(-1,2)
    if len(poly)<3: continue
    cells.append({'poly':poly.tolist(),'area_m2':float(st[i,4])*0.25,'kind':'informal'})
    cv2.fillPoly(out2,[poly.astype(np.int32)],(255,0,255))
o=cv2.addWeighted(a,0.55,out2,0.45,0)
for c in cells: cv2.polylines(o,[np.array(c['poly'],np.int32)],True,(255,255,0),1)
json.dump(cells,open('inf_cells.json','w'))
cv2.imwrite('inf_ov2.png',o)
def pair2(y0,x0,n,on):
  cv2.imwrite(on,np.hstack([cv2.resize(a[y0:y0+n,x0:x0+n],(600,600)),cv2.resize(o[y0:y0+n,x0:x0+n],(600,600))]))
pair2(900,200,250,'i_t1.png');pair2(600,0,300,'i_t2.png')
print(len(cells))

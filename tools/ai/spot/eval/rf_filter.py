import json,cv2,numpy as np,sys
P=json.load(open(sys.argv[1]));pm=np.load(sys.argv[2]).astype(np.float32);T=float(sys.argv[3])
out=[]
for p in P:
    if p.get('manual'): out.append(p);continue
    z=np.zeros(pm.shape,np.uint8);cv2.fillPoly(z,[(np.array(p['poly'])*2).astype(np.int32)],1)
    v=pm[z>0].mean() if z.any() else 0
    if v>=T: out.append(p)
json.dump(out,open(sys.argv[4],'w'));print(len(P),'->',len(out))

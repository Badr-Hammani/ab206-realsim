import json,cv2,numpy as np,sys
G=json.load(open('/tmp/claude-0/boul/gt_user.json'))
fold=sys.argv[2] if len(sys.argv)>2 else 'all'
cx=lambda p:np.mean([q[0] for q in p])
sel=lambda p: fold=='all' or (fold=='A' and cx(p)<800) or (fold=='B' and cx(p)>=800)
G={'pos':[p for p in G['pos'] if sel(p)],'neg':[p for p in G['neg'] if sel(p)]};P=json.load(open(sys.argv[1] if len(sys.argv)>1 else 'pieces.json'))
def mask(polys):
    z=np.zeros((1200,1200),np.uint8)
    for p in polys: cv2.fillPoly(z,[np.array(p,np.int32)],1)
    return z
bm=mask([p['poly'] for p in P if not p.get('manual')])
pos=mask(G['pos']);neg=mask(G['neg'])&(pos==0)
ring=(cv2.dilate(pos,np.ones((9,9),np.uint8))>0)&(pos==0)&(neg==0)
rec=(bm&pos).sum()/pos.sum()
spill=bm[ring>0].mean()           # detection outside the real house edge (sidewalk etc.)
false=(bm&neg).sum()/max(neg.sum(),1)
score=round(100*(rec+(1-spill)+(1-false))/3)
print(json.dumps({'house_found':round(rec,2),'spill_past_edge':round(spill,2),'false_on_marked_wrong':round(false,2),'score':score}))

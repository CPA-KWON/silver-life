"""Offline articulated previews built from the existing original Kongi generator.
Designer PNGs remain the primary reference; these are approximations, not the
original artist's meshes. Rebuild without Blender or network access.
"""
import math,sys,json
from pathlib import Path
from build_kongi_3d import Model,build,quat
ROOT=Path(__file__).resolve().parents[1]
# Capture the existing generator's model without rewriting its original files.
def build_base(stage):
 saved=Model.save;captured=[]
 def capture(self,path):captured.append(self)
 Model.save=capture
 try:build(stage)
 finally:Model.save=saved
 return captured[0]

def triangle(m):
 points=[[-.17,0,0],[.17,0,0],[0,.34,0],[-.13,0,-.14],[.13,0,-.14],[0,.30,-.14]]
 faces=[(0,1,2),(5,4,3),(0,3,4),(0,4,1),(1,4,5),(1,5,2),(2,5,3),(2,3,0)]
 p=[];n=[];idx=[]
 for face in faces:
  a,b,c=[points[i] for i in face];u=[b[i]-a[i] for i in range(3)];v=[c[i]-a[i] for i in range(3)]
  normal=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];length=math.sqrt(sum(x*x for x in normal));normal=[x/length for x in normal]
  for vertex in [a,b,c]:idx.append(len(p)//3);p.extend(vertex);n.extend(normal)
 m.geometry['earTriangle']=(m.accessor(p,'VEC3',bounds=True,target=34962),m.accessor(n,'VEC3',target=34962),m.accessor(idx,'SCALAR',5123,target=34963))

colors={'walk_vest':(222,146,69),'flower_cardigan':(225,185,182),'raincoat':(238,200,58),'winter_coat':(55,77,121),'outing_overall':(81,144,155),'walk_hat':(181,167,111),'flower_pin':(242,166,190),'ribbon':(207,94,113),'first_walk_badge':(241,190,52),'outing_scarf':(204,105,87),'stripe_knit':(78,159,170),'beret':(203,93,124),'moon_scarf':(38,65,113)}
manifest=json.loads((ROOT/'docs/plans/pet_expansion_catalog_20261029.json').read_text())['items']
for species in ['dog','cat']:
 for stage in range(3):
  m=build_base(stage);head=next(i for i,n in enumerate(m.g['nodes']) if n['name']=='HeadPivot')
  head_y=[1.52,1.72,1.96][stage];body_y=[.67,.78,.9][stage];height=[.49,.60,.72][stage];width=[.43,.48,.52][stage];neck=head_y-.52
  if species=='cat':
   for mat in m.g['materials']:
    if mat['name'] in ['fur','ear']:mat['pbrMetallicRoughness']['baseColorFactor']=[.67,.69,.73,1]
    if mat['name'] in ['cream','belly']:mat['pbrMetallicRoughness']['baseColorFactor']=[.92,.92,.90,1]
   for node in m.g['nodes']:
    if node['name'].startswith(('Ear','Forelock')):node['scale']=[0,0,0]
    if node['name']=='Tail':node['scale']=[.6,1.8,.8]
   triangle(m);m.material('innerEar',(224,174,185),.8);m.material('catStripe',(113,112,130),.8)
   for sign in [-1,1]:
    m.node('PointedEar'+str(sign),head,p=[sign*.42,.43,.03],material='fur',geo='earTriangle')
    m.node('PinkEar'+str(sign),head,p=[sign*.42,.48,.035],scale=[.58,.60,.5],material='innerEar',geo='earTriangle')
   for material in m.g['materials']:
    if material['name']=='nose':material['pbrMetallicRoughness']['baseColorFactor']=[.84,.48,.56,1]
   for node in m.g['nodes']:
    if node['name']=='Nose':node['scale']=[.055,.035,.035]
    if node['name']=='Muzzle':node['scale']=[.20,.11,.08]
   for sign in [-1,1]:
    for delta in [-.03,.03]:m.node('Whisker'+str(sign)+str(delta),head,p=[sign*.30,-.28+delta,.48],scale=[.12,.005,.006],material='catStripe')
   for x in [-.13,0,.13]:m.node('ForeheadStripe'+str(x),head,p=[x,.38,.39],scale=[.025,.09,.014],material='catStripe')
  for material in m.g['materials']:
   if material['name'] in ['blue','gold']:material['alphaMode']='BLEND'
  for item in manifest:
   if item['species']!=species:continue
   ident=item['id'];suffix=ident.split('_',1)[1];rgb=colors[suffix]
   # Match each species' delivered wardrobe art, rather than reusing dog colors.
   overrides={
    'dog_flower_cardigan':(192,183,169),'dog_outing_overall':(75,108,156),
    'dog_flower_pin':(148,185,156),
    'cat_walk_vest':(104,159,179),'cat_stripe_knit':(200,136,152),
    'cat_raincoat':(142,175,89),'cat_flower_cardigan':(154,138,172),
    'cat_outing_overall':(181,143,84),'cat_ribbon':(127,137,161),
    'cat_first_walk_badge':(181,170,201),
   }
   rgb=overrides.get(ident,rgb)
   material='item:'+ident;m.material(material,rgb,.72,hidden=True)
   if item['slot']=='body':
    m.node(ident,p=[0,body_y,0],scale=[width+.035,height*.86,.40+.025*stage],material=material)
    if suffix in ['walk_vest','stripe_knit']:
     m.material(material+':stripe',(241,230,207),.8,hidden=True)
     for i in range(3):
      y=body_y-height*.45+i*height*.4
      radius=math.sqrt(max(.1,1-((y-body_y)/(height*.86))**2))
      m.node(ident+'Stripe'+str(i),p=[0,y,0],scale=[(width+.037)*radius,.25,(.402+.025*stage)*radius],material=material+':stripe',geo='torus')
   elif item['slot']=='head':
    if suffix in ['walk_hat','beret']:
     m.node(ident,head,p=[0,.54,0],scale=[.52,.18,.43],material=material)
     if suffix=='walk_hat':m.node(ident+'Brim',head,p=[0,.49,0],scale=[.76,.045,.61],material=material)
    else:
     for i in range(5):
      a=i*math.tau/5;m.node(ident+str(i),head,p=[-.48+.07*math.cos(a),.37+.07*math.sin(a),.36],scale=[.06,.06,.025],material=material)
   elif item['slot']=='neck':
    m.node(ident,p=[0,neck,.03],scale=[.42,.7,.34],material=material,geo='torus')
    m.node(ident+'End',p=[.08,neck-.16,.39],scale=[.17,.18,.035],angle=-.35,axis=[0,0,1],material=material)
   else:m.node(ident,p=[-.21,neck-.13,.395],scale=[.085,.10,.023],material=material)
  t=[0,.2,.4,.6,.8,1]
  m.animation('Happy',[(head,'rotation',t,[quat([0,0,1],v) for v in [0,.12,-.12,.12,-.08,0]])])
  path=ROOT/'assets/pet/models'/f'{species}_{["baby","junior","adult"][stage]}.glb';m.save(path);print(path.name,path.stat().st_size)

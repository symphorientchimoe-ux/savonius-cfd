// Plan z = 0 du maillage 3D par extrusion (scripts/maillage3d_extrusion.sh) : même section que savonius2D.geo
// (11 couches limites autour des pales et de l'arbre), avec quatre régions extrudées sur une maille d'épaisseur dz :
// fluide (disque tournant moins les pales), pale (intérieur des pales et de l'arbre), anneau (domaine fixe hors du disque),
// couvercle (disque fixe, superposé au disque tournant). OpenFOAM empile ensuite ces régions en hauteur.
// Usage : gmsh -3 -format msh2 savonius3D_plan.geo [-setnumber hb 0.005 ...]
SetFactory("OpenCASCADE");

c  = 0.68; Rb = 0.50; t = 0.0015; rs = 0.0225; Rr = 0.90;
DefineConstant[ xmin = -14, xmax = 34, ymax = 14 ];
DefineConstant[ hb = 0.005, htip = 0.003, hami = 0.03, hfar = 0.6, hwake = 0.12,
                bl1 = 1e-4, blT = 0.003, blR = 1.2, tm = 0.004, blQuads = 1 ];
If (tm > 0)
  t = tm;
EndIf

// ---------- section 2D (comme savonius2D.geo, mais l'intérieur des pales est gardé) ----------
d = Sqrt(Rb^2 - (c/2)^2);
blades[] = {};
For i In {0:3}
  th = -Pi/2 + i*Pi/2;
  ex = Cos(th); ey = Sin(th);
  nx = ey;      ny = -ex;
  cx = c/2*ex + d*nx; cy = c/2*ey + d*ny;
  dO = news; Disk(dO) = {cx, cy, 0, Rb + t/2};
  dI = news; Disk(dI) = {cx, cy, 0, Rb - t/2};
  ring() = BooleanDifference{ Surface{dO}; Delete; }{ Surface{dI}; Delete; };
  p1 = newp; Point(p1) = {cx, cy, 0};
  p2 = newp; Point(p2) = {cx + 3*(0 - cx), cy + 3*(0 - cy), 0};
  p3 = newp; Point(p3) = {cx + 3*(c*ex - cx), cy + 3*(c*ey - cy), 0};
  l1 = newl; Line(l1) = {p1, p2};
  l2 = newl; Line(l2) = {p2, p3};
  l3 = newl; Line(l3) = {p3, p1};
  cl = newll; Curve Loop(cl) = {l1, l2, l3};
  tri = news; Plane Surface(tri) = {cl};
  b() = BooleanIntersection{ Surface{ring()}; Delete; }{ Surface{tri}; Delete; };
  dt_ = news; Disk(dt_) = {c*ex, c*ey, 0, t/2};
  b2() = BooleanUnion{ Surface{b()}; Delete; }{ Surface{dt_}; Delete; };
  blades[] += b2();
EndFor
sh = news; Disk(sh) = {0, 0, 0, rs};
solid() = BooleanUnion{ Surface{blades[0]}; Delete; }{ Surface{blades[{1:3}], sh}; Delete; };

// disque tournant découpé par les pales : fluide + intérieur des pales, avec des courbes communes
dr = news; Disk(dr) = {0, 0, 0, Rr};
frag() = BooleanFragments{ Surface{dr}; Delete; }{ Surface{solid()}; Delete; };
fluR() = {}; pal() = {};
For k In {0:#frag()-1}
  bb() = BoundingBox Surface{frag(k)};
  If (bb(3) - bb(0) > 1.9*Rr)          // disque tournant : 1,8 m ; pales : 1,36 m
    fluR() += frag(k);
  Else
    pal() += frag(k);
  EndIf
EndFor
// domaine fixe : rectangle découpé par le cercle en un anneau et un couvercle (courbe commune) ;
// le couvercle se superpose au disque tournant sans lui être relié (interface glissante non conforme)
rc = news; Rectangle(rc) = {xmin, -ymax, 0, xmax - xmin, 2*ymax};
dh = news; Disk(dh) = {0, 0, 0, Rr};
fs() = BooleanFragments{ Surface{rc}; Delete; }{ Surface{dh}; Delete; };
anneau() = {}; couv() = {};
For k In {0:#fs()-1}
  bb() = BoundingBox Surface{fs(k)};
  If (bb(3) - bb(0) > 2.5*Rr)
    anneau() += fs(k);
  Else
    couv() += fs(k);
  EndIf
EndFor
Printf("fluide tournant %g, pales %g, anneau %g, couvercle %g", #fluR(), #pal(), #anneau(), #couv());

// ---------- tailles de maille (comme en 2D) ----------
rotB() = Boundary{ Surface{fluR()}; };
bladeCurves() = {};
For k In {0:#rotB()-1}
  bb() = BoundingBox Curve{ Abs(rotB(k)) };
  If (bb(3) - bb(0) < 1.9*Rr)
    bladeCurves() += Abs(rotB(k));
  EndIf
EndFor
Field[1] = Distance;  Field[1].CurvesList = {bladeCurves()}; Field[1].Sampling = 400;
Field[2] = Threshold; Field[2].InField = 1; Field[2].SizeMin = hb; Field[2].SizeMax = hami;
Field[2].DistMin = 0.004; Field[2].DistMax = 0.12; Field[2].StopAtDistMax = 1;
Field[3] = Box; Field[3].VIn = hwake; Field[3].VOut = hfar;
Field[3].XMin = -1.5; Field[3].XMax = 10; Field[3].YMin = -1.8; Field[3].YMax = 1.8; Field[3].Thickness = 3;
Field[4] = Box; Field[4].VIn = hami; Field[4].VOut = hfar;
Field[4].XMin = -1.0; Field[4].XMax = 1.0; Field[4].YMin = -1.0; Field[4].YMax = 1.0; Field[4].Thickness = 0.6;
bladePts() = PointsOf{ Curve{bladeCurves()}; };
Field[6] = Distance;  Field[6].PointsList = {bladePts()};
Field[7] = Threshold; Field[7].InField = 6; Field[7].SizeMin = htip; Field[7].SizeMax = hb;
Field[7].DistMin = 0.002; Field[7].DistMax = 0.03; Field[7].StopAtDistMax = 1;
Field[5] = Min; Field[5].FieldsList = {2, 3, 4, 7};
Background Field = 5;
Field[10] = BoundaryLayer;
Field[10].CurvesList = {bladeCurves()};
Field[10].ExcludedSurfacesList = {pal()};     // pas de couches à l'intérieur de la tôle
Field[10].Size = bl1; Field[10].Ratio = blR; Field[10].Thickness = blT;
Field[10].Quads = blQuads;
BoundaryLayer Field = 10;
Mesh.MeshSizeExtendFromBoundary = 0;
Mesh.MeshSizeFromPoints = 0;
Mesh.MeshSizeFromCurvature = 0;
Mesh.Algorithm = 6;


// ---------- une maille d'épaisseur, groupes physiques ----------
dz = 0.01; eps = 1e-4;
eF[] = Extrude {0, 0, dz} { Surface{fluR(), pal()}; Layers{1}; Recombine; };
v1() = Volume{:};
eS[] = Extrude {0, 0, dz} { Surface{anneau(), couv()}; Layers{1}; Recombine; };
v2() = Volume{:}; v2() -= v1();
vP() = {}; vF() = {}; vA() = {}; vC() = {};
For k In {0:#v1()-1}
  bb() = BoundingBox Volume{v1(k)};
  If (bb(3) - bb(0) < 1.9*Rr)
    vP() += v1(k);
  Else
    vF() += v1(k);
  EndIf
EndFor
For k In {0:#v2()-1}
  bb() = BoundingBox Volume{v2(k)};
  If (bb(3) - bb(0) < 2.5*Rr)
    vC() += v2(k);
  Else
    vA() += v2(k);
  EndIf
EndFor
Printf("volumes : fluide %g, pale %g, anneau %g, couvercle %g", #vF(), #vP(), #vA(), #vC());
Physical Volume("fluide")    = {vF()};
Physical Volume("pale")      = {vP()};
Physical Volume("anneau")    = {vA()};
Physical Volume("couvercle") = {vC()};
Physical Surface("bas")    = Surface In BoundingBox{xmin-eps, -ymax-eps, -eps, xmax+eps, ymax+eps, eps};
Physical Surface("haut")   = Surface In BoundingBox{xmin-eps, -ymax-eps, dz-eps, xmax+eps, ymax+eps, dz+eps};
Physical Surface("inlet")  = Surface In BoundingBox{xmin-eps, -ymax-eps, -eps, xmin+eps, ymax+eps, dz+eps};
Physical Surface("outlet") = Surface In BoundingBox{xmax-eps, -ymax-eps, -eps, xmax+eps, ymax+eps, dz+eps};
Physical Surface("sides")  = {Surface In BoundingBox{xmin-eps, -ymax-eps, -eps, xmax+eps, -ymax+eps, dz+eps},
                              Surface In BoundingBox{xmin-eps,  ymax-eps, -eps, xmax+eps,  ymax+eps, dz+eps}};
// bord du disque tournant (côté tournant de l'interface)
bF() = Abs(Boundary{ Volume{vF()}; });
amiR() = {};
For k In {0:#bF()-1}
  bb() = BoundingBox Surface{ bF(k) };
  If (bb(5) - bb(2) > eps && Max(Max(Abs(bb(0)), Abs(bb(3))), Max(Abs(bb(1)), Abs(bb(4)))) > Rr - 1e-3)
    amiR() += bF(k);
  EndIf
EndFor
Physical Surface("AMI1") = {amiR()};

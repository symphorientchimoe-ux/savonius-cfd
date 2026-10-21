// Rotor Savonius 4 pales du prototype CNDT (plans SolidWorks 2018)
// Pales en arc : corde 0.68 m depuis l'axe, rayon 0.50 m, tole 1.5 mm, H = 1.00 m, D = 1.354 m
// Vent selon +x, rotation antihoraire autour de +z (omega > 0)
SetFactory("OpenCASCADE");

c  = 0.68;     // corde de la pale [m]
Rb = 0.50;     // rayon de courbure [m]
t  = 0.0015;   // epaisseur tole 15/10 [m]
rs = 0.0225;   // rayon de l'arbre [m]
Rr = 0.90;     // rayon de la zone tournante (AMI) [m]
dz = 0.1;      // epaisseur d'extrusion 2D [m]
// domaine : 5D amont, 15D aval, 10D de large (modifiable : -setnumber ymax 14)
DefineConstant[ xmin = -7, xmax = 20, ymax = 7 ];

// tailles de maille (modifiables en ligne de commande : -setnumber hb 0.002)
DefineConstant[ hb = 0.0015, htip = 0.0015, hami = 0.02, hfar = 0.30, hwake = 0.07,
                bl1 = 1.5e-4, blT = 0.003, blR = 1.2, useBL = 0, ext = 1, tm = 0,
                blQuads = 1, blArbre = 0 ];
// Nb : nombre de pales ; ec : écartement, décalage radial de chaque pale vers l'extérieur [m]
// (pied de pale à ec de l'axe, bout à c + ec) ; Nb = 4 et ec = 0 : rotor CNDT
DefineConstant[ Nb = 4, ec = 0 ];
// tm > 0 : epaisseur de pale modelisee (et diametre du bout arrondi), pour grossir les mailles du bout
If (tm > 0)
  t = tm;
EndIf

d = Sqrt(Rb^2 - (c/2)^2);
blades[] = {};
For i In {0:Nb-1}
  th = -Pi/2 + i*2*Pi/Nb;
  ex = Cos(th); ey = Sin(th);
  nx = ey;      ny = -ex;          // centre de l'arc du cote amont pour la pale "avancante"
  cx = (c/2 + ec)*ex + d*nx; cy = (c/2 + ec)*ey + d*ny;
  dO = news; Disk(dO) = {cx, cy, 0, Rb + t/2};
  dI = news; Disk(dI) = {cx, cy, 0, Rb - t/2};
  ring() = BooleanDifference{ Surface{dO}; Delete; }{ Surface{dI}; Delete; };
  // triangle limitant l'anneau au secteur [axe -> bout de pale]
  p1 = newp; Point(p1) = {cx, cy, 0};
  p2 = newp; Point(p2) = {cx + 3*(ec*ex - cx), cy + 3*(ec*ey - cy), 0};
  p3 = newp; Point(p3) = {cx + 3*((c + ec)*ex - cx), cy + 3*((c + ec)*ey - cy), 0};
  l1 = newl; Line(l1) = {p1, p2};
  l2 = newl; Line(l2) = {p2, p3};
  l3 = newl; Line(l3) = {p3, p1};
  cl = newll; Curve Loop(cl) = {l1, l2, l3};
  tri = news; Plane Surface(tri) = {cl};
  b() = BooleanIntersection{ Surface{ring()}; Delete; }{ Surface{tri}; Delete; };
  // bout de pale arrondi (chant de la tole)
  dt_ = news; Disk(dt_) = {(c + ec)*ex, (c + ec)*ey, 0, t/2};
  If (ec > 0)
    dr_ = news; Disk(dr_) = {ec*ex, ec*ey, 0, t/2};   // pied de pale arrondi, détaché de l'arbre
    b2() = BooleanUnion{ Surface{b()}; Delete; }{ Surface{dt_, dr_}; Delete; };
  Else
    b2() = BooleanUnion{ Surface{b()}; Delete; }{ Surface{dt_}; Delete; };
  EndIf
  blades[] += b2();
EndFor
sh = news; Disk(sh) = {0, 0, 0, rs};
solid() = BooleanUnion{ Surface{blades[0]}; Delete; }{ Surface{blades[{1:Nb-1}], sh}; Delete; };

dr = news; Disk(dr) = {0, 0, 0, Rr};
rotor() = BooleanDifference{ Surface{dr}; Delete; }{ Surface{solid()}; Delete; };

rc = news; Rectangle(rc) = {xmin, -ymax, 0, xmax - xmin, 2*ymax};
dh = news; Disk(dh) = {0, 0, 0, Rr};
stator() = BooleanDifference{ Surface{rc}; Delete; }{ Surface{dh}; Delete; };

// courbes des pales = bord du rotor sauf le cercle AMI
rotB() = Boundary{ Surface{rotor()}; };
bladeCurves() = {}; faceCurves() = {};
For k In {0:#rotB()-1}
  bb() = BoundingBox Curve{ Abs(rotB(k)) };
  If (bb(3) - bb(0) < 1.5*Rr)
    bladeCurves() += Abs(rotB(k));
    If (Max(Max(Abs(bb(0)), Abs(bb(3))), Max(Abs(bb(1)), Abs(bb(4)))) > 0.05)
      faceCurves() += Abs(rotB(k));   // faces et bouts arrondis des pales (hors arbre)
    EndIf
  EndIf
EndFor

// champs de taille
Field[1] = Distance;  Field[1].CurvesList = {bladeCurves()}; Field[1].Sampling = 400;
Field[2] = Threshold; Field[2].InField = 1; Field[2].SizeMin = hb; Field[2].SizeMax = hami;
Field[2].DistMin = 0.004; Field[2].DistMax = 0.12; Field[2].StopAtDistMax = 1;
Field[3] = Box; Field[3].VIn = hwake; Field[3].VOut = hfar;
Field[3].XMin = -1.5; Field[3].XMax = 10; Field[3].YMin = -1.8; Field[3].YMax = 1.8; Field[3].Thickness = 3;
Field[4] = Box; Field[4].VIn = hami; Field[4].VOut = hfar;
Field[4].XMin = -1.0; Field[4].XMax = 1.0; Field[4].YMin = -1.0; Field[4].YMax = 1.0; Field[4].Thickness = 0.6;
// sommets des pales (bouts, jonctions avec l'arbre)
bladePts() = PointsOf{ Curve{bladeCurves()}; };
Field[6] = Distance;  Field[6].PointsList = {bladePts()};
Field[7] = Threshold; Field[7].InField = 6; Field[7].SizeMin = htip; Field[7].SizeMax = hb;
Field[7].DistMin = 0.002; Field[7].DistMax = 0.03; Field[7].StopAtDistMax = 1;
Field[5] = Min; Field[5].FieldsList = {2, 3, 4, 7};
Background Field = 5;

If (useBL)
Field[10] = BoundaryLayer;
If (blArbre)
  Field[10].CurvesList = {bladeCurves()};   // couche limite aussi sur l'arbre
Else
  Field[10].CurvesList = {faceCurves()};
EndIf
Field[10].Size = bl1; Field[10].Ratio = blR; Field[10].Thickness = blT;
Field[10].Quads = blQuads;
BoundaryLayer Field = 10;
EndIf

Mesh.MeshSizeExtendFromBoundary = 0;
Mesh.MeshSizeFromPoints = 0;
Mesh.MeshSizeFromCurvature = 0;
Mesh.Algorithm = 6;

If (ext)
// extrusion d'une couche pour OpenFOAM
exR[] = Extrude {0, 0, dz} { Surface{rotor()};  Layers{1}; Recombine; };
exS[] = Extrude {0, 0, dz} { Surface{stator()}; Layers{1}; Recombine; };

eps = 1e-3;
Physical Volume("rotor")  = {exR[1]};
Physical Volume("stator") = {exS[1]};
Physical Surface("inlet")  = Surface In BoundingBox{xmin-eps, -ymax-eps, -eps, xmin+eps, ymax+eps, dz+eps};
Physical Surface("outlet") = Surface In BoundingBox{xmax-eps, -ymax-eps, -eps, xmax+eps, ymax+eps, dz+eps};
Physical Surface("sides")  = {Surface In BoundingBox{xmin-eps, -ymax-eps, -eps, xmax+eps, -ymax+eps, dz+eps},
                              Surface In BoundingBox{xmin-eps,  ymax-eps, -eps, xmax+eps,  ymax+eps, dz+eps}};
Physical Surface("frontAndBack") = {rotor(), stator(), exR[0], exS[0]};
// lateral surfaces of the rotor extrusion: AMI cylinder + blade walls
latR() = {};
For k In {2:#exR[]-1}
  latR() += exR[k];
EndFor
amiR() = {}; wallR() = {};
For k In {0:#latR()-1}
  bb() = BoundingBox Surface{latR(k)};
  If (bb(3) - bb(0) > 1.5*Rr)
    amiR() += latR(k);
  Else
    wallR() += latR(k);
  EndIf
EndFor
latS() = {};
For k In {2:#exS[]-1}
  bb() = BoundingBox Surface{exS[k]};
  If (bb(3) - bb(0) > 1.5*Rr && bb(3) - bb(0) < 2.5*Rr)
    latS() += exS[k];
  EndIf
EndFor
Physical Surface("AMI1")   = {amiR()};
Physical Surface("AMI2")   = {latS()};
Physical Surface("blades") = {wallR()};
EndIf

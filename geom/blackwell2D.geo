// Rotor de validation de Blackwell et al. 1977 (Sandia SAND76-0131) : 2 godets demi-circulaires,
// corde (diamètre du godet) 0,5 m, recouvrement s/c = 0,15, hauteur 1 m (H/c = 2), sans arbre.
// D = 2c - s = 0,925 m. Même domaine, mêmes champs de taille et mêmes patchs que savonius2D.geo.
// Vent selon +x, rotation antihoraire (le godet du bas reçoit le vent côté creux).
SetFactory("OpenCASCADE");

c  = 0.50;     // corde du godet [m]
sr = 0.15;     // recouvrement s/c
rs = 0.0;      // pas d'arbre (gardé pour les tests de courbes)
Rr = 0.62;     // rayon de la zone tournante (AMI) [m]
dz = 0.1;      // épaisseur d'extrusion 2D [m]
DefineConstant[ xmin = -7, xmax = 20, ymax = 7 ];

DefineConstant[ hb = 0.0025, htip = 0.0025, hami = 0.015, hfar = 0.30, hwake = 0.07,
                bl1 = 1.5e-4, blT = 0.003, blR = 1.2, useBL = 0, ext = 1, tm = 0.004 ];
t = tm;        // épaisseur de godet modélisée [m]

a = (c - sr*c)/2;   // distance de l'axe au centre de chaque godet
blades[] = {};
For i In {0:1}
  sg = 1 - 2*i;                    // +1 : godet du haut (centre (+a,0)), -1 : godet du bas (centre (-a,0))
  cx = sg*a;
  dO = news; Disk(dO) = {cx, 0, 0, c/2 + t/2};
  dI = news; Disk(dI) = {cx, 0, 0, c/2 - t/2};
  ring() = BooleanDifference{ Surface{dO}; Delete; }{ Surface{dI}; Delete; };
  // demi-plan y > 0 pour le godet du haut, y < 0 pour celui du bas
  hp = news; Rectangle(hp) = {cx - c, (sg > 0 ? 0 : -c), 0, 2*c, c};
  b() = BooleanIntersection{ Surface{ring()}; Delete; }{ Surface{hp}; Delete; };
  // bouts arrondis
  d1 = news; Disk(d1) = {cx - c/2, 0, 0, t/2};
  d2 = news; Disk(d2) = {cx + c/2, 0, 0, t/2};
  b2() = BooleanUnion{ Surface{b()}; Delete; }{ Surface{d1, d2}; Delete; };
  blades[] += b2();
EndFor
solid() = BooleanUnion{ Surface{blades[0]}; Delete; }{ Surface{blades[1]}; Delete; };

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
    If (1)
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
Field[10].CurvesList = {faceCurves()};
Field[10].Size = bl1; Field[10].Ratio = blR; Field[10].Thickness = blT;
Field[10].Quads = 1;
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

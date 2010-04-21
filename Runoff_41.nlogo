extensions [ gis table widget41 ]
globals [ landuse-code-name 
          landuse-name-code 
          landuse-name-color 
          landuse-flow-velocity
          landuse-curve-numbers
          landuse-menu-values
          soil-a
          soil-b
          soil-c
          watershed-boundary
          flow-direction 
          slope
          stream-distance
          in-stream-dist
          border 
          interior 
          watershed 
          base-stepsize
          outlet
          outlet-flow
          pen-number ]
patches-own [ luc landuse exit-count ]
turtles-own [ q ]
__includes [ "data/NationalLandCoverDatasetLevel1.nls" ]


to setup
  ca
  setup-landuse-tables
  show "loading grid data..."
  set flow-direction convert-flow-directions gis:load-dataset "data/flowdirection.asc"
  show gis:envelope-of flow-direction
  if world-width != ((floor (gis:width-of flow-direction / 2)) + 2) or world-height != ((floor (gis:height-of flow-direction / 2)) + 2)
  [ user-message (word "Please open the Settings window and set max-pxcor to " 
                       ((floor (gis:width-of flow-direction / 2)) + 1) 
                       " and max-pycor to " 
                       ((floor (gis:height-of flow-direction / 2)) + 1))
    stop ]
  gis:set-transformation-ds gis:envelope-of flow-direction (list (min-pxcor + 1) (max-pxcor - 1)  (min-pycor + 1) (max-pycor - 1))
  let env gis:envelope-of flow-direction
  let w item 1 env - item 0 env
  let h item 3 env - item 2 env
  ifelse w > h
  [ set in-stream-dist 0.0004 / w ]
  [ set in-stream-dist 0.0004 / h ]
  set slope gis:load-dataset "data/slope.asc"
  set stream-distance gis:load-dataset "data/streamdistance.asc"
  show "loading watershed boundary..."
  set watershed-boundary first gis:feature-list-of gis:load-dataset "data/watershed.shp"
  set border patches with [ pxcor = min-pxcor or pxcor = max-pxcor or pycor = min-pycor or pycor = max-pycor ]
  set interior patches with [ not member? self border ]
  set watershed interior gis:intersecting watershed-boundary ; interior with [ gis:intersects? watershed-boundary self ]
  show "loading soil type data"
  let soil-dataset gis:load-dataset "data/soilgroup.shp"
  set soil-a gis:find-one-feature soil-dataset "SOILTYPE_H" "A"
  set soil-b gis:find-one-feature soil-dataset "SOILTYPE_H" "B"
  set soil-c gis:find-one-feature soil-dataset "SOILTYPE_H" "C"
  show "loading aerial photo from Terraserver..."
  carefully
  [ gis:import-wms-drawing "http://terraservice.net/ogcmap.ashx" "EPSG:4326" "DOQ" 128 ]
  [ show "Unable to import photo from Terraserver. Check your network connection." ]
  gis:set-drawing-color white
  gis:draw watershed-boundary 2
  set base-stepsize  0.5 / (sqrt (gis:maximum-of slope + 1.0))
  show "locating watershed outlet..."
  set outlet find-outlet
  set outlet-flow [ ]
  set pen-number -1
  show "ready!"
end


to-report find-outlet
  let boundary patches with [ gis:have-relationship? self watershed-boundary "****T****" ] 
  ask watershed 
  [ set exit-count 0
    sprout 1 ]
  let stop-count count turtles / 2
  while [ count turtles > stop-count ]
  [ ask turtles
    [ set heading gis:raster-sample flow-direction self
      let next-patch patch-ahead 0.5
      ifelse (member? patch-here boundary) and (not member? next-patch watershed)
      [ ask patch-here
        [ set exit-count exit-count + 1 ]
        die ]
      [ forward 0.5 ] ] ]
  ask turtles [ die ]
  report max-one-of boundary [ exit-count ]
end


to go
  if (not any? turtles) and (empty? outlet-flow) 
  [ ask watershed
    [ sprout 1 
      [ set size 0.75 
        set heading gis:raster-sample flow-direction self
        set q 10
        let sd gis:raster-sample stream-distance self
        ifelse sd < in-stream-dist
        [ set color blue ]
        [ set color sky
          if (landuse != 0)
          [ let cn curve-number landuse
            if (cn != 0)
            [ let s (1000 / cn) - 10
              let temp q - 0.2 * s
              set q (temp * temp) / (q + 0.8 * s) ] ] ] ] ]
    reset-ticks
    set pen-number pen-number + 1 ]
  ask turtles
  [ let step base-stepsize
    let sd gis:raster-sample stream-distance self
    if sd < in-stream-dist
    [ set color blue ]
    if (landuse != 0) and (sd > in-stream-dist)
    [ set step step * table:get landuse-flow-velocity landuse ]
    set step step * (sqrt (gis:raster-sample slope self / 100) + 1.0)
    forward step
    ifelse member? patch-here interior
    [ set heading gis:raster-sample flow-direction self ]
    [ die ] ]
  tick
  ifelse any? turtles
  [ let flow [ sum [ q ] of turtles-here ] of outlet
    set outlet-flow fput flow outlet-flow
    if length outlet-flow > 50
    [ set outlet-flow but-last outlet-flow ] ]
  [ set outlet-flow but-last outlet-flow
    if empty? outlet-flow
    [ stop ] ]
  if (ticks mod 5) = 0
    [ create-temporary-plot-pen (word "discharge-" pen-number)
      set-plot-pen-color 3 + (pen-number * 10)
      plotxy ticks mean outlet-flow ]
end


to draw-land-use
  if mouse-down? 
  [ let orig-xcor mouse-xcor
    let orig-ycor mouse-ycor
    let snap-xcor round orig-xcor
    let snap-ycor round orig-ycor
    ask patches with [pxcor = snap-xcor and pycor = snap-ycor] 
    [ ask (patches in-radius 5) with [ member? self interior ]
      [ set landuse draw-land-cover-with
        set pcolor table:get landuse-name-color landuse ] ]
    tick ]
end


to load-land-use
  let file user-file
  if is-string? file
  [ gis:apply-raster gis:load-dataset file luc 
    ask interior
    [ ifelse table:has-key? landuse-code-name luc
      [ set landuse table:get landuse-code-name luc ]
      [ set landuse 0 ] ]
    ask interior
    [ ifelse table:has-key? landuse-name-color landuse
      [ set pcolor table:get landuse-name-color landuse ]
      [ set pcolor black ] ] ]
end


to save-land-use
  let file user-new-file
  if is-string? file
  [ ask interior
    [ ifelse table:has-key? landuse-name-code landuse
      [ set luc table:get landuse-name-code landuse ]
      [ set luc 0 ] ]
    gis:store-dataset gis:patch-dataset luc file ]
end


to clear-land-use
  ask interior
  [ set luc 0 
    set landuse 0 ]
  ask interior
  [ set pcolor black ]
end


; turtle procedure
to-report curve-number [ lu ]
  let curve table:get landuse-curve-numbers lu
  if (soil-a != nobody) and (gis:contains? soil-a self)
  [ report item 0 curve ]
  if (soil-b != nobody) and (gis:contains? soil-b self)
  [ report item 1 curve ]
  if (soil-c != nobody) and (gis:contains? soil-c self)
  [ report item 2 curve ]
  ; assume soil group D if it's not A, B, or C
  report item 3 curve
end


to setup-landuse-tables
  set landuse-code-name table:make
  set landuse-name-code table:make
  set landuse-name-color table:make
  set landuse-flow-velocity table:make
  set landuse-curve-numbers table:make
  set landuse-menu-values [ ]
  define-landuse-categories
  let max-velocity 0
  foreach table:keys landuse-flow-velocity
  [ let velocity table:get landuse-flow-velocity ?
    if velocity > max-velocity
    [ set max-velocity velocity ] ]
  set max-velocity 1.1 * max-velocity
  foreach table:keys landuse-flow-velocity
  [ let velocity table:get landuse-flow-velocity ?
    table:put landuse-flow-velocity ? velocity / max-velocity ]
  widget41:set-chooser-items "draw-land-use-with" landuse-menu-values
end


to define-landuse [ code lu-color manning-n cn name menu? ]
  table:put landuse-code-name code name
  table:put landuse-name-code name code
  table:put landuse-name-color name lu-color
  table:put landuse-flow-velocity name (1 / manning-n)
  table:put landuse-curve-numbers name cn
  if menu?
  [ set landuse-menu-values lput name landuse-menu-values ]
end


to-report convert-flow-directions [ flow-directions ]
  let result gis:create-raster gis:width-of flow-directions gis:height-of flow-directions gis:envelope-of flow-directions
  let x 0
  repeat (gis:width-of flow-directions)
  [ let y 0
    repeat (gis:height-of flow-directions)
    [ let in-dir gis:raster-value flow-directions x y
      let out-dir 0
      if in-dir = 1 [ set out-dir 90 ]
      if in-dir = 2 [ set out-dir 135 ]
      if in-dir = 4 [ set out-dir 180 ]
      if in-dir = 8 [ set out-dir 225 ]
      if in-dir = 16 [ set out-dir 270 ]
      if in-dir = 32 [ set out-dir 315 ]
      if in-dir = 64 [ set out-dir 0 ]
      if in-dir = 128 [ set out-dir 45 ]
      gis:set-raster-value result x y out-dir
      set y y + 1 ]
    set x x + 1 ]
  report result
end
@#$#@#$#@
GRAPHICS-WINDOW
145
10
811
433
-1
-1
8.0
1
10
1
1
1
0
0
0
1
0
81
0
48
1
1
0
ticks

BUTTON
5
20
135
53
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL

BUTTON
5
79
135
112
rain
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL

BUTTON
5
305
135
338
save land cover
save-land-use
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL

BUTTON
5
265
135
298
load land cover
load-land-use
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL

BUTTON
5
150
135
183
draw land cover
draw-land-use
T
1
T
OBSERVER
NIL
NIL
NIL
NIL

CHOOSER
5
190
135
235
draw-land-cover-with
draw-land-cover-with
"Developed" "Agricultural" "Grassland" "Forest"
0

PLOT
835
10
1015
400
hydrograph
time
discharge
0.0
550.0
0.0
600.0
true
false
PENS
"default" 1.0 0 -16777216 true

BUTTON
5
345
135
378
clear land cover
clear-land-use
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL

BUTTON
835
410
1015
443
clear hydrograph
clear-plot
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL

@#$#@#$#@
WHAT IS IT?
-----------
This section could give a general understanding of what the model is trying to show or explain.


HOW IT WORKS
------------
This section could explain what rules the agents use to create the overall behavior of the model.


HOW TO USE IT
-------------
This section could explain how to use the model, including a description of each of the items in the interface tab.


THINGS TO NOTICE
----------------
This section could give some ideas of things for the user to notice while running the model.


THINGS TO TRY
-------------
This section could give some ideas of things for the user to try to do (move sliders, switches, etc.) with the model.


EXTENDING THE MODEL
-------------------
This section could give some ideas of things to add or change in the procedures tab to make the model more complicated, detailed, accurate, etc.


NETLOGO FEATURES
----------------
This section could point out any especially interesting or unusual features of NetLogo that the model makes use of, particularly in the Procedures tab.  It might also point out places where workarounds were needed because of missing features.


RELATED MODELS
--------------
This section could give the names of models in the NetLogo Models Library or elsewhere which are of related interest.


CREDITS AND REFERENCES
----------------------
This section could contain a reference to the model's URL on the web if it has one, as well as any other necessary credits or references.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 4.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@

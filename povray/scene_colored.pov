#include "colors.inc"
#declare OBJ = #include "object_colored.pov"
camera { 
    location <-0.016366, -0.015228, 0> 
	right <-1, 0, 0>*4/3
	up <0, 1, 0>
    look_at <-0.016366, -0.015228, -1>
    angle 56.7068
}

#include "/home/guo29/eccv2014/povray/light.pov"

light_source {
    <lightx-0.5, lighty, lightz-0.5>
    color White
	area_light <1,0,0> <0,0,1> 10,10
    adaptive 0
	jitter
}

OBJ

#ifndef GEOMETRY_H
#define GEOMETRY_H

#include "centroid.h"

// 2x2 rotation matrix applied to a Vec2
Vec2 rotate2D(Vec2 p, float angle, Vec2 center);

// Get the angle between two 2D vectors in radians
float getAngleBetweenVectors(Vec2 u1, Vec2 u2);

// Get the intersection point of two lines in homogenous form [a, b, c]
// where the line equation is ax + by + c = 0
Vec2 getIntersectionOfTwoLines(float l1[3], float l2[3]);

// Get the perpendicular bisector of two points as a line [a, b, c]
void getPerpBisector(Vec2 p1, Vec2 p2, float l[3]);

// Get the line through two points in homogenous form [a, b, c]
void getLine(Vec2 p1, Vec2 p2, float l[3]);

// Get the center and angle of rotation given three consecutive positions
// of the same point across three frames
void getCenterAngleOfRotation(Vec2 p1, Vec2 p2, Vec2 p3, Vec2 *center, float *angle);

#endif // GEOMETRY_H
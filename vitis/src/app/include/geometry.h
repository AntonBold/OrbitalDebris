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

// Get rotation parameters for matched triplets across three frames
// C1, C2, C3   : centroid frames at t-2, t-1, t
// M12          : matches between C1 and C2
// M23          : matches between C2 and C3
// out          : output rotation set
void getRotations(const Centroid *C1, const Centroid *C2, const Centroid *C3,
                  const Match *M12, int nm12,
                  const Match *M23, int nm23,
                  RotationSet *out);

// Get distance of each rotation center from the median center
// Used as input to GESD outlier detection
void getDistanceFromMedianCenter(const RotationSet *R, float *distances);

#endif // GEOMETRY_H
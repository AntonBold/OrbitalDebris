#include "include/geometry.h"
#include "include/centroid.h"
#include <math.h>

Vec2 rotate2D(Vec2 p, float angle, Vec2 center)
{
    p.x -= center.x;
    p.y -= center.y;

    float c = cosf(angle);
    float s = sinf(angle);

    Vec2 result;
    result.x = c * p.x - s * p.y + center.x;
    result.y = s * p.x + c * p.y + center.y;

    return result;
}

float getAngleBetweenVectors(Vec2 u1, Vec2 u2)
{
    // extend to 3d for cross product
    float d = u1.x * u2.x + u1.y * u2.y; // dot product
    float cz = u1.x * u2.y - u1.y * u2.x; // z component of cross product
    float mag = sqrtf((u1.x * u1.x + u1.y * u1.y) * (u2.x * u2.x + u2.y * u2.y));
    
    float a = atan2f(fabsf(cz), d) * (cz < 0 ? -1.0f : 1.0f);

    if (isnan(a) || fabsf(a) < EPS)
        return 0.0f;
    
    return a;
}

void getLine(Vec2 p1, Vec2 p2, float l[3])
{
    // cross product of homogenous points [x, y, z]
    l[0] = p1.y - p2.y;
    l[1] = p2.x - p1.x;
    l[2] = p1.x * p2.y - p2.x * p1.y;
}

void getPerpBisector(Vec2 p1, Vec2 p2, float l[3])
{
    getLine(p1, p2, l);

    // rotate normal by 90 degrees
    float nx = -l[1];
    float ny = l[0];

    // midpoint
    float mx = (p1.x + p2.x) / 2.0f;
    float my = (p1.y + p2.y) / 2.0f;

    l[0] = nx;
    l[1] = ny;
    l[3] = -(nx*mx + ny*my);
}

Vec2 getIntersectionOfTwoLines(float l1[3], float l2[3])
{
    // cross product of 2 lines in homogenous form
    float w = l1[0]*l2[1] - l1[1]*l2[0];
    float x = l1[1]*l2[2] - l1[2]*l2[1];
    float y = l1[2]*l2[0] - l1[0]*l2[2];

    Vec2 p;

    if (fabsf(w) < EPS || fabsf(x/w) > INF || fabsf(y/w) > INF) {
        p.x = INF;
        p.y = INF;
        return p;
    }

    p.x = x/w;
    p.y = y/w;
    return p;
}

void getCenterAngleOfRotation(Vec2 p1, Vec2 p2, Vec2 p3, Vec2 *center, float *angle) 
{
    float l1[3], l2[3];
    getPerpBisector(p1, p2, l1);
    getPerpBisector(p2, p3, l2);

    *center = getIntersectionOfTwoLines(l1, l2);

    Vec2 u2 = { p2.x - center->x, p2.y - center->y };
    Vec2 u3 = { p3.x - center->x, p3.y - center->y };

    *angle = getAngleBetweenVectors(u2, u3);
}
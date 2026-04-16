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
    l[2] = -(nx*mx + ny*my);
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

void getRotations(const Centroid *C1, const Centroid *C2, const Centroid *C3,
                  const Match *M12, int nm12,
                  const Match *M23, int nm23,
                  RotationSet *out)
{
    out->count = 0;

    for (int i = 0; i < nm12; i++) {
        int i1 = M12[i].from;
        int i2 = M12[i].to;

        // find if i2 is matched in m23
        int j = -1;
        for (int k = 0; k < nm23; k++) {
            if (M23[k].from == i2) {
                j = k;
                break;
            }
        }
        if (j < 0) continue;

        int i3 = M23[j].to;

        Vec2 p1 = { C1[i1].x, C1[i1].y };
        Vec2 p2 = { C2[i2].x, C2[i2].y };
        Vec2 p3 = { C3[i3].x, C3[i3].y };

        Vec2 center;
        float angle;
        getCenterAngleOfRotation(p1, p2, p3, &center, &angle);

        int idx = out->count;
        out->rotations[idx].center = center;
        out->rotations[idx].angle = angle;
        out->rotations[idx].i1 = i1;
        out->rotations[idx].i2 = i2;
        out->rotations[idx].i3 = i3;
        out->count++;
    }
}

void getDistanceFromMedianCenter(const RotationSet *R, float *distances) 
{
    if (R->count == 0) return;

    // compute median center
    float xs[MAX_CENTROIDS];
    float ys[MAX_CENTROIDS];

    for (int i = 0; i < R->count; i++) {
        xs[i] = R->rotations[i].center.x;
        ys[i] = R->rotations[i].center.y;
    }

    // simple median via insertion sort
    float sorted_x[MAX_CENTROIDS];
    float sorted_y[MAX_CENTROIDS];
    for (int i = 0; i < R->count; i++) {
        sorted_x[i] = xs[i];
        sorted_y[i] = ys[i];
    }

    for (int i = 1; i < R->count; i++) {
        float kx = sorted_x[i];
        float ky = sorted_y[i];
        int j = i - 1;
        while (j >= 0 && sorted_x[j] > kx) {
            sorted_x[j+1] = sorted_x[j];
            sorted_y[j+1] = sorted_y[j];
            j--;
        }
        sorted_x[j+1] = kx;
        sorted_y[j+1] = ky;
    }

    float med_x, med_y;
    int n = R->count;
    if (n % 2 == 0) {
        med_x = (sorted_x[n/2 - 1] + sorted_x[n/2]) / 2.0f;
        med_y = (sorted_y[n/2 - 1] + sorted_y[n/2]) /2.0f;
    } else {
        med_x = sorted_x[n/2];
        med_y = sorted_y[n/2];
    }

    // compute distance from median center
    for (int i = 0; i < R->count; i++) {
        float dx = R->rotations[i].center.x - med_x;
        float dy = R->rotations[i].center.y - med_y;
        float d = sqrtf(dx*dx + dy*dy);
        distances[i] = isnan(d) ? 0.0f : d;
    }
}
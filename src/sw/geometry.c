#include "include/geometry.h"
#include "include/centroid.h"
#include <math.h>

Vec2 rotate2D(Vec2 p, double angle, Vec2 center)
{
    p.x -= center.x;
    p.y -= center.y;

    double c = cos(angle);
    double s = sin(angle);

    Vec2 result;
    result.x = c * p.x - s * p.y + center.x;
    result.y = s * p.x + c * p.y + center.y;

    return result;
}

double getAngleBetweenVectors(Vec2 u1, Vec2 u2)
{
    // extend to 3d for cross product
    double d = u1.x * u2.x + u1.y * u2.y; // dot product
    double cz = u1.x * u2.y - u1.y * u2.x; // z component of cross product
    
    double a = atan2(fabs(cz), d) * (cz < 0 ? -1.0 : 1.0);

    if (isnan(a) || fabs(a) < EPS)
        return 0.0;
    
    return a;
}

void getLine(Vec2 p1, Vec2 p2, double l[3])
{
    // cross product of homogenous points [x, y, z]
    l[0] = p1.y - p2.y;
    l[1] = p2.x - p1.x;
    l[2] = p1.x * p2.y - p2.x * p1.y;
}

void getPerpBisector(Vec2 p1, Vec2 p2, double l[3])
{
    getLine(p1, p2, l);

    // rotate normal by 90 degrees
    double nx = -l[1];
    double ny = l[0];

    // midpoint
    double mx = (p1.x + p2.x) / 2.0;
    double my = (p1.y + p2.y) / 2.0;

    l[0] = nx;
    l[1] = ny;
    l[2] = -(nx*mx + ny*my);
}

Vec2 getIntersectionOfTwoLines(double l1[3], double l2[3])
{
    // cross product of 2 lines in homogenous form
    double w = l1[0]*l2[1] - l1[1]*l2[0];
    double x = l1[1]*l2[2] - l1[2]*l2[1];
    double y = l1[2]*l2[0] - l1[0]*l2[2];

    Vec2 p;

    if (w == 0.0 || fabs(x/w) > INF || fabs(y/w) > INF) {
        p.x = INF;
        p.y = INF;
        return p;
    }

    p.x = x/w;
    p.y = y/w;
    return p;
}

void getCenterAngleOfRotation(Vec2 p1, Vec2 p2, Vec2 p3, Vec2 *center, double *angle) 
{
    double l1[3], l2[3];
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
        double angle;
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


    // sort x and y independently to get correct medians
    double sorted_x[MAX_CENTROIDS];
    double sorted_y[MAX_CENTROIDS];
    for (int i = 0; i < R->count; i++) {
        sorted_x[i] = R->rotations[i].center.x;
        sorted_y[i] = R->rotations[i].center.y;
    }

   
    // sort x independently
    for (int i = 1; i < R->count; i++) {
        double kx = sorted_x[i];
        int j = i - 1;
        while (j >= 0 && sorted_x[j] > kx) {
            sorted_x[j+1] = sorted_x[j];
            j--;
        }
        sorted_x[j+1] = kx;
    }

    // sort y independently
    for (int i = 1; i < R->count; i++) {
        double ky = sorted_y[i];
        int j = i - 1;
        while (j >= 0 && sorted_y[j] > ky) {
            sorted_y[j+1] = sorted_y[j];
            j--;
        }
        sorted_y[j+1] = ky;
    }


    double med_x, med_y;
    int n = R->count;
    if (n % 2 == 0) {
        med_x = (sorted_x[n/2 - 1] + sorted_x[n/2]) / 2.0;
        med_y = (sorted_y[n/2 - 1] + sorted_y[n/2]) /2.0;
    } else {
        med_x = sorted_x[n/2];
        med_y = sorted_y[n/2];
    }

    // compute distance from median center
    for (int i = 0; i < R->count; i++) {
        double dx = R->rotations[i].center.x - med_x;
        double dy = R->rotations[i].center.y - med_y;
        double d = sqrt(dx*dx + dy*dy);
        distances[i] = isnan(d) ? 0.0 : d;
    }
}

void predictPositions(const Centroid *C1, int n1, const MatchSet *prev_matches,
                      const Vec2 *prev_translations, const RotationSet *prev_rotations,
                      Centroid *out)
{
    // expected translation of each C1 point (0 if it wasn't matched last frame)
    Vec2 T[MAX_CENTROIDS] = {0};
    for (int k = 0; k < prev_matches->count; k++)
        T[prev_matches->matches[k].to] = prev_translations[k];

    // no rotations: translate every point
    if (prev_rotations->count == 0) {
        for (int i = 0; i < n1; i++) {
            out[i] = C1[i];
            out[i].x += T[i].x;
            out[i].y += T[i].y;
        }
        return;
    }

    // rotations exist: points with a rotation are rotated (or translated if the
    // rotation isn't valid); points without one stay where they are (MATLAB RC1 = C1)
    for (int i = 0; i < n1; i++)
        out[i] = C1[i];
    for (int k = 0; k < prev_rotations->count; k++) {
        const Rotation *R = &prev_rotations->rotations[k];
        int i = R->i3;
        if (R->angle != 0.0 && R->center.x < INF && R->center.y < INF) {
            Vec2 p = { C1[i].x, C1[i].y };
            Vec2 rp = rotate2D(p, R->angle, R->center);
            out[i].x = rp.x;
            out[i].y = rp.y;
        } else {
            out[i].x = C1[i].x + T[i].x;
            out[i].y = C1[i].y + T[i].y;
        }
    }
}
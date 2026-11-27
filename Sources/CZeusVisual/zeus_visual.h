#ifndef ZEUS_VISUAL_H
#define ZEUS_VISUAL_H

#include <stdint.h>

typedef struct ZeusFlight {
    double from_x;
    double from_y;
    double control_x;
    double control_y;
    double to_x;
    double to_y;
    double duration;
    int32_t reduced_motion;
} ZeusFlight;

typedef struct ZeusPixels {
    int32_t width;
    int32_t height;
} ZeusPixels;

ZeusFlight zeus_visual_flight(double from_x, double from_y, double to_x, double to_y, int32_t reduced_motion);
ZeusFlight zeus_visual_flight_tangent(double from_x, double from_y, double to_x, double to_y, int32_t reduced_motion, double tangent_x, double tangent_y, int32_t has_tangent);
ZeusPixels zeus_visual_pixel_size(double width, double height, double scale);

#endif

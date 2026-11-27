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

typedef struct ZeusInkBox ZeusInkBox;
ZeusInkBox *zeus_visual_ink_new(void);
void zeus_visual_ink_free(ZeusInkBox *ink);
void zeus_visual_ink_reset(ZeusInkBox *ink);
int32_t zeus_visual_ink_add(ZeusInkBox *ink, double x, double y, double time);
void zeus_visual_ink_end(ZeusInkBox *ink);
int32_t zeus_visual_ink_smoothed(ZeusInkBox *ink, double *xs, double *ys, int32_t *stroke_lengths, int32_t max_strokes, int32_t max_points);

#endif

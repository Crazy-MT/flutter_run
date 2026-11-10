#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2 uOrigin;
uniform float uScale;
uniform vec2 uCenter;
uniform vec2 uRadius;
uniform sampler2D uAtlas;
out vec4 fragColor;

const vec2 roomSize = vec2(220., 140.);
const vec2 gridSize = vec2(72., 46.);
const vec2 atlasSize = vec2(220., 186.);

vec3 room(vec2 p) {
  vec2 pixel = clamp(floor((p - uOrigin) / uScale), vec2(0.), roomSize - 1.);
  return texture(uAtlas, (pixel + .5) / atlasSize).rgb;
}

vec4 weights(float f) {
  float f2 = f * f, f3 = f2 * f, inv = 1. - f;
  return vec4(inv * inv * inv, 4. - 6. * f2 + 3. * f3,
      1. + 3. * f + 3. * f2 - 3. * f3, f3) / 6.;
}

vec3 light(vec2 p) {
  vec2 cell = (p - uOrigin) / uScale / roomSize * gridSize - .5;
  vec2 base = floor(cell) - 1.;
  vec4 wx = weights(fract(cell.x)), wy = weights(fract(cell.y));
  vec3 result = vec3(0.);
  for (int y = 0; y < 4; y++) {
    for (int x = 0; x < 4; x++) {
      vec2 xy = clamp(base + vec2(float(x), float(y)), vec2(0.), gridSize - 1.);
      result += texture(uAtlas, (xy + vec2(.5, 140.5)) / atlasSize).rgb * wx[x] * wy[y];
    }
  }
  return result;
}

void main() {
  vec2 point = FlutterFragCoord().xy;
  vec2 samplePoint = point;
  vec2 lens = vec2(0.);
  float r = 0., edge = 0.;
  bool glass = uRadius.x > 0.;
  if (glass) {
    lens = (point - uCenter) / uRadius;
    r = length(lens);
    edge = smoothstep(.70, 1., r);
    samplePoint = uCenter + (point - uCenter) * mix(1. / 1.24, 1.16, edge);
  }
  vec3 color = room(samplePoint);
  if (glass) {
    vec2 d = samplePoint - uCenter;
    color.r = room(uCenter + d * (1. + .05 * edge)).r;
    color.b = room(uCenter + d * (1. - .05 * edge)).b;
  }
  color += (1. - color) * light(samplePoint);
  float a = 1.;
  if (glass) {
    vec2 reflection = (lens - vec2(-.26, -.49)) * vec2(1.65, 5.2);
    float top = .23 * exp(-dot(reflection, reflection));
    float ring = (r - .83) * 15.;
    float bottom = .22 * exp(-ring * ring) * smoothstep(.2, .91, lens.y);
    color += (1. - color) * (top + bottom);
    color *= 1. - .32 * smoothstep(.79, 1.01, r);
    a = 1. - smoothstep(.985, 1., r);
  }
  float noise = fract(sin(dot(point, vec2(12.9898, 78.233))) * 43758.5453);
  color += (noise - .5) * (1.5 / 255.);
  fragColor = vec4(color * a, a);
}

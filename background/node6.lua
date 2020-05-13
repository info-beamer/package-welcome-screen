gl.setup(NATIVE_WIDTH/8, NATIVE_HEIGHT/8)

local background_effect = resource.create_shader[[
    uniform float time;
    varying vec2 TexCoord;
    uniform vec4 Color;
    uniform float width1;
    uniform float width2;
    uniform float fade;

    float sinf(float x) {
      x*=0.159154943092;
      x-=floor(x);
      float xx=x*x;
      float y=16.4264961707;
      y=y*xx+-56.9342293281;
      y=y*xx+74.657362959;
      y=y*xx+-40.3774529476;
      y=y*xx+6.2511937242;
      return x*y;
    }

    vec3 hsv2rgb(vec3 c) {
      vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
      vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
      return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
    }

    void main() {
        float x = TexCoord.x;

        float y1 = TexCoord.y - sinf(x*13.0 - time) * 0.01 - 0.5;
        float t1 = abs(width1 / y1);
        float v1 = min(1.0, t1);

        float y2 = TexCoord.y - sinf(x*8.0 + time) * 0.01 - 0.5;
        float t2 = abs(width2 / y2);
        float v2 = min(1.0, t2);

        vec3 color = max(
            hsv2rgb(vec3(time*0.004+0.5, 1.0, v1)),
            hsv2rgb(vec3(time*0.004,     1.0, v2))
        ) * 2.0;
        float over = max(0.0, distance(vec3(1.0, 1.0, 1.0), color));

        color -= hsv2rgb(vec3(time*0.5, 1.0, over));
        color = color + fade;
        // color = vec3(over);
        gl_FragColor = vec4(color, Color.a);
    }
]]

local white = resource.create_colored_texture(1, 1, 1, 1)
local start = sys.now()

function node.render()
    local now = sys.now()

    local function eased(defer, d)
        local t = math.min(math.max(0, now - start - defer), d) / d
        t = t * 2
        if t < 1 then
            return 0.5 * t * t
        else
            t = t - 1
            return -0.5 * (t * (t - 2) - 1)
        end
    end

    background_effect:use{
        time = now * eased(0, 3);
        width1 = (1-eased(0,2.2))+0.002;
        width2 = (1-eased(0,3))+0.002;
        fade = 2.0 - eased(0,5)*2;
    }
    white:draw(0, 0, WIDTH, HEIGHT, alpha)
    background_effect:deactivate()
end

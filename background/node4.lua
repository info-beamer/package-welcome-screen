gl.setup(NATIVE_WIDTH/2, NATIVE_HEIGHT/2)

local background_effect = resource.create_shader[[
    uniform float t;
    uniform float sint;
    uniform float time;
    varying vec2 TexCoord;
    uniform vec4 Color;
    uniform float width1;
    uniform float width2;

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

    void main() {
        float x = TexCoord.x;

        float y1 = TexCoord.y - sinf(x*5.30- t) * 0.02 - 0.5;
        float t1 = abs(width1 / y1);

        float y2 = TexCoord.y - sinf(x*9.0+ t) * 0.01 - 0.5;
        float t2 = abs(width2 / y2);

        float y3 = TexCoord.y - sinf(x*-10.0 + t) * 0.015 - 0.5;
        float t3 = abs(width2 / y3);

        vec3 color = vec3(0.0,          min(t1,t3),     t1*4.3) +
                     vec3(min(t2,t1),   t2*4.1, 	0.0) +
                     vec3(t3*5.0,       0.0,            min(t3,t2)) 

		  - sinf(TexCoord.x*3.14-t+4.54)/2.0
                  + sint*0.4
                  -0.5;
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
        t = now;
        sint = math.sin(now);
        time = now * eased(0, 3);
        width1 = (1-eased(0,2.2))+0.002;
        width2 = (1-eased(0,3))+0.002;
    }
    white:draw(0, 0, WIDTH, HEIGHT, alpha)
    background_effect:deactivate()
end

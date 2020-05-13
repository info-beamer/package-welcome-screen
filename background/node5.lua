gl.setup(NATIVE_WIDTH/3, NATIVE_HEIGHT/3)

local background_effect = resource.create_shader[[
    uniform float time;
    varying vec2 TexCoord;
    uniform vec4 Color;

    float sinf(float x) {
        x*=0.159155;
        x-=floor(x);
        float xx=x*x;
        float y=-6.87897;
        y=y*xx+33.7755;
        y=y*xx+-72.5257;
        y=y*xx+80.5874;
        y=y*xx+-41.2408;
        y=y*xx+6.28077;
        return x*y;
    }

    float cosf(float x) {
        return sinf(x+1.5708);
    }

    void main() {
        vec2 uv = TexCoord.xy*9.0;
        vec2 uv0 = uv;
        float i0 = 0.7;
        float i1 = 1.0;
        float i2 = 1.1;
        float i4 = 0.0;
        for(int s = 0; s<4; s++) {
            vec2 r;
            r = vec2(cosf(uv.y*i0-i4+time/i1),sinf(uv.x*i0-i4+time/i1))/i2;
            r = r + vec2(-r.y,r.x)*0.3;
            uv.xy = uv.xy + r;

            i0 = i0 * 1.93;
            i1 = i1 * 1.15;
            i2 = i2 * 1.7;
            i4 = i4 + 0.05+0.1*time*i1;
        }
        float r = sinf(uv.x-time*2.05)*0.5+0.5;
        float b = sinf(uv.y+time*1.03)*0.5+0.5;
        float g = sinf((uv.x+uv.y+sinf(time*0.5))*0.5)*0.5+0.5;
        // gl_FragColor = vec4(r*r*r*r,g*g*g*g,b*b*b*b,TexCoord.y);
        // gl_FragColor = vec4(r,g,b,sinf(TexCoord.y*1.5+3.0)/1.0+1.3);
        gl_FragColor = vec4(r,g,b,(b+0.5) * (r+0.5) * (g+0.5));
        gl_FragColor = vec4(r*b,g*r,b*g,1.0);
        gl_FragColor = vec4(r*b,g*r,b*g,1.2-TexCoord.y/2.0);
        gl_FragColor = vec4(r,g,b,1.0-TexCoord.y/2.0);

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
        -- time = now/4 + math.sin(math.sin(now*0.5)*1.5)/3,
        time = now / 8
    }
    white:draw(0, 0, WIDTH, HEIGHT, alpha)
    background_effect:deactivate()
end

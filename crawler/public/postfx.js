// The view's last pass: a WebGL shader over the 448x288 canvas the game draws, shown at the screen's real
// resolution. Lines glow like phosphor on an old vector monitor (bloom), the pixels stay sharp instead of
// blurring when the canvas is scaled up, rows show faint scanlines, the edges fall off into the dark, and the
// floor's accent color tints the shadows. Game state drives it through a few numbers: a red pulse at the
// edges while the party is in danger (on the heartbeat), a red flash and a split of color when someone is
// hurt, a flash for a critical hit or a kill.
//
// The 2D canvas stays where it is (clicks, tips and toasts are laid out against it); this one sits on top of
// it and ignores the mouse. No WebGL, a lost context, or ?nofx in the address: the plain canvas shows instead.
//
// Passes per frame: upload the canvas, keep its bright parts at half size, blur them across and down
// (quarter size), then one composite at full size. Four draws.

const VERT = `
attribute vec2 aPos;
varying vec2 vUv;
void main() {
  vUv = aPos * 0.5 + 0.5;
  gl_Position = vec4(aPos, 0.0, 1.0);
}`;

// Keep what is bright, as a soft knee so faint lines glow a little and bright ones a lot
const BRIGHT = `
precision mediump float;
varying vec2 vUv;
uniform sampler2D uTex;
void main() {
  vec3 c = texture2D(uTex, vUv).rgb;
  float l = max(c.r, max(c.g, c.b));
  float k = smoothstep(0.12, 0.7, l);
  gl_FragColor = vec4(c * k, 1.0);
}`;

// 9-tap gaussian along uDir (in texels), using linear filtering to read two texels per tap
const BLUR = `
precision mediump float;
varying vec2 vUv;
uniform sampler2D uTex;
uniform vec2 uDir;
void main() {
  vec3 c = texture2D(uTex, vUv).rgb * 0.2270270270;
  c += texture2D(uTex, vUv + uDir * 1.3846153846).rgb * 0.3162162162;
  c += texture2D(uTex, vUv - uDir * 1.3846153846).rgb * 0.3162162162;
  c += texture2D(uTex, vUv + uDir * 3.2307692308).rgb * 0.0702702703;
  c += texture2D(uTex, vUv - uDir * 3.2307692308).rgb * 0.0702702703;
  gl_FragColor = vec4(c, 1.0);
}`;

const COMPOSITE = `
precision mediump float;
varying vec2 vUv;
uniform sampler2D uTex;
uniform sampler2D uBloom;
uniform vec2 uSrc;      // the game canvas, in pixels
uniform vec2 uOut;      // this canvas, in pixels
uniform vec3 uAccent;   // the floor's accent color
uniform float uTime;
uniform float uDanger;  // 0..1, eased
uniform float uPulse;   // 0..1, a heartbeat that decays
uniform float uHurt;    // 0..1, decays
uniform vec4 uFlash;    // rgb, strength
uniform float uSplit;   // chromatic split, in source pixels

// Sharp bilinear: nearest-neighbour pixels with only their edges blended, so a 448-wide canvas scaled to any
// size keeps crisp pixels without shimmering
vec2 sharp(vec2 uv) {
  vec2 texel = uv * uSrc;
  vec2 scale = max(uOut / uSrc, vec2(1.0));
  vec2 region = 0.5 - 0.5 / scale;
  vec2 d = fract(texel) - 0.5;
  vec2 f = (d - clamp(d, -region, region)) * scale + 0.5;
  return (floor(texel) + f) / uSrc;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void main() {
  vec2 uv = vUv;
  vec2 fromCenter = uv - 0.5;
  // Hurt pulls the color channels apart toward the edges
  vec2 split = fromCenter * (uSplit / uSrc.x) * 2.0;
  vec3 col;
  col.r = texture2D(uTex, sharp(uv + split)).r;
  col.g = texture2D(uTex, sharp(uv)).g;
  col.b = texture2D(uTex, sharp(uv - split)).b;

  // Phosphor glow, warmed a little toward the floor's accent
  vec3 bloom = texture2D(uBloom, uv).rgb;
  col += bloom * mix(vec3(1.0), uAccent, 0.25) * 1.15;

  // Shadows lifted toward the accent: the dark is this floor's dark, not flat black
  float luma = dot(col, vec3(0.299, 0.587, 0.114));
  col += uAccent * 0.03 * (1.0 - smoothstep(0.0, 0.35, luma));

  // Danger drains the color (red holds on longest) and closes in a pulsing red edge
  float edge = smoothstep(0.25, 0.75, length(fromCenter * vec2(1.25, 1.0)));
  col = mix(col, vec3(luma) * vec3(1.15, 0.85, 0.85), uDanger * 0.5);
  col += vec3(0.75, 0.04, 0.03) * edge * uDanger * (0.35 + 0.65 * uPulse);
  col += vec3(0.9, 0.08, 0.05) * edge * uHurt * 0.9;

  // Scanlines on the game's own rows, and a soft vignette
  float row = sin((uv.y * uSrc.y) * 6.2831853);
  col *= 0.9 + 0.1 * row;
  col *= mix(1.0, 0.55, smoothstep(0.35, 0.85, length(fromCenter * vec2(1.1, 1.25))));

  col += uFlash.rgb * uFlash.a;
  col += (hash(uv * uOut + uTime) - 0.5) / 160.0; // dither: no banding in the dark gradients
  gl_FragColor = vec4(col, 1.0);
}`;

const hexRgb = (hex) => {
  const n = parseInt(String(hex).replace("#", "").slice(0, 6), 16);
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
};

// How fast the effects fade, per second
export const FX_DECAY = { hurt: 3.2, flash: 6, pulse: 3.5, split: 5 };

export class PostFx {
  // Returns null when the shader can't run here (the plain canvas keeps showing).
  static create(source, { reducedMotion = false } = {}) {
    if (/nofx/i.test(location.search + location.hash)) return null;
    const canvas = document.createElement("canvas");
    canvas.className = "postfx";
    canvas.setAttribute("aria-hidden", "true");
    const gl = canvas.getContext("webgl", { alpha: false, antialias: false, premultipliedAlpha: false, preserveDrawingBuffer: false, powerPreference: "low-power" });
    if (!gl) return null;
    try {
      return new PostFx(source, canvas, gl, reducedMotion);
    } catch (err) {
      console.warn("postfx: off,", err.message);
      return null;
    }
  }

  constructor(source, canvas, gl, reducedMotion) {
    Object.assign(this, { source, canvas, gl, reducedMotion });
    this.alive = true;
    this.accent = [1, 0.7, 0.28];
    this.danger = 0;
    this.hurtLevel = 0;
    this.splitLevel = 0;
    this.pulseLevel = 0;
    this.flashColor = [1, 1, 1];
    this.flashLevel = 0;
    this.beats = []; // performance.now() times of upcoming heartbeats
    this.last = null;
    const prog = (frag) => {
      const p = gl.createProgram();
      for (const [type, src] of [[gl.VERTEX_SHADER, VERT], [gl.FRAGMENT_SHADER, frag]]) {
        const s = gl.createShader(type);
        gl.shaderSource(s, src);
        gl.compileShader(s);
        if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
        gl.attachShader(p, s);
      }
      gl.bindAttribLocation(p, 0, "aPos");
      gl.linkProgram(p);
      if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
      const u = {};
      const n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
      for (let i = 0; i < n; i++) {
        const name = gl.getActiveUniform(p, i).name;
        u[name] = gl.getUniformLocation(p, name);
      }
      return { p, u };
    };
    this.bright = prog(BRIGHT);
    this.blur = prog(BLUR);
    this.comp = prog(COMPOSITE);
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
    this.src = this.texture(source.width, source.height);
    const [w, h] = [source.width, source.height];
    this.half = this.target(Math.ceil(w / 2), Math.ceil(h / 2));
    this.qa = this.target(Math.ceil(w / 4), Math.ceil(h / 4));
    this.qb = this.target(Math.ceil(w / 4), Math.ceil(h / 4));
    canvas.addEventListener("webglcontextlost", (ev) => {
      ev.preventDefault();
      this.kill("context lost");
    });
    this.place();
  }

  texture(w, h) {
    const gl = this.gl;
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    return t;
  }

  target(w, h) {
    const gl = this.gl;
    const tex = this.texture(w, h);
    const fb = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) throw new Error("framebuffer incomplete");
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    return { tex, fb, w, h };
  }

  // Sit exactly over the source canvas's picture (inside its border), at the screen's pixel density
  place() {
    const s = this.source;
    s.after(this.canvas);
    const fit = () => {
      const w = s.clientWidth;
      const h = s.clientHeight;
      Object.assign(this.canvas.style, { left: `${s.offsetLeft + s.clientLeft}px`, top: `${s.offsetTop + s.clientTop}px`, width: `${w}px`, height: `${h}px` });
      const dpr = Math.min(window.devicePixelRatio || 1, 3);
      this.canvas.width = Math.max(1, Math.round(w * dpr));
      this.canvas.height = Math.max(1, Math.round(h * dpr));
    };
    fit();
    this.resize = new ResizeObserver(fit);
    this.resize.observe(s);
    s.classList.add("under-fx");
  }

  kill(why) {
    if (!this.alive) return;
    this.alive = false;
    console.warn(`postfx: off (${why})`);
    this.resize?.disconnect();
    this.canvas.remove();
    this.source.classList.remove("under-fx");
  }

  // ---- what the game tells it

  setAccent(hex) {
    this.accent = hexRgb(hex);
  }
  setDanger(x) {
    this.danger = x;
  }
  hurt(strength = 1) {
    this.hurtLevel = Math.min(1, this.hurtLevel + strength);
    if (!this.reducedMotion) this.splitLevel = Math.min(3, this.splitLevel + 2.2 * strength);
  }
  flash(hex, strength = 0.35) {
    this.flashColor = hexRgb(hex);
    this.flashLevel = Math.max(this.flashLevel, this.reducedMotion ? strength * 0.3 : strength);
  }
  // A heartbeat lands at this performance.now() time (the audio clock's beat, converted): the red edge pulses with it
  beat(atMs) {
    this.beats.push(atMs);
  }

  // ---- one frame

  render(now) {
    if (!this.alive) return;
    const gl = this.gl;
    const dt = this.last === null ? 0 : Math.min(0.1, (now - this.last) / 1000);
    this.last = now;
    const decay = (v, rate) => v * Math.exp(-rate * dt);
    this.hurtLevel = decay(this.hurtLevel, FX_DECAY.hurt);
    this.splitLevel = decay(this.splitLevel, FX_DECAY.split);
    this.flashLevel = decay(this.flashLevel, FX_DECAY.flash);
    this.pulseLevel = decay(this.pulseLevel, FX_DECAY.pulse);
    if (this.beats.length && this.beats[0] <= now) {
      this.beats = this.beats.filter((t) => t > now);
      this.pulseLevel = 1;
    }

    // The game's canvas becomes a texture
    gl.bindTexture(gl.TEXTURE_2D, this.src);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, this.source);

    const pass = (prog, into, tex, set) => {
      gl.useProgram(prog.p);
      gl.bindFramebuffer(gl.FRAMEBUFFER, into?.fb ?? null);
      gl.viewport(0, 0, into?.w ?? this.canvas.width, into?.h ?? this.canvas.height);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.uniform1i(prog.u.uTex, 0);
      set?.(prog.u);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    };
    pass(this.bright, this.half, this.src);
    pass(this.blur, this.qa, this.half.tex, (u) => gl.uniform2f(u.uDir, 1 / this.half.w, 0));
    pass(this.blur, this.qb, this.qa.tex, (u) => gl.uniform2f(u.uDir, 0, 1 / this.qa.h));
    pass(this.comp, null, this.src, (u) => {
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, this.qb.tex);
      gl.uniform1i(u.uBloom, 1);
      gl.activeTexture(gl.TEXTURE0);
      gl.uniform2f(u.uSrc, this.source.width, this.source.height);
      gl.uniform2f(u.uOut, this.canvas.width, this.canvas.height);
      gl.uniform3f(u.uAccent, ...this.accent);
      gl.uniform1f(u.uTime, (now / 1000) % 100);
      gl.uniform1f(u.uDanger, this.danger);
      gl.uniform1f(u.uPulse, this.reducedMotion ? 0.5 : this.pulseLevel);
      gl.uniform1f(u.uHurt, this.hurtLevel);
      gl.uniform4f(u.uFlash, ...this.flashColor, this.flashLevel);
      gl.uniform1f(u.uSplit, 0.35 + this.splitLevel);
    });
  }
}

/*
 * Focus Garden — landing-page scene renderer.
 * Draws the SAME 10×6 top-down farm as the macOS app, from the SAME exported sprite sheet
 * (garden-sheet.png + window.GARDEN_FRAMES). Layout mirrors DayBarCore/GardenSceneModel so the
 * site and app cannot drift. No external libraries; honors prefers-reduced-motion.
 */
(function () {
  "use strict";
  var COLS = 10, ROWS = 6, PATH_ROW = 4, DISP = 2; // DISP = ×master (32px → 64px cells)
  var PLOTS = [[2, 3], [4, 3], [6, 3], [8, 3]];
  var COMPANION = [5, 4], HOME = [1, 1], SIGN = [7, 1];
  var SOIL = { spring: "plot_soil_spring", summer: "plot_soil_summer", autumn: "plot_soil_autumn", winter: "plot_soil_winter" };

  function grass(x, y) { return (x * 3 + y * 5) % 7 === 0 ? "tile_grass_b" : "tile_grass_a"; }
  function fenceKind(x, y) {
    var lc = COLS - 1, lr = ROWS - 1;
    if (x === 0 && y === 0) return "nw"; if (x === lc && y === 0) return "ne";
    if (x === 0 && y === lr) return "sw"; if (x === lc && y === lr) return "se";
    if (y === 0) return "n"; if (y === lr) return "s"; if (x === 0) return "w"; if (x === lc) return "e";
    return null;
  }

  function placements(state) {
    var p = [], x, y, i;
    for (y = 0; y < ROWS; y++) for (x = 0; x < COLS; x++) p.push({ n: grass(x, y), c: x, r: y });
    for (x = 1; x < COLS - 1; x++) p.push({ n: "tile_path", c: x, r: PATH_ROW });
    var soil = SOIL[state.season || "autumn"];
    PLOTS.forEach(function (cell) { p.push({ n: soil, c: cell[0], r: cell[1] }); });
    p.push({ n: "prop_home", c: HOME[0], r: HOME[1], w: 2, h: 2 });
    p.push({ n: "prop_sign", c: SIGN[0], r: SIGN[1] });
    (state.crops || []).forEach(function (crop, idx) {
      if (!crop || idx >= PLOTS.length) return;
      var cell = PLOTS[idx];
      p.push({ n: "crop_" + crop.id + "_top_" + crop.stage, c: cell[0], r: cell[1], wilt: crop.wilt || 0 });
      if (crop.stage >= 4) p.push({ n: "fx_sparkle", c: cell[0], r: cell[1], spark: true });
    });
    p.push({ n: "companion_" + (state.mood || "idle") + "_down", c: COMPANION[0], r: COMPANION[1], comp: true });
    for (y = 0; y < ROWS; y++) for (x = 0; x < COLS; x++) { var k = fenceKind(x, y); if (k) p.push({ n: "fence_" + k, c: x, r: y }); }
    if (state.rain) for (y = 0; y < ROWS; y++) for (x = 0; x < COLS; x++) if (!fenceKind(x, y)) p.push({ n: "fx_rain_16", c: x, r: y });
    return p;
  }

  function mount(canvas, opts) {
    var F = window.GARDEN_FRAMES;
    if (!F) { return null; }
    var frames = F.frames, S = F.scale, cell = 32 * DISP;
    canvas.width = COLS * cell; canvas.height = ROWS * cell;
    var ctx = canvas.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    var reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    var sheet = new Image(); sheet.src = "assets/garden/garden-sheet.png";
    var state = opts.state, t0 = null, raf = null;

    function drawTile(pl, t) {
      var f = frames[pl.n]; if (!f) return;
      var dx = pl.c * cell, dy = pl.r * cell, a = 1;
      if (pl.comp && !reduce) dy += Math.round(Math.sin(t / 380) * 2 - 2);
      if (pl.spark) a = reduce ? 0.85 : 0.5 + 0.5 * Math.abs(Math.sin(t / 430));
      else if (pl.wilt >= 2) a = 0.82;
      ctx.globalAlpha = a;
      ctx.drawImage(sheet, f.x * S, f.y * S, f.w * S, f.h * S, dx, dy, f.w * DISP, f.h * DISP);
      ctx.globalAlpha = 1;
    }
    function render(t) {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      placements(state).forEach(function (pl) { drawTile(pl, t); });
    }
    function loop(ts) { if (t0 === null) t0 = ts; render(ts - t0); raf = requestAnimationFrame(loop); }
    function start() { if (opts.animate && !reduce) { raf = requestAnimationFrame(loop); } else { render(0); } }
    if (sheet.complete) start(); else sheet.onload = start;

    return {
      setState: function (s) { state = s; if (!(opts.animate && !reduce)) render(0); },
      stop: function () { if (raf) cancelAnimationFrame(raf); }
    };
  }

  var STATES = {
    empty:   { season: "autumn", mood: "idle",  crops: [] },
    growing: { season: "autumn", mood: "happy", crops: [{ id: "parsnip", stage: 2 }, { id: "cauliflower", stage: 3 }, { id: "berry", stage: 1 }] },
    ready:   { season: "autumn", mood: "happy", rain: true, crops: [{ id: "parsnip", stage: 4 }, { id: "cauliflower", stage: 4 }, { id: "berry", stage: 4 }, { id: "parsnip", stage: 3 }] },
    winter:  { season: "winter", mood: "wilted", crops: [{ id: "berry", stage: 2, wilt: 1 }] }
  };

  function init() {
    document.querySelectorAll("canvas[data-garden]").forEach(function (cv) {
      var st = STATES[cv.dataset.state || "growing"] || STATES.growing;
      cv._garden = mount(cv, { state: st, animate: cv.dataset.animate === "true" });
    });
    var demo = document.querySelector('canvas[data-garden="demo"]');
    var btns = document.querySelectorAll("[data-garden-state]");
    btns.forEach(function (btn) {
      btn.addEventListener("click", function () {
        btns.forEach(function (b) { b.setAttribute("aria-pressed", b === btn ? "true" : "false"); });
        if (demo && demo._garden) demo._garden.setState(STATES[btn.dataset.gardenState] || STATES.growing);
      });
    });
  }

  window.GardenScene = { mount: mount, placements: placements, STATES: STATES };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();

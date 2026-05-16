#!/usr/bin/env osascript -l JavaScript
// mac-overlay-compact.js — Thin, stackable notification overlay for PeonPing
// Based on glass theme but: 60px tall, shows tab name + short summary, proper stacking
// Usage: same args as mac-overlay-glass.js

ObjC.import('Cocoa');
ObjC.import('QuartzCore');

function run(argv) {
  var message    = argv[0] || 'peon-ping';
  var color      = argv[1] || 'blue';
  var iconPath   = argv[2] || '';
  var slot       = parseInt(argv[3], 10) || 0;
  var dismiss    = argv[4] !== undefined ? parseFloat(argv[4]) : 3;
  if (isNaN(dismiss)) dismiss = 3;
  var bundleId   = argv[5] || '';
  var idePid     = parseInt(argv[6], 10) || 0;
  var sessionTty = argv[7] || '';
  var subtitle   = argv[8] || '';
  var position   = argv[9] || 'top-right';
  var notifType  = argv[10] || '';
  var allScreens = argv[11] === 'true';
  var screenIdx  = (argv[12] !== undefined && argv[12] !== '') ? parseInt(argv[12], 10) : -1;
  var showCloseButton = (argv[13] || 'true') === 'true';

  var env = $.NSProcessInfo.processInfo.environment;
  var clickCommandValue = env.objectForKey($('PEON_CLICK_COMMAND'));
  var clickCommand = clickCommandValue && !clickCommandValue.isNil() ? ObjC.unwrap(clickCommandValue) : '';

  // ── Per-tab color palette (read from config.json, fallback to catppuccin-mocha) ──
  function hexToRgb(hex) {
    hex = hex.replace('#', '');
    return [parseInt(hex.substring(0,2), 16) / 255,
            parseInt(hex.substring(2,4), 16) / 255,
            parseInt(hex.substring(4,6), 16) / 255];
  }
  var defaultPalette = ['#cba6f7','#89b4fa','#a6e3a1','#fab387','#f38ba8','#94e2d5','#f9e2af','#74c7ec'];
  var hudDirValue = env.objectForKey($('HUD_DIR'));
  var hudDir = hudDirValue && !hudDirValue.isNil() ? ObjC.unwrap(hudDirValue) : '';
  var paletteHexes = defaultPalette;
  if (hudDir) {
    try {
      var cfgData = $.NSData.dataWithContentsOfFile($(hudDir + '/config.json'));
      if (cfgData && !cfgData.isNil()) {
        var cfgStr = $.NSString.alloc.initWithDataEncoding(cfgData, $.NSUTF8StringEncoding).js;
        var cfg = JSON.parse(cfgStr);
        if (cfg.tab_palette && cfg.tab_palette.length > 0) paletteHexes = cfg.tab_palette;
      }
    } catch(e) {}
  }
  var tabPalette = paletteHexes.map(hexToRgb);

  // ── Resolve WezTerm tab name + tab ID from TTY ──
  var tabName = '';
  var tabId = -1;
  if (sessionTty) {
    try {
      var task = $.NSTask.alloc.init;
      task.setLaunchPath($('/opt/homebrew/bin/wezterm'));
      task.setArguments($(['cli', 'list', '--format', 'json']));
      var pipe = $.NSPipe.pipe;
      task.setStandardOutput(pipe);
      task.setStandardError($.NSPipe.pipe);
      task.launch;
      task.waitUntilExit;
      var data = pipe.fileHandleForReading.readDataToEndOfFile;
      var jsonStr = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
      var panes = JSON.parse(jsonStr);
      // Build tab visual index: unique tab_ids in array order = visual position
      var tabOrder = [];
      for (var ti = 0; ti < panes.length; ti++) {
        var tid = panes[ti].tab_id;
        if (tabOrder.indexOf(tid) === -1) tabOrder.push(tid);
      }
      for (var pi = 0; pi < panes.length; pi++) {
        if (panes[pi].tty_name === sessionTty) {
          tabName = panes[pi].tab_title || '';
          tabId = tabOrder.indexOf(panes[pi].tab_id);
          break;
        }
      }
    } catch(e) {}
  }
  var tabColorIdx = tabId >= 0 ? tabId % tabPalette.length : -1;

  // ── Type badge text ──
  var typeText;
  switch (notifType) {
    case 'complete':   typeText = 'DONE'; break;
    case 'permission': typeText = 'APPROVE'; break;
    case 'limit':      typeText = 'LIMIT'; break;
    case 'idle':       typeText = 'IDLE'; break;
    case 'question':   typeText = 'INPUT'; break;
    default:
      if (color === 'blue') typeText = 'DONE';
      else if (color === 'red') typeText = 'APPROVE';
      else if (color === 'yellow') typeText = 'IDLE';
      else typeText = 'INPUT';
  }

  // ── Build display text ──
  // Primary: tab name or project name, Secondary: short summary
  var displayName = tabName || message.split(':')[0] || 'Claude';
  var displaySummary = subtitle || message;
  // Truncate summary to ~40 chars
  if (displaySummary.length > 45) {
    displaySummary = displaySummary.substring(0, 42) + '...';
  }

  // ── Window dimensions — compact ──
  var winW = 320, winH = 56;
  var padX = 6, padY = 4;
  var contentW = winW - padX * 2, contentH = winH - padY * 2;
  var cornerRadius = 10;

  // ── NSApp setup ──
  $.NSApplication.sharedApplication;
  $.NSApp.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  var dismissNotificationName = 'com.peonping.dismiss.compact.' + slot;

  // ── Screen detection ──
  var screens = $.NSScreen.screens;
  var targetScreen;
  if (screenIdx >= 0 && screenIdx < screens.count) {
    targetScreen = screens.objectAtIndex(screenIdx);
  } else {
    var mouseLocation = $.NSEvent.mouseLocation;
    targetScreen = screens.objectAtIndex(0);
    for (var s = 0; s < screens.count; s++) {
      var scr = screens.objectAtIndex(s);
      var sf = scr.frame;
      if (mouseLocation.x >= sf.origin.x && mouseLocation.x <= sf.origin.x + sf.size.width &&
          mouseLocation.y >= sf.origin.y && mouseLocation.y <= sf.origin.y + sf.size.height) {
        targetScreen = scr; break;
      }
    }
  }

  var vf = targetScreen.visibleFrame;
  var margin = 8;
  var slotStep = winH + 6;  // 62px per notification — tight stacking
  var ySlotOffset = margin + slot * slotStep;
  var x, y;
  switch (position) {
    case 'top-right':
      x = vf.origin.x + vf.size.width - winW - margin;
      y = vf.origin.y + vf.size.height - winH - ySlotOffset;
      break;
    case 'top-left':
      x = vf.origin.x + margin;
      y = vf.origin.y + vf.size.height - winH - ySlotOffset;
      break;
    case 'bottom-right':
      x = vf.origin.x + vf.size.width - winW - margin;
      y = vf.origin.y + ySlotOffset;
      break;
    case 'bottom-left':
      x = vf.origin.x + margin;
      y = vf.origin.y + ySlotOffset;
      break;
    default: // top-center
      x = vf.origin.x + (vf.size.width - winW) / 2;
      y = vf.origin.y + vf.size.height - winH - ySlotOffset;
  }

  // ── Window ──
  var nonActivating = 1 << 7;
  var win = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer(
    $.NSMakeRect(x, y, winW, winH),
    $.NSWindowStyleMaskBorderless | nonActivating, $.NSBackingStoreBuffered, false
  );
  win.setBackgroundColor($.NSColor.clearColor);
  win.setOpaque(false); win.setHasShadow(false); win.setAlphaValue(0.0);
  win.setLevel($.NSStatusWindowLevel);
  win.setCollectionBehavior($.NSWindowCollectionBehaviorCanJoinAllSpaces | $.NSWindowCollectionBehaviorStationary);
  win.contentView.wantsLayer = true;

  // ── Colors ──
  function cg(r,g,b,a) { return $.NSColor.colorWithSRGBRedGreenBlueAlpha(r,g,b,a).CGColor; }

  var inkBgCG = cg(0.08, 0.08, 0.11, 0.92);
  var glassBorderCG = cg(0.99, 0.99, 0.99, 0.08);

  var accentR, accentG, accentB;
  switch (color) {
    case 'red':    accentR=0.90; accentG=0.25; accentB=0.30; break;
    case 'yellow': accentR=0.95; accentG=0.75; accentB=0.20; break;
    case 'green':  accentR=0.30; accentG=0.80; accentB=0.40; break;
    case 'blue': default: accentR=0.40; accentG=0.60; accentB=0.99; break;
  }
  var accentCG = cg(accentR, accentG, accentB, 1.0);

  // ── HUD background ──
  var hud = $.NSView.alloc.initWithFrame($.NSMakeRect(padX, padY, contentW, contentH));
  hud.setWantsLayer(true);

  var bgPath = $.CGPathCreateWithRoundedRect(
    $.CGRectMake(0, 0, contentW, contentH), cornerRadius, cornerRadius, null
  );
  var bg = $.CAShapeLayer.layer;
  bg.setPath(bgPath);
  bg.setFillColor(inkBgCG);
  hud.layer.addSublayer(bg);

  var border = $.CAShapeLayer.layer;
  border.setPath(bgPath);
  border.setFillColor(null);
  border.setStrokeColor(glassBorderCG);
  border.setLineWidth(0.5);
  hud.layer.addSublayer(border);

  // No progress line — clean look, no timer pressure

  hud.layer.shadowColor = cg(0, 0, 0, 0.8);
  hud.layer.shadowRadius = 12;
  hud.layer.shadowOpacity = 0.25;
  hud.layer.shadowOffset = $.CGSizeMake(0, -2);

  win.contentView.addSubview(hud);

  // ── Accent bar (per-tab color identity, left edge) ──
  var barW = 4, barInset = 8;
  var barH = contentH - barInset * 2;
  var barR = accentR, barG = accentG, barB = accentB;
  if (tabColorIdx >= 0) {
    var tc = tabPalette[tabColorIdx];
    barR = tc[0]; barG = tc[1]; barB = tc[2];
  }
  var barView = $.NSView.alloc.initWithFrame(
    $.NSMakeRect(padX + 6, padY + barInset, barW, barH)
  );
  barView.setWantsLayer(true);
  barView.layer.setCornerRadius(barW / 2);
  barView.layer.setBackgroundColor(cg(barR, barG, barB, 0.9));
  win.contentView.addSubview(barView);

  // ── Text ──
  function makeLabel(text, xPos, yPos, w, fontSize, fontName, r, g, b, alpha) {
    var font = $.NSFont.fontWithNameSize(fontName, fontSize);
    if (!font || font.isNil()) font = $.NSFont.systemFontOfSize(fontSize);
    var label = $.NSTextField.alloc.initWithFrame($.NSMakeRect(xPos, yPos, w, fontSize + 4));
    label.setStringValue($(text)); label.setBezeled(false); label.setDrawsBackground(false);
    label.setEditable(false); label.setSelectable(false);
    label.setTextColor($.NSColor.colorWithSRGBRedGreenBlueAlpha(r, g, b, alpha));
    label.setFont(font);
    label.setLineBreakMode($.NSLineBreakByTruncatingTail);
    label.cell.setWraps(false);
    return label;
  }

  var textX = padX + 22;
  var textW = contentW - 36;

  // Type badge + tab name on top line (prominent, accent-colored)
  var topLine = typeText + '  ' + displayName;
  win.contentView.addSubview(makeLabel(topLine, textX, padY + contentH - 26, textW, 12, 'HelveticaNeue-Bold', accentR, accentG, accentB, 0.95));

  // Summary on bottom line (subdued blue)
  win.contentView.addSubview(makeLabel(displaySummary, textX, padY + contentH - 42, textW, 10, 'HelveticaNeue', 0.45, 0.58, 0.82, 0.7));

  // ── Click handler — dismiss + optional focus ──
  // Unique class name per process to avoid ObjC runtime collisions
  var uid = '' + slot + '' + Math.floor(Math.random() * 99999);
  var dhClassName = 'CDH' + uid;
  ObjC.registerSubclass({
    name: dhClassName, superclass: 'NSObject',
    methods: { 'handleDismiss': { types: ['void', []], implementation: function() {
      if (clickCommand) {
        try {
          var t = $.NSTask.alloc.init;
          t.setLaunchPath($('/bin/bash'));
          t.setArguments($(['-lc', clickCommand]));
          t.launch; t.waitUntilExit;
        } catch(e) {}
      }
      $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObject($(dismissNotificationName), $.NSString.string);
      win.orderOut(null);
      $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(0.05, $.NSApp, 'terminate:', null, false);
    }}}
  });
  var dh = $[dhClassName].alloc.init;
  var btn = $.NSButton.alloc.initWithFrame($.NSMakeRect(0, 0, winW, winH));
  btn.setTitle($('')); btn.setBordered(false); btn.setTransparent(true);
  btn.setTarget(dh); btn.setAction('handleDismiss');
  win.contentView.addSubview(btn);

  // ══════════════════════════════════════════════
  // ANIMATION
  // ══════════════════════════════════════════════
  win.orderFrontRegardless;
  win.animator.setAlphaValue(1.0);

  if (dismiss > 0) {
    var animSteps = 100, animInterval = dismiss / animSteps;
    var step = { val: 0 };

    // Simple fade out in the last second, then terminate
    var animClassName = 'CA' + uid;
    ObjC.registerSubclass({
      name: animClassName, superclass: 'NSObject',
      methods: { 'tick:': { types: ['void', ['id']], implementation: function(timer) {
        step.val++;
        var p = Math.min(step.val / animSteps, 1.0);
        if (p > 0.85) {
          win.setAlphaValue(0.99 - ((p - 0.85) / 0.15) * 0.99);
        }
        if (step.val >= animSteps) {
          timer.invalidate();
          win.setAlphaValue(0.0);
          win.orderOut(null);
        }
      }}}
    });

    var anim = $[animClassName].alloc.init;
    $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(
      animInterval, anim, 'tick:', null, true);
    $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(
      dismiss + 0.3, $.NSApp, 'terminate:', null, false);
  }

  // Event-driven dismissal from siblings
  var obsClassName = 'CDO' + uid;
  ObjC.registerSubclass({
    name: obsClassName, superclass: 'NSObject',
    methods: { 'handleDismiss:': { types: ['void', ['id']], implementation: function(n) {
      $.NSApp.terminate(null);
    }}}
  });
  var obs = $[obsClassName].alloc.init;
  $.NSDistributedNotificationCenter.defaultCenter.addObserverSelectorNameObject(
    obs, 'handleDismiss:', $(dismissNotificationName), $.NSString.string
  );

  $.NSApp.run;
}

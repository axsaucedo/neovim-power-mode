use cocoa::appkit::{
    NSApp, NSApplication, NSApplicationActivationPolicy, NSBackingStoreType, NSWindow,
    NSWindowCollectionBehavior, NSWindowStyleMask,
};
use cocoa::base::{id, nil, NO, YES};
use cocoa::foundation::{NSAutoreleasePool, NSRect};
use core_foundation::runloop::{
    kCFRunLoopDefaultMode, CFRunLoop, CFRunLoopTimer, CFRunLoopTimerContext, CFRunLoopTimerRef,
};
use core_graphics::context::CGContext;
use core_graphics::geometry::{CGPoint, CGRect, CGSize};
use objc::declare::ClassDecl;
use objc::runtime::{Class, Object, Sel, BOOL};
use objc::{class, msg_send, sel, sel_impl};
use serde::Deserialize;
use std::ffi::c_void;
use std::io::{self, BufRead};
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

// ---------------------------------------------------------------------------
// JSON protocol (same as Swift/Python overlays)
// ---------------------------------------------------------------------------

#[derive(Deserialize, Debug)]
struct Event {
    event: String,
    #[serde(default)]
    row: f64,
    #[serde(default)]
    col: f64,
    #[serde(default)]
    combo: i32,
    #[serde(default)]
    level: i32,
}

// ---------------------------------------------------------------------------
// Particle system
// ---------------------------------------------------------------------------

#[derive(Clone)]
struct Particle {
    x: f64,
    y: f64,
    vx: f64,
    vy: f64,
    r: f64,
    g: f64,
    b: f64,
    alpha: f64,
    lifetime: f64,
    max_lifetime: f64,
    radius: f64,
}

struct AppState {
    particles: Vec<Particle>,
    combo: i32,
    level: i32,
    cursor_x: f64,
    cursor_y: f64,
    #[allow(dead_code)]
    screen_width: f64,
    screen_height: f64,
    iterm_bounds: Option<(f64, f64, f64, f64)>,
    last_bounds_fetch: Instant,
    bounds_fetching: bool,
    window: id,
    content_view: id,
}

// SAFETY: we only touch `window`/`content_view` from the main thread.
unsafe impl Send for AppState {}
unsafe impl Sync for AppState {}

const NEON_COLORS: [(f64, f64, f64); 4] = [
    (0.0, 1.0, 1.0),    // cyan
    (1.0, 0.078, 0.576), // pink
    (0.749, 0.0, 1.0),   // purple
    (0.224, 1.0, 0.078), // green
];

impl AppState {
    fn new(screen_width: f64, screen_height: f64) -> Self {
        AppState {
            particles: Vec::with_capacity(500),
            combo: 0,
            level: 0,
            cursor_x: 0.0,
            cursor_y: 0.0,
            screen_width,
            screen_height,
            iterm_bounds: None,
            last_bounds_fetch: Instant::now() - Duration::from_secs(10),
            bounds_fetching: false,
            window: nil,
            content_view: nil,
        }
    }

    fn fetch_iterm_bounds_async(state: &Arc<Mutex<AppState>>) {
        let state_clone = state.clone();
        thread::spawn(move || {
            let output = Command::new("osascript")
                .arg("-e")
                .arg(r#"
tell application "iTerm2"
    set w to front window
    set b to bounds of w
    set x1 to item 1 of b as text
    set y1 to item 2 of b as text
    set x2 to item 3 of b as text
    set y2 to item 4 of b as text
    return x1 & "," & y1 & "," & x2 & "," & y2
end tell
"#)
                .output();

            if let Ok(out) = output {
                if let Ok(s) = String::from_utf8(out.stdout) {
                    let parts: Vec<f64> = s
                        .trim()
                        .split(',')
                        .filter_map(|p| p.trim().parse().ok())
                        .collect();
                    if parts.len() == 4 {
                        let mut s = state_clone.lock().unwrap();
                        s.iterm_bounds = Some((parts[0], parts[1], parts[2], parts[3]));
                        s.last_bounds_fetch = Instant::now();
                        s.bounds_fetching = false;
                    }
                }
            }
        });
    }

    fn cursor_to_screen(&self, row: f64, col: f64) -> (f64, f64) {
        let cell_w = 8.0;
        let cell_h = 16.0;
        let y_offset = 70.0;
        let x_offset = 4.0;

        if let Some((bx, by, _, _)) = self.iterm_bounds {
            let sx = bx + x_offset + col * cell_w;
            let sy = self.screen_height - (by + y_offset + row * cell_h);
            (sx, sy)
        } else {
            (col * cell_w + 80.0, self.screen_height - (row * cell_h + 70.0))
        }
    }

    fn should_fetch_bounds(&self) -> bool {
        !self.bounds_fetching && self.last_bounds_fetch.elapsed() >= Duration::from_secs(2)
    }

    fn spawn_particles(&mut self, x: f64, y: f64, count: usize) {
        use std::f64::consts::PI;
        for _ in 0..count {
            if self.particles.len() >= 500 {
                break;
            }
            // 60% upward bias, 40% random
            let angle = if rand_f64() < 0.6 {
                PI / 4.0 + rand_f64() * PI / 2.0  // 45° to 135° (upward)
            } else {
                rand_f64() * 2.0 * PI  // full circle
            };
            let speed = 150.0 + rand_f64() * 300.0;
            let (cr, cg, cb) = NEON_COLORS[(rand_f64() * 4.0) as usize % 4];
            let lt = 0.5 + rand_f64() * 1.0;
            self.particles.push(Particle {
                x,
                y,
                vx: angle.cos() * speed,
                vy: angle.sin() * speed,
                r: cr,
                g: cg,
                b: cb,
                alpha: 1.0,
                lifetime: lt,
                max_lifetime: lt,
                radius: 2.0 + rand_f64() * 8.0,
            });
        }
    }

    fn update(&mut self, dt: f64) {
        let gravity = 200.0;
        let drag = 0.95;
        self.particles.retain_mut(|p| {
            p.lifetime -= dt;
            if p.lifetime <= 0.0 {
                return false;
            }
            p.vy -= gravity * dt;
            p.vx *= drag;
            p.vy *= drag;
            p.x += p.vx * dt;
            p.y += p.vy * dt;
            p.alpha = (p.lifetime / p.max_lifetime).max(0.0);
            true
        });
    }
}

// ---------------------------------------------------------------------------
// Simple LCG random — good enough for particle effects
// ---------------------------------------------------------------------------

fn rand_f64() -> f64 {
    use std::cell::Cell;
    thread_local! {
        static SEED: Cell<u64> = Cell::new(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos() as u64
        );
    }
    SEED.with(|s| {
        let v = s
            .get()
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        s.set(v);
        (v >> 33) as f64 / (1u64 << 31) as f64
    })
}

// ---------------------------------------------------------------------------
// Custom NSView subclass for drawing particles via Core Graphics
// ---------------------------------------------------------------------------

static mut GLOBAL_STATE: *const Mutex<AppState> = std::ptr::null();

extern "C" fn draw_rect(this: &Object, _sel: Sel, _dirty: NSRect) {
    unsafe {
        if GLOBAL_STATE.is_null() {
            return;
        }
        let state_mutex = &*GLOBAL_STATE;
        let state = state_mutex.lock().unwrap();

        // Get the current NSGraphicsContext's CGContext
        let ns_ctx: id = msg_send![class!(NSGraphicsContext), currentContext];
        if ns_ctx == nil {
            return;
        }
        let cg_ctx_ref: core_graphics::sys::CGContextRef = msg_send![ns_ctx, CGContext];
        if cg_ctx_ref.is_null() {
            return;
        }

        // Wrap raw pointer in safe CGContext (non-owning)
        let cg = CGContext::from_existing_context_ptr(cg_ctx_ref);

        // Clear
        let frame: NSRect = msg_send![this, bounds];
        cg.clear_rect(CGRect::new(
            &CGPoint::new(0.0, 0.0),
            &CGSize::new(frame.size.width, frame.size.height),
        ));

        // Draw each particle with glow + trail + core
        for p in &state.particles {
            // Layer 1: Outer glow (large blurred circle at low alpha)
            let glow_radius = p.radius * 3.0;
            let glow_alpha = p.alpha * 0.2;
            cg.set_rgb_fill_color(p.r, p.g, p.b, glow_alpha);
            let glow_rect = CGRect::new(
                &CGPoint::new(p.x - glow_radius, p.y - glow_radius),
                &CGSize::new(glow_radius * 2.0, glow_radius * 2.0),
            );
            cg.fill_ellipse_in_rect(glow_rect);

            // Layer 2: Comet trail (3 trailing circles along negative velocity)
            for t in 1..=3 {
                let trail_factor = t as f64 * 0.008;
                let trail_x = p.x - p.vx * trail_factor;
                let trail_y = p.y - p.vy * trail_factor;
                let trail_alpha = p.alpha * (1.0 - t as f64 / 4.0) * 0.6;
                let trail_radius = p.radius * (1.0 - t as f64 / 5.0);
                cg.set_rgb_fill_color(p.r, p.g, p.b, trail_alpha);
                let trail_rect = CGRect::new(
                    &CGPoint::new(trail_x - trail_radius, trail_y - trail_radius),
                    &CGSize::new(trail_radius * 2.0, trail_radius * 2.0),
                );
                cg.fill_ellipse_in_rect(trail_rect);
            }

            // Layer 3: Main body
            cg.set_rgb_fill_color(p.r, p.g, p.b, p.alpha);
            let rect = CGRect::new(
                &CGPoint::new(p.x - p.radius, p.y - p.radius),
                &CGSize::new(p.radius * 2.0, p.radius * 2.0),
            );
            cg.fill_ellipse_in_rect(rect);

            // Layer 4: Hot white core (small bright center)
            let core_radius = p.radius * 0.4;
            let core_alpha = (p.alpha * 1.5).min(1.0);
            cg.set_rgb_fill_color(1.0, 1.0, 1.0, core_alpha);
            let core_rect = CGRect::new(
                &CGPoint::new(p.x - core_radius, p.y - core_radius),
                &CGSize::new(core_radius * 2.0, core_radius * 2.0),
            );
            cg.fill_ellipse_in_rect(core_rect);
        }
    }
}

extern "C" fn is_opaque(_this: &Object, _sel: Sel) -> BOOL {
    NO
}

fn register_particle_view_class() -> &'static Class {
    let superclass = class!(NSView);
    let mut decl = ClassDecl::new("ParticleView", superclass).unwrap();
    unsafe {
        decl.add_method(
            sel!(drawRect:),
            draw_rect as extern "C" fn(&Object, Sel, NSRect),
        );
        decl.add_method(
            sel!(isOpaque),
            is_opaque as extern "C" fn(&Object, Sel) -> BOOL,
        );
    }
    decl.register()
}

// ---------------------------------------------------------------------------
// CFRunLoopTimer callback – drives the animation at ~60 fps
// ---------------------------------------------------------------------------

extern "C" fn timer_callback(_timer: CFRunLoopTimerRef, info: *mut c_void) {
    unsafe {
        if info.is_null() {
            return;
        }
        let state_mutex = &*(info as *const Mutex<AppState>);
        let mut state = state_mutex.lock().unwrap();
        state.update(1.0 / 60.0);

        let view = state.content_view;
        if view != nil {
            let needs = !state.particles.is_empty();
            drop(state); // release lock before calling into Cocoa
            if needs {
                let _: () = msg_send![view, setNeedsDisplay: YES];
            } else {
                let _: () = msg_send![view, setNeedsDisplay: YES]; // clear
            }
        }
    }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

fn main() {
    unsafe {
        let _pool = NSAutoreleasePool::new(nil);
        let app = NSApp();
        app.setActivationPolicy_(
            NSApplicationActivationPolicy::NSApplicationActivationPolicyAccessory,
        );

        // Screen size
        let screen: id = msg_send![class!(NSScreen), mainScreen];
        let frame: NSRect = msg_send![screen, frame];
        let screen_width = frame.size.width;
        let screen_height = frame.size.height;

        // Create transparent, click-through, always-on-top window
        let window = NSWindow::alloc(nil).initWithContentRect_styleMask_backing_defer_(
            frame,
            NSWindowStyleMask::NSBorderlessWindowMask,
            NSBackingStoreType::NSBackingStoreBuffered,
            NO,
        );

        let clear_color: id = msg_send![class!(NSColor), clearColor];
        let _: () = msg_send![window, setBackgroundColor: clear_color];
        let _: () = msg_send![window, setOpaque: NO];
        let _: () = msg_send![window, setLevel: 3i64]; // NSFloatingWindowLevel
        let _: () = msg_send![window, setIgnoresMouseEvents: YES];
        let _: () = msg_send![window, setHasShadow: NO];
        let behavior = NSWindowCollectionBehavior::NSWindowCollectionBehaviorCanJoinAllSpaces
            | NSWindowCollectionBehavior::NSWindowCollectionBehaviorStationary;
        let _: () = msg_send![window, setCollectionBehavior: behavior];

        // Register and create the custom view
        let view_class = register_particle_view_class();
        let view: id = msg_send![view_class, alloc];
        let view: id = msg_send![view, initWithFrame: frame];
        let _: () = msg_send![window, setContentView: view];
        window.makeKeyAndOrderFront_(nil);

        // Shared state
        let state = Arc::new(Mutex::new(AppState::new(screen_width, screen_height)));
        {
            let mut s = state.lock().unwrap();
            s.window = window;
            s.content_view = view;
        }

        // Store raw pointer for the C callbacks
        let state_ptr = Arc::into_raw(state.clone());
        GLOBAL_STATE = state_ptr;

        // stdin reader thread
        let state_clone = state.clone();
        thread::spawn(move || {
            let stdin = io::stdin();
            for line in stdin.lock().lines() {
                if let Ok(line) = line {
                    if line.is_empty() {
                        continue;
                    }
                    if let Ok(event) = serde_json::from_str::<Event>(&line) {
                        let mut s = state_clone.lock().unwrap();
                        s.combo = event.combo;
                        s.level = event.level;
                        if s.should_fetch_bounds() {
                            s.bounds_fetching = true;
                            drop(s);
                            AppState::fetch_iterm_bounds_async(&state_clone);
                            s = state_clone.lock().unwrap();
                        }
                        let (sx, sy) = s.cursor_to_screen(event.row, event.col);
                        s.cursor_x = sx;
                        s.cursor_y = sy;
                        if event.event == "keystroke" {
                            let count = 8 + (event.level * 3) as usize;
                            let x = s.cursor_x;
                            let y = s.cursor_y;
                            s.spawn_particles(x, y, count);
                        }
                    }
                }
            }
            eprintln!("[rust-overlay] stdin closed, exiting");
            std::process::exit(0);
        });

        // 60 fps timer on the main run loop
        let mut ctx = CFRunLoopTimerContext {
            version: 0,
            info: state_ptr as *mut c_void,
            retain: None,
            release: None,
            copyDescription: None,
        };
        let timer = CFRunLoopTimer::new(
            0.0,                // fire date (now)
            1.0 / 60.0,        // interval
            0,                  // flags
            0,                  // order
            timer_callback,
            &mut ctx,
        );
        CFRunLoop::get_current().add_timer(&timer, kCFRunLoopDefaultMode);

        eprintln!("[rust-overlay] Power Mode overlay running (Rust). Send JSON to stdin.");
        eprintln!("[rust-overlay] Screen: {}x{}", screen_width, screen_height);

        app.run();
    }
}

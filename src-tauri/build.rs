use std::env;
use std::process::Command;

fn get_zig_path() -> String {
    let home = match env::var("HOME") {
        Ok(v) => v,
        Err(e) => panic!("HOME is not set ({})", e)
    };

    return format!("{}/.local/bin/zig", home);
}

fn compile_backend() {
    let zig_out = Command::new(get_zig_path())
        .current_dir("./../backend")
        .arg("build")
        .arg("-Doptimize=ReleaseSafe")
        .output();

    match zig_out {
        Ok(compile_lib) => {
            if compile_lib.status.success() {
                println!("zig output:\n{}", String::from_utf8_lossy(&compile_lib.stdout));
            } else {
                panic!("'zig build' failed:\n{}", String::from_utf8_lossy(&compile_lib.stderr))
            }
        }
        Err(e) => panic!("failed to run 'zig build'. Check zig path: {}", e)
    }
}

fn main() {
    // TODO: below rerun doesn't work
    println!("cargo:rerun-if-changed=/Users/jalal/projects/modex/modex/backend/src/main.zig");
    println!("cargo:rustc-link-search=./../backend/zig-out/lib");

    compile_backend();
    tauri_build::build()
}

use std::{env, fs, path::{Path, PathBuf}, process::Command};

fn read_toolchain(path: &Path) -> Option<String> {
    fs::read_to_string(path)
        .ok()
        .and_then(|s| s.lines().next().map(|l| l.trim().to_string()))
        .filter(|s| !s.is_empty())
}

fn toolchain_dir_name(toolchain: &str) -> String {
    toolchain.replace('/', "--").replace(':', "---")
}

fn lean_sysroot(repo_root: &Path, example_dir: &Path) -> PathBuf {
    if let Ok(root) = env::var("LEAN_SYSROOT") {
        return PathBuf::from(root);
    }
    if let Ok(root) = env::var("LEAN_ROOT") {
        return PathBuf::from(root);
    }

    let toolchain = read_toolchain(&example_dir.join("lean-toolchain"))
        .or_else(|| read_toolchain(&repo_root.join("lean-toolchain")))
        .expect("lean-toolchain not found");

    let elan_home = env::var("ELAN_HOME")
        .ok()
        .or_else(|| env::var("HOME").ok().map(|h| format!("{}/.elan", h)))
        .expect("ELAN_HOME or HOME not set");

    let dir_name = toolchain_dir_name(&toolchain);
    PathBuf::from(elan_home).join("toolchains").join(dir_name)
}

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let repo_root = manifest_dir
        .parent()
        .and_then(|p| p.parent())
        .expect("repo root");

    let example_name = env::var("LITHE_EXAMPLE").unwrap_or_else(|_| "hello".to_string());
    let example_dir = repo_root.join("examples").join(&example_name);
    let ir_dir = example_dir.join(".lake/build/ir");
    let lithe_ir_dir = repo_root.join(".lake/build/ir");

    let skip_lake = env::var("LITHE_SKIP_LAKE_BUILD").is_ok();
    if !skip_lake {
        let status = Command::new("lake")
            .arg("build")
            .current_dir(&example_dir)
            .status()
            .expect("failed to run lake build for example");
        if !status.success() {
            panic!("lake build failed for example");
        }
    } else if !ir_dir.exists() {
        panic!("missing {} (set LITHE_SKIP_LAKE_BUILD only if C output exists)", ir_dir.display());
    }

    let lean_root = lean_sysroot(&repo_root, &example_dir);
    if !lean_root.exists() {
        panic!("Lean sysroot not found at {}", lean_root.display());
    }
    println!("cargo:rustc-link-lib=dylib=leanshared");
    let lean_lib_dir = lean_root.join("lib/lean");
    println!(
        "cargo:rustc-link-search=native={}",
        lean_lib_dir.display()
    );
    if env::var("CARGO_CFG_TARGET_OS").unwrap_or_default() != "windows" {
        println!(
            "cargo:rustc-link-arg=-Wl,-rpath,{}",
            lean_lib_dir.display()
        );
    }

    let mut build = cc::Build::new();
    build.include(lean_root.join("include"));
    build.flag_if_supported("-std=c11");

    let mut c_files: Vec<PathBuf> = Vec::new();
    for entry in walkdir::WalkDir::new(&ir_dir) {
        let entry = entry.unwrap();
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) == Some("c") {
            c_files.push(path.to_path_buf());
        }
    }
    for entry in walkdir::WalkDir::new(&lithe_ir_dir) {
        let entry = entry.unwrap();
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) == Some("c") {
            c_files.push(path.to_path_buf());
        }
    }

    if c_files.is_empty() {
        panic!("no C files found in {}", ir_dir.display());
    }

    for file in &c_files {
        build.file(file);
    }
    build.file(manifest_dir.join("lean_shim.c"));

    build.compile("lithe_example");

    for file in c_files {
        println!("cargo:rerun-if-changed={}", file.display());
    }
    println!("cargo:rerun-if-changed={}", manifest_dir.join("lean_shim.c").display());
    for entry in walkdir::WalkDir::new(&example_dir) {
        let entry = entry.unwrap();
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) == Some("lean") {
            println!("cargo:rerun-if-changed={}", path.display());
        }
    }
    for entry in walkdir::WalkDir::new(&repo_root.join("Lithe")) {
        let entry = entry.unwrap();
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) == Some("lean") {
            println!("cargo:rerun-if-changed={}", path.display());
        }
    }
    println!("cargo:rerun-if-changed={}", example_dir.join("lakefile.lean").display());
    println!("cargo:rerun-if-changed={}", repo_root.join("lakefile.lean").display());
    println!("cargo:rerun-if-changed={}", example_dir.join("lean-toolchain").display());
    println!("cargo:rerun-if-changed={}", repo_root.join("lean-toolchain").display());
    println!("cargo:rerun-if-env-changed=LEAN_SYSROOT");
    println!("cargo:rerun-if-env-changed=LEAN_ROOT");
    println!("cargo:rerun-if-env-changed=ELAN_HOME");
    println!("cargo:rerun-if-env-changed=LITHE_SKIP_LAKE_BUILD");
    println!("cargo:rerun-if-env-changed=LITHE_EXAMPLE");
    println!("cargo:rustc-cfg=lithe_example=\"{}\"", example_name);
}

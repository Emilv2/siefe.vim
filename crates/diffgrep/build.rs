fn main() {
    // Embed the short git hash at build time so --version can report it.
    let hash = std::process::Command::new("git")
        .args(["rev-parse", "--short", "HEAD"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_owned())
        .unwrap_or_else(|| "unknown".to_owned());
    println!("cargo:rustc-env=SIEFE_GIT_HASH={hash}");

    // Walk up from the crate root to find .git/HEAD and rerun on commit.
    let manifest = std::env::var("CARGO_MANIFEST_DIR").unwrap_or_default();
    let mut dir = std::path::Path::new(&manifest);
    loop {
        let head = dir.join(".git/HEAD");
        if head.exists() {
            println!("cargo:rerun-if-changed={}", head.display());
            break;
        }
        match dir.parent() {
            Some(p) => dir = p,
            None => break,
        }
    }
}

// alpm (Rust) - the start of a compiled rewrite of Arctic's package manager.
//
// Second slice: named installs with dependency resolution against the same
// repo config and sync index format the shell alpm uses, so both can read
// the same /etc/alpm/repos.d and /var/lib/alpm/sync.
//
//   alpm-rs ins <path-to.alpmz> [--root DIR]     install a local file
//   alpm-rs ins <name> [--root DIR]              resolve + install by name
//   alpm-rs fetch [--root DIR]                   sync repo indexes
//   alpm-rs list [--root DIR]
//
// Shells out to tar/xz/curl rather than pulling in archive/http crates - a
// pragmatic choice for this stage, revisited later.

use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

struct PkgInfo {
    fields: BTreeMap<String, String>,
    depends: Vec<String>,
}

impl PkgInfo {
    fn get(&self, key: &str) -> Option<&str> {
        self.fields.get(key).map(|s| s.as_str())
    }
}

fn parse_pkginfo(text: &str) -> PkgInfo {
    let mut fields = BTreeMap::new();
    let mut depends = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            let k = k.trim().to_string();
            let v = v.trim().to_string();
            if k == "depend" {
                depends.push(v);
            } else {
                fields.insert(k, v);
            }
        }
    }
    PkgInfo { fields, depends }
}

fn die(msg: &str) -> ! {
    eprintln!("error: {msg}");
    std::process::exit(1);
}

fn root_relative(root: &str, sub: &str) -> PathBuf {
    let root = root.trim_end_matches('/');
    PathBuf::from(format!("{root}/{sub}"))
}

// Matches libalpm.sh: ALPM_DB defaults to ${ALPM_ROOT%/}/var/lib/alpm - same
// root-relative default the shell version now uses, on purpose, so a
// package installed by one is visible to the other.
fn alpm_db(root: &str) -> PathBuf {
    root_relative(root, "var/lib/alpm")
}

fn extract_alpmz(pkg_path: &Path, dest: &Path) {
    fs::create_dir_all(dest).unwrap_or_else(|e| die(&format!("mkdir {}: {e}", dest.display())));
    let status = Command::new("tar")
        .arg("-xf")
        .arg(pkg_path)
        .arg("-C")
        .arg(dest)
        .status()
        .unwrap_or_else(|e| die(&format!("running tar: {e}")));
    if !status.success() {
        die(&format!("tar extract of {} failed", pkg_path.display()));
    }
}

fn walk(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        let Ok(read) = fs::read_dir(&d) else { continue };
        for entry in read.flatten() {
            let path = entry.path();
            out.push(path.clone());
            if path.is_dir() && !path.is_symlink() {
                stack.push(path);
            }
        }
    }
    out
}

fn cmd_ins(pkg_path: &str, root: &str) {
    let pkg_path = Path::new(pkg_path);
    if !pkg_path.is_file() {
        die(&format!("no such file: {}", pkg_path.display()));
    }

    let work = env::temp_dir().join(format!(
        "alpm-rs-{}-{}",
        std::process::id(),
        pkg_path.file_stem().unwrap().to_string_lossy()
    ));
    extract_alpmz(pkg_path, &work);

    let pkginfo_text = fs::read_to_string(work.join(".PKGINFO"))
        .unwrap_or_else(|e| die(&format!(".PKGINFO missing or unreadable: {e}")));
    let info = parse_pkginfo(&pkginfo_text);
    let name = info.get("name").unwrap_or_else(|| die("no 'name' in .PKGINFO")).to_string();
    let version = info.get("version").unwrap_or("0").to_string();
    let release = info.get("release").unwrap_or("1").to_string();

    println!(":: installing {name} {version}-{release}");

    // Copy the payload into root, skipping the package metadata files -
    // matches what the shell version's bsdtar pipe does.
    for entry in walk(&work) {
        let rel = entry.strip_prefix(&work).unwrap();
        let rel_str = rel.to_string_lossy();
        if rel_str == ".PKGINFO" || rel_str == ".FILES" || rel_str == ".INSTALL" || rel_str.is_empty()
        {
            continue;
        }
        let dest = root_relative(root, &rel_str);
        if entry.is_dir() {
            fs::create_dir_all(&dest).ok();
        } else if entry.is_file() {
            if let Some(parent) = dest.parent() {
                fs::create_dir_all(parent).ok();
            }
            fs::copy(&entry, &dest)
                .unwrap_or_else(|e| die(&format!("copying {}: {e}", entry.display())));
            if let Ok(meta) = fs::metadata(&entry) {
                use std::os::unix::fs::PermissionsExt;
                let _ = fs::set_permissions(&dest, meta.permissions());
                let _ = meta.permissions().mode();
            }
        }
    }

    // Record it in the local database - same file layout the shell alpm
    // writes, so `alpm list`/`is_installed`/rollback etc. still see it.
    let db = alpm_db(root).join("local").join(&name);
    fs::create_dir_all(&db).unwrap_or_else(|e| die(&format!("mkdir {}: {e}", db.display())));
    fs::write(db.join("PKGINFO"), &pkginfo_text).unwrap();
    fs::write(db.join("REASON"), "explicit\n").unwrap();
    fs::write(db.join("DEPS"), info.depends.join("\n") + "\n").unwrap();
    fs::write(db.join("STATE"), "activated = yes\n").unwrap();

    let mut files_list = String::new();
    for entry in walk(&work) {
        let rel = entry.strip_prefix(&work).unwrap();
        let rel_str = rel.to_string_lossy();
        if rel_str.is_empty() || (rel_str.starts_with('.') && !rel_str.contains('/')) {
            continue;
        }
        if entry.is_file() || entry.is_symlink() {
            files_list.push('/');
            files_list.push_str(&rel_str);
            files_list.push('\n');
        }
    }
    fs::write(db.join("FILES"), &files_list).unwrap();

    fs::remove_dir_all(&work).ok();
    println!("   ok  {name} {version}-{release} installed ({} files)", files_list.lines().count());
}

// -------------------------------------------------------------- repos + index

struct Repo {
    name: String,
    url: String,
}

fn alpm_repod() -> PathBuf {
    // Host-absolute regardless of --root, same as the shell version: repo
    // config is the tool's own configuration, not the target root's state.
    // Overridable via ALPM_REPOD, matching libalpm.sh's own `:` default.
    match env::var("ALPM_REPOD") {
        Ok(v) if !v.is_empty() => PathBuf::from(v),
        _ => PathBuf::from("/etc/alpm/repos.d"),
    }
}

fn load_repos() -> Vec<Repo> {
    let mut repos = Vec::new();
    let Ok(read) = fs::read_dir(alpm_repod()) else { return repos };
    for entry in read.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("repo") {
            continue;
        }
        let Ok(text) = fs::read_to_string(&path) else { continue };
        let mut name = String::new();
        let mut url = String::new();
        let mut enabled = true;
        for line in text.lines() {
            let line = line.trim();
            if line.starts_with('#') || line.is_empty() {
                continue;
            }
            if let Some((k, v)) = line.split_once('=') {
                let v = v.trim().to_string();
                match k.trim() {
                    "name" => name = v,
                    "url" => url = v,
                    "enabled" => enabled = v == "yes",
                    _ => {}
                }
            }
        }
        if name.is_empty() {
            name = path.file_stem().unwrap().to_string_lossy().to_string();
        }
        if enabled && !url.is_empty() {
            repos.push(Repo { name, url });
        }
    }
    repos
}

#[derive(Clone)]
struct IndexEntry {
    repo: String,
    name: String,
    version: String,
    release: String,
    deps: Vec<String>,
}

fn sync_dir(root: &str) -> PathBuf {
    alpm_db(root).join("sync")
}

fn load_index(root: &str) -> BTreeMap<String, IndexEntry> {
    let mut map = BTreeMap::new();
    let dir = sync_dir(root);
    let Ok(read) = fs::read_dir(&dir) else { return map };
    for entry in read.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("idx") {
            continue;
        }
        let repo = path.file_stem().unwrap().to_string_lossy().to_string();
        let Ok(text) = fs::read_to_string(&path) else { continue };
        for line in text.lines() {
            if line.starts_with('#') || line.trim().is_empty() {
                continue;
            }
            let f: Vec<&str> = line.split('\t').collect();
            if f.len() < 8 {
                continue;
            }
            let name = f[0].to_string();
            let deps: Vec<String> = f[7]
                .split_whitespace()
                .map(|s| s.to_string())
                .collect();
            map.insert(
                name.clone(),
                IndexEntry {
                    repo: repo.clone(),
                    name,
                    version: f[1].to_string(),
                    release: f[2].to_string(),
                    deps,
                },
            );
        }
    }
    map
}

fn is_installed(root: &str, name: &str) -> bool {
    alpm_db(root).join("local").join(name).join("PKGINFO").is_file()
}

// None if not installed; otherwise "version-release" as recorded locally.
fn installed_version(root: &str, name: &str) -> Option<String> {
    let pkginfo = alpm_db(root).join("local").join(name).join("PKGINFO");
    let text = fs::read_to_string(pkginfo).ok()?;
    let info = parse_pkginfo(&text);
    let v = info.get("version")?.to_string();
    let r = info.get("release").unwrap_or("1").to_string();
    Some(format!("{v}-{r}"))
}

// Depth-first, dependencies before the package that needs them, each name
// appearing once even if several packages depend on it. "-" in a deps field
// is the index's sentinel for "no dependencies" (see gen-ports.py), not a
// package name. A dep missing from the index but already installed is left
// alone rather than erroring, matching the shell alpm's _resolve.
fn resolve(names: &[String], index: &BTreeMap<String, IndexEntry>, root: &str) -> Vec<String> {
    let mut seen = BTreeSet::new();
    let mut order = Vec::new();
    fn visit(
        name: &str,
        index: &BTreeMap<String, IndexEntry>,
        root: &str,
        seen: &mut BTreeSet<String>,
        order: &mut Vec<String>,
    ) {
        if seen.contains(name) {
            return;
        }
        seen.insert(name.to_string());
        match index.get(name) {
            Some(entry) => {
                for dep in &entry.deps {
                    if dep == "-" {
                        continue;
                    }
                    visit(dep, index, root, seen, order);
                }
                order.push(name.to_string());
            }
            None => {
                if is_installed(root, name) {
                    return;
                }
                die(&format!("package not found: {name} (try 'alpm-rs fetch' first)"));
            }
        }
    }
    for n in names {
        visit(n, index, root, &mut seen, &mut order);
    }
    order
}

fn cmd_fetch(root: &str) {
    let dir = sync_dir(root);
    fs::create_dir_all(&dir).unwrap_or_else(|e| die(&format!("mkdir {}: {e}", dir.display())));
    for repo in load_repos() {
        let idx_url = format!("{}/{}/INDEX", repo.url.trim_end_matches('/'), std::env::consts::ARCH);
        let dest = dir.join(format!("{}.idx", repo.name));
        let raw = fetch_to_string(&idx_url);
        match raw {
            Some(text) => {
                let filtered: String = text
                    .lines()
                    .filter(|l| !l.starts_with('#') && !l.trim().is_empty())
                    .map(|l| format!("{l}\n"))
                    .collect();
                fs::write(&dest, filtered).ok();
                let n = fs::read_to_string(&dest).map(|t| t.lines().count()).unwrap_or(0);
                println!("  -> {:<12} ok  {n} packages", repo.name);
            }
            None => println!("  -> {:<12} FAILED ({idx_url})", repo.name),
        }
    }
}

fn fetch_to_string(url: &str) -> Option<String> {
    if let Some(path) = url.strip_prefix("file://") {
        return fs::read_to_string(path).ok();
    }
    let out = Command::new("curl")
        .args(["-fsSL", url])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    String::from_utf8(out.stdout).ok()
}

fn fetch_to_file(url: &str, dest: &Path) -> bool {
    if let Some(path) = url.strip_prefix("file://") {
        return fs::copy(path, dest).is_ok();
    }
    Command::new("curl")
        .args(["-fsSL", "-o"])
        .arg(dest)
        .arg(url)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn cmd_ins_named(name: &str, root: &str) {
    let index = load_index(root);
    if !index.contains_key(name) {
        die(&format!("package not found: {name} (try 'alpm-rs fetch' first)"));
    }
    let order = resolve(&[name.to_string()], &index, root);
    println!(":: resolved: {}", order.join(" "));

    // Root-relative, matching libalpm.sh's ALPM_CACHE default of
    // ${ALPM_ROOT%/}/var/cache/alpm - not a host-absolute path.
    let cache = root_relative(root, "var/cache/alpm/pkg");
    fs::create_dir_all(&cache).unwrap_or_else(|e| die(&format!("mkdir {}: {e}", cache.display())));

    for pkg_name in &order {
        // Already installed and not in the index (e.g. satisfied some other
        // way) - resolve() already vetted this, nothing left to do.
        let Some(entry) = index.get(pkg_name) else {
            continue;
        };
        let wanted = format!("{}-{}", entry.version, entry.release);
        if installed_version(root, pkg_name).as_deref() == Some(wanted.as_str()) {
            println!(":: {pkg_name} {wanted} is already installed");
            continue;
        }
        let fname = format!("{}-{}-{}.x86_64.alpmz", entry.name, entry.version, entry.release);
        let cached = cache.join(&fname);
        if !cached.is_file() {
            let repo = load_repos()
                .into_iter()
                .find(|r| r.name == entry.repo)
                .unwrap_or_else(|| die(&format!("no repo config for {}", entry.repo)));
            let url = format!("{}/{}/{}", repo.url.trim_end_matches('/'), std::env::consts::ARCH, fname);
            println!(":: fetching {fname}");
            if !fetch_to_file(&url, &cached) {
                die(&format!("could not fetch {url}"));
            }
        }
        cmd_ins(cached.to_str().unwrap(), root);
    }
}

fn cmd_list(root: &str) {
    let local = alpm_db(root).join("local");
    let Ok(read) = fs::read_dir(&local) else {
        println!("(no packages installed under {root})");
        return;
    };
    let mut names: Vec<String> = read
        .flatten()
        .filter(|e| e.path().is_dir())
        .map(|e| e.file_name().to_string_lossy().to_string())
        .collect();
    names.sort();
    for n in names {
        let pkginfo = local.join(&n).join("PKGINFO");
        let version = fs::read_to_string(&pkginfo)
            .ok()
            .and_then(|t| {
                let info = parse_pkginfo(&t);
                let v = info.get("version")?.to_string();
                let r = info.get("release").unwrap_or("1").to_string();
                Some(format!("{v}-{r}"))
            })
            .unwrap_or_else(|| "?".to_string());
        println!("{n} {version}");
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let mut root = "/".to_string();
    let mut rest: Vec<String> = Vec::new();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--root" => {
                i += 1;
                root = args.get(i).cloned().unwrap_or_else(|| die("--root needs a value"));
            }
            other => rest.push(other.to_string()),
        }
        i += 1;
    }

    match rest.first().map(|s| s.as_str()) {
        Some("ins") => {
            let pkg = rest.get(1).unwrap_or_else(|| die("usage: alpm-rs ins <name|path.alpmz> [--root DIR]"));
            if pkg.ends_with(".alpmz") || pkg.contains('/') {
                cmd_ins(pkg, &root);
            } else {
                cmd_ins_named(pkg, &root);
            }
        }
        Some("fetch") => cmd_fetch(&root),
        Some("list") => cmd_list(&root),
        _ => {
            eprintln!("alpm-rs - early Rust rewrite of alpm");
            eprintln!("usage:");
            eprintln!("  alpm-rs ins <name|path.alpmz> [--root DIR]");
            eprintln!("  alpm-rs fetch [--root DIR]");
            eprintln!("  alpm-rs list [--root DIR]");
            std::process::exit(1);
        }
    }
}

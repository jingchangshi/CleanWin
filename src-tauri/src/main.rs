use serde::Serialize;
use std::path::PathBuf;
use std::process::Command;
use tauri::{AppHandle, Manager};

#[derive(Serialize)]
struct ScriptResult {
    stdout: String,
    stderr: String,
    code: i32,
}

#[tauri::command]
fn run_diagnose(app: AppHandle) -> Result<ScriptResult, String> {
    run_script(&app, "diagnose-memory.ps1", &[])
}

#[tauri::command]
fn run_clean(app: AppHandle) -> Result<ScriptResult, String> {
    run_script(&app, "clean-memory.ps1", &[])
}

fn run_script(app: &AppHandle, script_name: &str, script_args: &[&str]) -> Result<ScriptResult, String> {
    let script_path = resolve_script_path(app, script_name)?;
    let script = quote_powershell_path(&script_path);
    let args = script_args.join(" ");
    let command_text = format!(
        "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(); $OutputEncoding = [Console]::OutputEncoding; & {} {}",
        script, args
    );

    let output = Command::new("powershell.exe")
        .arg("-NoProfile")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-Command")
        .arg(command_text)
        .output()
        .map_err(|error| format!("无法启动 powershell.exe：{}", error))?;

    Ok(ScriptResult {
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        code: output.status.code().unwrap_or(-1),
    })
}

fn resolve_script_path(app: &AppHandle, script_name: &str) -> Result<PathBuf, String> {
    let mut candidates = Vec::new();

    if let Ok(current_dir) = std::env::current_dir() {
        candidates.push(current_dir.join(script_name));
        candidates.push(current_dir.join("..").join(script_name));
    }

    if let Ok(resource_dir) = app.path().resource_dir() {
        candidates.push(resource_dir.join(script_name));
    }

    candidates
        .into_iter()
        .find(|path| path.exists())
        .ok_or_else(|| format!("找不到脚本文件：{}", script_name))
}

fn quote_powershell_path(path: &PathBuf) -> String {
    let text = path.to_string_lossy().replace('\'', "''");
    format!("'{}'", text)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![run_diagnose, run_clean])
        .run(tauri::generate_context!())
        .expect("failed to run CleanWin");
}

fn main() {
    run();
}

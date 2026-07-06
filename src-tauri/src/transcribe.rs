// Wikily local transcription (Tech Spec §5.4).
//
// Local-first goal path: transcribe VAD-gated WAV utterance buffers entirely
// on-device via a bundled whisper.cpp sidecar, so call audio never leaves the
// machine (§4.2 / §9). This module is the Rust half of that path.
//
// Scaffold status: the sidecar binary + CoreML model bundling
// (`tauri.conf.json` `externalBin`, notarization) is a macOS build-pipeline
// follow-up, so when the sidecar/model is not present this command returns a
// typed `LOCAL_TRANSCRIPTION_UNAVAILABLE` error. The frontend detects that and
// either falls back to the opt-in cloud STT path or prompts the user to finish
// local setup — nothing crashes and the cloud fallback keeps working today.

use base64::{engine::general_purpose, Engine as _};
use std::path::PathBuf;
use tauri::AppHandle;
use tauri_plugin_shell::ShellExt;

/// Sentinel prefix the frontend matches to decide whether to degrade to cloud.
const UNAVAILABLE: &str = "LOCAL_TRANSCRIPTION_UNAVAILABLE";

/// Name of the whisper.cpp sidecar as it will be declared under
/// `bundle.externalBin` once packaging lands.
const WHISPER_SIDECAR: &str = "whisper-cli";

/// Resolve the whisper model path. Defaults to a conventional bundled location
/// but is overridable via `WIKILY_WHISPER_MODEL` so a dev can point at a local
/// `ggml-*.bin` without a full bundle.
fn model_path() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("WIKILY_WHISPER_MODEL") {
        let path = PathBuf::from(p);
        if path.exists() {
            return Some(path);
        }
    }
    None
}

/// Transcribe a single WAV utterance buffer on-device.
///
/// `wav_base64` is the base64-encoded WAV produced by the VAD pipeline. Returns
/// the recognised text, or an error string beginning with `UNAVAILABLE` when the
/// local model/sidecar is not installed yet.
#[tauri::command]
pub async fn transcribe_local(app: AppHandle, wav_base64: String) -> Result<String, String> {
    let model = match model_path() {
        Some(m) => m,
        None => {
            return Err(format!(
                "{UNAVAILABLE}: whisper.cpp model not found. Set WIKILY_WHISPER_MODEL \
                 or bundle a model, or enable the cloud transcription fallback in Settings."
            ));
        }
    };

    // Decode and stage the WAV to a temp file for the sidecar to read.
    let bytes = general_purpose::STANDARD
        .decode(wav_base64.as_bytes())
        .map_err(|e| format!("Invalid base64 WAV: {e}"))?;
    let tmp = std::env::temp_dir().join(format!("wikily-{}.wav", uuid::Uuid::new_v4()));
    std::fs::write(&tmp, &bytes).map_err(|e| format!("Failed to stage WAV: {e}"))?;

    // Build the sidecar command. If the sidecar isn't declared/bundled this
    // errors out cleanly and we surface the UNAVAILABLE sentinel.
    let command = app.shell().sidecar(WHISPER_SIDECAR).map_err(|e| {
        format!("{UNAVAILABLE}: whisper.cpp sidecar not installed ({e}).")
    })?;

    let model_arg = model.to_string_lossy().to_string();
    let file_arg = tmp.to_string_lossy().to_string();
    let result = command
        .args([
            "-m",
            &model_arg,
            "-f",
            &file_arg,
            "-nt", // no timestamps: we want plain text
            "-otxt",
        ])
        .output()
        .await;

    // Best-effort cleanup regardless of outcome.
    let _ = std::fs::remove_file(&tmp);

    match result {
        Ok(output) if output.status.success() => {
            Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
        }
        Ok(output) => Err(format!(
            "whisper.cpp failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        )),
        Err(e) => Err(format!("{UNAVAILABLE}: failed to run whisper.cpp sidecar ({e}).")),
    }
}

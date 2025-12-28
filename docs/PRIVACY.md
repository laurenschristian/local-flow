# Privacy Policy

**Last updated:** December 2024

## Summary

LocalFlow is designed with privacy as a core principle. Your voice data never leaves your Mac.

## Data Collection

### What LocalFlow Does NOT Collect

- **Audio recordings** — Not stored, not transmitted
- **Transcribed text** — Stays on your device
- **Personal information** — No accounts, no sign-ups
- **Usage analytics** — No telemetry, no tracking
- **Crash reports** — Not automatically sent

### What LocalFlow Stores Locally

The following data is stored **only on your Mac**:

| Data | Location | Purpose |
|------|----------|---------|
| Settings | UserDefaults | Your preferences |
| Transcription history | UserDefaults | Recent transcriptions (last 50) |
| Speech models | ~/Library/Application Support/LocalFlow/Models/ | Offline speech recognition |

## Network Requests

LocalFlow makes network requests only for:

1. **Model downloads** — Fetched from Hugging Face (`huggingface.co`) when you download a new model
2. **Update checks** — Fetches `appcast.xml` from GitHub to check for app updates

No audio, text, or personal data is ever transmitted.

## Third-Party Services

### Hugging Face
Models are downloaded from Hugging Face's model repository. LocalFlow does not authenticate with Hugging Face or share any data with them. [Hugging Face Privacy Policy](https://huggingface.co/privacy)

### GitHub
Update checks fetch a small XML file from GitHub. No user data is transmitted. [GitHub Privacy Policy](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement)

### Sparkle (Update Framework)
LocalFlow uses Sparkle for updates. Sparkle only fetches the appcast URL configured in the app. [Sparkle Documentation](https://sparkle-project.org/)

## Permissions

LocalFlow requires these macOS permissions:

| Permission | Why |
|------------|-----|
| **Microphone** | To record your voice for transcription |
| **Accessibility** | To detect hotkeys and insert text into other apps |

These permissions are used only for their stated purposes.

## Open Source

LocalFlow is open source. You can audit the code yourself:
[github.com/laurenschristian/local-flow](https://github.com/laurenschristian/local-flow)

## Data Deletion

To remove all LocalFlow data from your Mac:

```bash
# Remove the app
rm -rf /Applications/LocalFlow.app

# Remove settings and history
defaults delete com.localflow.app

# Remove models
rm -rf ~/Library/Application\ Support/LocalFlow

# Remove cache
rm -rf ~/Library/Caches/com.localflow.app
```

## Contact

For privacy concerns, open an issue on [GitHub](https://github.com/laurenschristian/local-flow/issues).

---

**LocalFlow does not sell, share, or monetize your data in any way.**

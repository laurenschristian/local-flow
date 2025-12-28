# Troubleshooting Guide

## Common Issues

### "Microphone access required"

**Cause:** LocalFlow doesn't have permission to access your microphone.

**Fix:**
1. Open System Settings → Privacy & Security → Microphone
2. Find LocalFlow in the list
3. Toggle it ON
4. Restart LocalFlow

---

### "Accessibility access required"

**Cause:** LocalFlow can't detect your hotkey or insert text without accessibility access.

**Fix:**
1. Open System Settings → Privacy & Security → Accessibility
2. Click the + button
3. Navigate to Applications → LocalFlow.app
4. Toggle it ON
5. Restart LocalFlow

---

### "Failed to load speech model"

**Cause:** The downloaded model file may be corrupted or incomplete.

**Fix:**
1. Open Settings → Model
2. Delete the problematic model (if possible) or locate it in:
   `~/Library/Application Support/LocalFlow/Models/`
3. Re-download the model

---

### "No audio detected"

**Cause:** Recording was too short or microphone isn't picking up sound.

**Fix:**
- Make sure you're **holding** the trigger key while speaking
- Check that your microphone is working (test in another app)
- Speak louder or move closer to the microphone
- Check System Settings → Sound → Input to verify the correct mic is selected

---

### Hotkey not working

**Cause:** Accessibility permission not granted, or another app is intercepting the key.

**Fix:**
1. Verify accessibility permission is granted (see above)
2. Try a different trigger key in Settings → Hotkey
3. Check if another app (like Karabiner, BetterTouchTool) is using the same key
4. Restart LocalFlow

---

### Text not inserting into apps

**Cause:** Some apps don't accept simulated paste commands.

**Fix:**
1. Enable "Clipboard mode" in Settings → General
2. Manually paste (Cmd+V) after transcription
3. Some apps (like certain terminal emulators) may require special handling

---

### Permissions reset after update

**Cause:** macOS ties permissions to an app's code signature. Updates can change this signature.

**Fix:**
1. When LocalFlow detects missing permissions after an update, the setup wizard will appear
2. Follow the steps to re-grant Accessibility and Microphone access
3. This is a one-time process per update

---

### App shows "LocalFlow.app is damaged"

**Cause:** macOS Gatekeeper blocking unsigned app.

**Fix:**
1. Right-click (or Control-click) LocalFlow.app
2. Select "Open" from the context menu
3. Click "Open" in the dialog
4. This only needs to be done once

---

### Slow transcription

**Cause:** Using a larger model than your Mac can handle efficiently.

**Fix:**
- Try a smaller model (Tiny or Base) for faster results
- Close other resource-intensive apps
- Ensure your Mac isn't in low-power mode

---

### Model download fails

**Cause:** Network issues or Hugging Face servers temporarily unavailable.

**Fix:**
1. Check your internet connection
2. Try again in a few minutes
3. If behind a corporate firewall, models are downloaded from:
   `https://huggingface.co/ggerganov/whisper.cpp/`

---

## Still having issues?

1. Quit LocalFlow completely (Menu bar → Quit)
2. Restart your Mac
3. Open LocalFlow again

If problems persist, [open an issue on GitHub](https://github.com/laurenschristian/local-flow/issues) with:
- Your macOS version
- Mac model (M1, M2, etc.)
- What you expected vs. what happened
- Any error messages shown

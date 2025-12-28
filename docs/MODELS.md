# Model Comparison Guide

LocalFlow uses OpenAI's Whisper models for speech recognition. All processing happens locally on your Mac.

## Available Models

| Model | Size | Speed | Accuracy | Best For |
|-------|------|-------|----------|----------|
| **Tiny** | 75 MB | ~0.5s | Basic | Quick notes, simple dictation |
| **Base** | 142 MB | ~1s | Good | General use, everyday dictation |
| **Small** | 466 MB | ~2s | Better | Professional use, complex vocabulary |
| **Medium** | 1.5 GB | ~4s | Best | Maximum accuracy, technical terms |

*Speed estimates are for ~10 seconds of audio on Apple M1.*

## Detailed Comparison

### Tiny (75 MB)
- **Pros:** Fastest transcription, minimal storage
- **Cons:** More errors, struggles with accents
- **Use when:** You need instant results and can tolerate occasional mistakes
- **RAM usage:** ~400 MB

### Base (142 MB) — *Default*
- **Pros:** Good balance of speed and accuracy, quick download
- **Cons:** May miss complex words
- **Use when:** Starting out, general dictation, casual use
- **RAM usage:** ~500 MB

### Small (466 MB) — *Recommended*
- **Pros:** Significantly better accuracy, handles accents well
- **Cons:** Slower than Base, larger download
- **Use when:** You want reliable transcription for important work
- **RAM usage:** ~1 GB

### Medium (1.5 GB)
- **Pros:** Best accuracy, handles technical vocabulary
- **Cons:** Slowest, large download, high memory usage
- **Use when:** Maximum accuracy is critical, technical/medical/legal terms
- **RAM usage:** ~2.5 GB

## Recommendations

**For most users:** Start with **Base**, upgrade to **Small** if you find accuracy lacking.

**For professionals:** Use **Small** for the best balance, or **Medium** if you regularly use specialized terminology.

**For older Macs (8GB RAM):** Stick with **Tiny** or **Base** to avoid memory pressure.

## Language Support

All models are English-only (`.en` variants). They're optimized for English and provide better accuracy than multilingual models for English speech.

## Switching Models

1. Open LocalFlow settings (menu bar → Settings)
2. Go to the **Model** tab
3. Download your preferred model
4. Select it from the dropdown

The new model will be used for the next transcription. Previously downloaded models remain available.

## Technical Details

LocalFlow uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp), a C++ port of OpenAI's Whisper optimized for Apple Silicon. Models run with Metal GPU acceleration for fast inference.

Models are stored in:
```
~/Library/Application Support/LocalFlow/Models/
```

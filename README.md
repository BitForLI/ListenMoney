# Listen

Listen is a focused bilingual podcast player. The MVP supports up to ten
podcast subscriptions, sentence/paragraph/episode repetition, bilingual
transcripts, and daily listening streaks.

## Repository layout

- `lib/`: Flutter application for iOS and Android.
- `backend/`: FastAPI service for feed synchronization and transcript jobs.
- `test/`: Flutter widget tests.
- `backend/tests/`: backend tests.

## Current milestone

RSS subscriptions, playback, and timed transcripts are implemented end to end.
The app supports Apple Podcasts search, direct RSS entry, a ten-subscription
limit, duplicate-safe refresh, streaming playback, speed and seek controls,
episode/sentence/paragraph repetition, Podcasting 2.0 transcript imports, and
an optional local Whisper fallback, publisher-provided Chinese tracks, and
cached machine translation through an OpenAI-compatible local service. Actual
ready-state playback time is aggregated by local calendar day, with a monthly
heatmap, total duration, and current listening streak.

Android offline ASR uses a single quantized NVIDIA Parakeet TDT 0.6B v2 English
model. It combines a continuous Silero neural VAD, token timestamps plus pauses
for sentence boundaries, and retries low-quality long windows. Versioned ASR
caches are reusable and can be regenerated from the transcript screen.

The add-subscription sheet includes one-tap entries for Practical AI, The TED
AI Show, and Latent Space. Episodes without an RSS timed transcript can be
transcribed locally on a supported Android phone.

## Local checks

Install and test the backend once:

```bash
cd /Users/x/Desktop/listen/backend
source .venv/bin/activate
python -m pip install -e '.[dev]'
python -m pytest
```

Start the backend (leave this terminal running):

```bash
cd /Users/x/Desktop/listen/backend
source .venv/bin/activate
python -m uvicorn app.main:app --reload
```

Then start the iOS app from a second terminal:

```bash
cd /Users/x/Desktop/listen
/Users/x/develop/flutter/bin/flutter run \
  --dart-define=LISTEN_API_BASE_URL=http://127.0.0.1:8000
```

For the Android emulator, use `http://10.0.2.2:8000` as the API base URL.
For a physical Android phone on the same Wi-Fi network as the Mac, use the
Mac's LAN address, for example `http://192.168.1.20:8000`. The backend must be
started with `--host 0.0.0.0` for the phone to reach it.

Run local Flutter checks with:

```bash
/Users/x/develop/flutter/bin/flutter analyze
/Users/x/develop/flutter/bin/flutter test
```

The backend is intended for local MVP use. Do not expose it publicly without
authentication and network-request restrictions.

## Optional local transcription

Episodes that publish Podcasting 2.0 VTT, SRT, or JSON transcripts work without
extra dependencies. To generate a transcript for an episode that does not
publish one, install the local transcription extra:

```bash
cd /Users/x/Desktop/listen/backend
source .venv/bin/activate
python -m pip install -e '.[dev,transcription]'
```

The first transcription downloads the Whisper `small` model. Set
`LISTEN_WHISPER_MODEL` before starting the backend to choose another compatible
model.

### Free Android on-device transcription

On Android, the text page can generate English timed captions directly on the
phone without installing `faster-whisper` on the Mac. Listen always uses the
quantized Parakeet TDT English model (about 661 MB) to prioritize recognition
quality and precise timestamps; there is no lower-quality model selector. The
sherpa-onnx Parakeet model and the small Silero VAD model are downloaded on
first use, then reused offline. Legacy Whisper models are removed automatically.
Episode audio is decoded into 30-second chunks while VAD state remains
continuous across chunk boundaries; completed captions appear progressively
and are kept in the app's private storage.

After the subscription library loads or refreshes, Listen merges all episodes,
sorts them by publication date, and serially prepares English captions for the
latest five. Episodes with an existing RSS transcript or phone cache are
skipped, and foreground transcription shares the same queue so only one model
job runs at a time.

When the local FastAPI backend is reachable, the phone also syncs the generated
timeline to it so the existing Chinese translation flow can use it. If the Mac
is unavailable, English captions remain usable from the phone cache and can be
synced later by tapping the translate action after reconnecting.

## Local Chinese translation

If a publisher supplies Chinese timed captions, Listen uses them directly.
Otherwise the backend defaults to Ollama's OpenAI-compatible endpoint and the
`qwen3:4b` model:

```bash
brew install ollama
brew services start ollama
ollama pull qwen3:4b
```

To use another OpenAI-compatible service, set these variables before starting
the backend:

```bash
export LISTEN_TRANSLATION_BASE_URL=http://127.0.0.1:11434/v1
export LISTEN_TRANSLATION_MODEL=qwen3:4b
export LISTEN_TRANSLATION_API_KEY=ollama
```

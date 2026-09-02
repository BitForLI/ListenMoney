# Listen

Listen is a local-first bilingual podcast player for Android and iOS. The app
supports up to ten RSS subscriptions, sentence/paragraph/episode repetition,
on-device English transcription, English–Chinese translation, and monthly
listening statistics.

## Phone-first architecture

The released app does not need FastAPI, Cloudflare, a Mac, USB debugging, or
`adb reverse` during normal use.

- RSS subscriptions and episode updates are fetched directly by the phone.
- Podcasts, transcripts, translations, and listening history are stored in the
  app's private local data directory.
- The last episode, playback position, and speed are restored after reopening.
- Apple Podcasts search is called directly from the phone.
- NVIDIA Parakeet transcription runs on supported Android devices.
- Google ML Kit translation models are downloaded once, then run on device.
- Podcasting 2.0 VTT, SRT, and JSON transcripts are imported directly from RSS.

Sentence/paragraph repetition and all seek controls share the full episode's
timeline; changing sentences does not reload a clipped audio source. New phone
transcripts retain their original compressed audio in private app storage and
play from that exact recording (including when offline), so separate network
requests cannot change the audio underneath a saved transcript. This uses extra
storage roughly equal to each transcribed episode's download size. Existing
transcripts remain readable but unbound/older timelines no longer drive
highlighting, auto-scroll or sentence jumps. Opening captions requests a new
aligned transcript; the newest-five background queue also refreshes old
unbound transcripts. Generation v6 uses native token timestamps only and leaves
unaligned regions as gaps instead of estimating timing from text length. During
seeking/buffering captions wait for the player to confirm its position. These
checks do not guarantee that every recognized word is correct.

The previous FastAPI implementation remains in `backend/` as a tested reference
service, but the Flutter app has no runtime dependency on it.

## Run

```bash
cd /Users/x/Desktop/listen
/Users/x/develop/flutter/bin/flutter pub get
/Users/x/develop/flutter/bin/flutter run -d R5GL32WY17H
```

No API base URL is required.

## Verify

```bash
/Users/x/develop/flutter/bin/flutter analyze
/Users/x/develop/flutter/bin/flutter test
cd backend && .venv/bin/python -m pytest tests -q
```

## Android release

```bash
/Users/x/develop/flutter/bin/flutter build apk --release
```

The Android application id is `com.listenapp.listen`. Version `1.0.4+5` can be
installed over earlier test builds.

# Listen

Listen is a local-first podcast player for people learning English. It combines ordinary RSS playback with repeat controls, time-aligned transcripts, English-to-Chinese translation, and listening statistics.

## Highlights

- Subscribe to up to ten RSS feeds and search Apple Podcasts.
- Repeat a sentence, paragraph, or whole episode without switching audio sources.
- Generate English transcripts on supported Android devices with NVIDIA Parakeet.
- Translate transcripts on-device with Google ML Kit.
- Import Podcasting 2.0 transcripts in VTT, SRT, or JSON format.
- Restore the last episode, playback position, and speed after restarting.
- Keep podcasts, transcripts, translations, and history in the app's private storage.

The mobile app talks directly to RSS and podcast services. The older FastAPI implementation remains under `backend/` as a tested reference, but it is not required at runtime.

## Run

```bash
flutter pub get
flutter run
```

No API base URL is required.

## Verify

```bash
flutter analyze
flutter test
cd backend
python -m pytest tests -q
```

## Build for Android

```bash
flutter build apk --release
```

The Android application ID is `com.listenapp.listen`.

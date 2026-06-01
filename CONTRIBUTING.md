# Contributing

Detto is a solo project. Pull requests are welcome, but review bandwidth is limited, so smaller, focused changes are easier to merge.

## Bug Reports

Open an issue with:
- What you expected vs. what happened
- macOS version, Mac model
- Steps to reproduce

## Feature Requests

Open an issue first to discuss before building. This saves you from writing code that doesn't fit the project direction.

## Pull Requests

- One change per PR. Don't bundle unrelated fixes.
- Include a brief test plan (what you tested, how).
- Match existing code style: Swift 6 concurrency patterns, no force-unwraps, minimal comments.
- Make sure the app builds: `./scripts/build_swift_app.sh`

## Architecture Note

The ASR engine, VAD, and diarization live in a separate package: [GrembleVoice](https://github.com/Gremble-io/gremble-voice). If your change is about transcription accuracy, model loading, or audio processing, it probably belongs there.

## License

By contributing, you agree that your contributions will be licensed under the [Business Source License 1.1](LICENSE).

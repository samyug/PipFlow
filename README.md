# PipFlow

**PipFlow 1.2** runs IBM Granite Speech 5.0 470M TurboCTC locally. PipFlow bundles the 506 MB Q8_0 model, shows a rolling draft while you speak, and finalizes it using the full recording. The compact bars in the bottom bar react to microphone frequencies and volume during dictation.

## Dictation

- **In Studio**, click **Start**, grant microphone access, speak, then click Finish recording. Read the result in the main pane or select a saved transcript from the left sidebar.
- **In another app**, place the cursor in a text field and hold Control–Option–Space. Release to finalize and insert the transcript. The floating panel shows the microphone level and live draft. Use its checkmark to finish or × to discard the take.
- **Settings** controls cross-app dictation and its recording shortcut.
- **Hands-free**, press your dictation shortcut (initially Control–Option–Shift–Space for new installs) to start and again to finish.
- Enable PipFlow in **System Settings → Privacy & Security → Accessibility** for direct insertion. If Accessibility is off, PipFlow copies the text and the panel prompts you to press Command–V. With access enabled, apps that require a paste receive the transcript via the clipboard. If focus moves to a different app, or PipFlow detects that the text field changed, PipFlow keeps the result under Transcripts.
- **Dictionary** maps recognized phrases to preferred spellings or expanded snippets. **Settings** controls lightweight filler removal. The **Transcripts** sidebar supports search, copy and individual deletion.
- Closing the window leaves PipFlow available in the menu bar. Choose Quit PipFlow to exit.

## Spoken formatting

PipFlow 1.2 supports local formatting. Say “Bullet point, review the draft. Next bullet, send feedback,” or enumerate steps with “first … second … third.” For an explicit request, try “Make a numbered list: apples, oats, and milk.” Say “new paragraph” or “end list” to resume prose. Settings includes examples and a switch for spoken formatting. The transcript pane, saved notes, copy and insertion preserve the resulting line breaks and list markers.

## Local data

PipFlow stores transcripts and dictionary entries in the current user's Application Support/Murmur/library.json. PipFlow keeps its temporary WAV and decoder output in a private directory that it removes after transcription, cancellation, or normal quit. A forced quit or crash can leave files in the current user’s temporary directory.

## Build

To build for your Mac's native architecture, install CMake and the Xcode Command Line Tools and run `./build.sh` from this folder. The script verifies the model and engine archive checksums, compiles the Swift interface, and signs the app locally. Set PIP_SIGNING_IDENTITY to the same Apple code-signing identity for each release so macOS can recognize updates for microphone permission. Without it the build uses ad-hoc signing. The deployment target is macOS 13.4.

The recording and global shortcut behavior uses public macOS APIs and Wispr Flow's publicly documented interaction pattern. PipFlow 1.2 uses the [IBM model](https://huggingface.co/ibm-granite/granite-speech-5.0-470m-turboctc) with the [community Q8 conversion](https://huggingface.co/vladers/granite-speech-5.0-470m-turboctc-GGUF) and [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp). The licenses ship inside the app.

See [Releasing PipFlow](RELEASE.md) for downloadable app packaging, GitHub release automation, and signing instructions.

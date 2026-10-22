# Call recording and transcripts

Records a call on the Mac, finds its event in Calendar, and turns it into a
transcript on this machine. Nothing leaves the Mac until the transcript is
handed to Claude to file in the brain, and that step asks first. macOS only.

## Use

    make record-init        # once per Mac: OBS, whisper.cpp and its models, the diarizer
    make record             # records until Ctrl+C, then names and saves it
    make record-stop        # finishes a recording whose terminal was closed
    make record-transcribe  # picks a recording, writes its transcript, offers the brain step

`record` asks audio or video, Enter = audio. Ctrl+C stops it. If Calendar has an
event at that time, Enter takes its title as the name; with two events at once
it asks which. `record-transcribe` asks quick or precise, transcribes, then asks
whether to file the call in the brain.

| Variable | For |
|----------|-----|
| `MODE=video` | `record` without the audio-or-video question |
| `NAME=…` | `record-stop` without the name question |
| `FILE=…` | `record-transcribe` on this file instead of picking one |
| `MODEL=quick\|precise` | skips the question; precise is better at Czech, about 3× slower |
| `SPOKEN=cs` | the language, instead of guessing it per track |
| `ICS=event.ics` | an event for a recording that has none saved (an `ical://` link works too) |
| `SPEAKERS=3` | how many voices are on the other side, when the event's people would mislead |
| `BRAIN=n` | skips the brain step |

## What it writes

Each call gets a folder of its own in `~/Recordings` (`RECORDINGS_DIR` moves
it), and every file in it is still named after the call, so a copy taken
elsewhere still says which call it is. A second call with the same name gets a
`-2` folder.

| File in `20261021-weekly-sync/` | What |
|------|------|
| `20261021-weekly-sync.m4a` | the call: track 1 both sides mixed, 2 the call, 3 my mic (`.mp4` for video) |
| `20261021-weekly-sync.event.json` | the Calendar event as it was when the call ended: title, times, me, the others |
| `20261021-weekly-sync.txt` | the transcript; a second run writes `-2.txt` and never overwrites one |

`record-init` moves calls saved before this, loose in `~/Recordings`, into
folders. Running it again changes nothing, and it never moves a file over
another one.

The transcript opens with `#` lines saying what is known before reading: the
event, who else was on it, and each voice heard on the call track with how long
it spoke. The lines say `Me`, and `Them 1`, `Them 2`… for the other side,
numbered by who spoke first. No names go on the lines: who is who is decided
once the whole call has been read, so an early guess cannot steer the rest.

## What it uses

| Part | What it does | Where it lives |
|------|--------------|----------------|
| [OBS](https://obsproject.com/) | records what the Mac plays and the mic on separate tracks, driven over its websocket ([`record.ts`](record.ts)); profiles and scenes in [`config/`](config) | Brewfile cask |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | speech to text, each track on its own ([`transcribe.ts`](transcribe.ts)) | Brewfile; models in `~/.cache/whisper` |
| `ggml-large-v3-turbo.bin` | the quick model, 1.5 GB | `~/.cache/whisper` |
| `ggml-large-v3.bin` | the precise model, 2.9 GB | `~/.cache/whisper` |
| `ggml-silero-v6.2.0.bin` | skips silence, which whisper otherwise fills with made-up sentences | `~/.cache/whisper` |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) 0.17.7 | tells the voices on the call track apart (pyannote Community-1 on CoreML) | built by `record-init` into `~/.cache/fluidaudio`, 22 MB |
| its diarizer models | 22 MB, 21 files | `~/Library/Application Support/FluidAudio/Models/speaker-diarization` |
| Calendar | the event during the call, and who was on it ([`apple-calendar.ts`](apple-calendar.ts)) | read-only from its database |
| Contacts | a name for an attendee known only by address ([`contacts.ts`](contacts.ts)) | read-only; a new name is saved through the Contacts app, when confirmed |
| [Claude Code](https://claude.com/claude-code) | files the call in the brain, interactively, in `~/projects/landsman/brain` | asked after each transcript |

Every model is pinned by sha256 and checked before it is used. The diarizer has
no release binary, so it is built with Xcode from the commit behind its tag, and
refused if the tag moved. That commit pins its own model revision. If Calendar,
Contacts or the diarizer is not available, the transcript is still written,
just without names or with one `Them`.

## Removing it

    rm -rf ~/.cache/whisper ~/.cache/fluidaudio \
      "$HOME/Library/Application Support/FluidAudio/Models/speaker-diarization"

The other folders under `FluidAudio/Models` belong to other apps that use the
same library. OBS and whisper.cpp go with the Brewfile.

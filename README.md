# zspeech-paul

Generate WAV audio from NeoSpeech VoiceText's "Paul" voice in a Linux
container. Headless — no GUI, no display, no SAPI5 needed at runtime.

## Background

### NeoSpeech VoiceText

NeoSpeech, Inc. (Fremont, CA) was the US subsidiary of Korean company
Voiceware Co., Ltd. (founded 2000; VoiceText engine first shipped 2001).
VoiceText used Unit Selection Synthesis — stitching speech together from
large databases of pre-recorded segments rather than generating it
neurally, which is why the engine's API centers on a `db_path` install
directory (see `CLAUDE.md`). Pentax acquired Voiceware in Jan 2006.
Following ReadSpeaker's 2017 acquisition by HOYA, HOYA folded
Voiceware/NeoSpeech/VoiceText into the unified ReadSpeaker brand and
retired the NeoSpeech name — see
[Wikipedia: NeoSpeech](https://en.wikipedia.org/wiki/NeoSpeech). That's
why this repo has to reverse-engineer the engine (`CLAUDE.md`) instead of
just contacting the vendor: there's no vendor left.

### "New Paul": NWS and EAS

This isn't just some voice — `VT-Paul-M16` is the exact engine NWS's
Broadcast Message Handler (BMH) system adopted as the primary NOAA
Weather Radio (NWR) voice when it finished replacing the aging
DECtalk-based Console Replacement System by the end of 2016, per
[weather.gov/nwr/automatevoice](https://www.weather.gov/nwr/automatevoice):
"BMH has replaced 'Donna' and 'Tom' with an improved 'Paul' voice." It's
relayed for most EAS alerts distributed through NWR. The weather-radio
and EAS hobbyist community calls this voice **"New Paul,"** to
distinguish it from the original DECtalk-era "Old Paul" nickname.

## Requirements

You need your own legally-obtained copy of the `VT-Paul-M16` installer
(InstallShield package). It is **not included in this repo** — it's
proprietary NeoSpeech/VoiceWare software, licensed as a runtime engine
that (per its own EULA) prohibits redistributing generated audio output
without a separate agreement. Place these files in the repo root before
building:

```
setup.exe  ISSetup.dll  layout.bin  setup.ini  setup.inx
data1.cab  data1.hdr  data2.cab
0x0409.ini  0x0411.ini  0x0412.ini  setup.bmp
```

(`.gitignore` already excludes these — don't commit them.)

Build needs `linux/amd64`. On Apple Silicon, enable Docker Desktop's
"Use Rosetta for x86/amd64 emulation" (Settings → General) first — plain
QEMU emulation is dramatically slower for this build's dpkg-heavy Debian
package installs.

## Build

```bash
docker build --platform linux/amd64 -t zspeech-paul .
```

This runs a one-time automated InstallShield install (via Xvfb + fluxbox +
xdotool) inside the build, so it takes a while (large voice database
copy). No interaction needed.

## Use

One-liner: synthesizes and exits, no daemon/exec/cp dance needed.

```bash
docker run --rm --platform linux/amd64 -v "$PWD:/output" zspeech-paul synth "Text to speak" /output/out.wav
```

Output: 16-bit PCM WAV, mono, 16kHz, written to `./out.wav` on the host.

Text can include [VTML](CLAUDE.md#vtml--pronunciation-control) tags for
phoneme overrides, pauses, and prosody, e.g.:

```bash
docker run --rm --platform linux/amd64 -v "$PWD:/output" zspeech-paul synth \
  '<vtml_phoneme alphabet="x-cmu" ph="T AH0 K EY1 M AH">Tekamah</vtml_phoneme><vtml_pause time="500"/>testing' \
  /output/out.wav
```

### Or with Compose

```bash
docker compose up
```

Edit the text and output filename directly in `docker-compose.yml`'s
`command:` line. Output lands in `./output/`.

## How it works

See `CLAUDE.md` for the full technical writeup — what `vt_eng.dll`
actually is, why Wine is unavoidable, how the undocumented C API was
recovered, and Wine-specific gotchas hit along the way.

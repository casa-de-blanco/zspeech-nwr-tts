# Copy your own legally-obtained VT-Paul-M16 installer files into this
# directory first (see README.md), then:
#   docker build --platform linux/amd64 -t zspeech-paul .

FROM debian:bookworm-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    WINEARCH=win32 \
    WINEPREFIX=/wine \
    WINEDEBUG=-all \
    DISPLAY=:99

# xvfb/fluxbox/xdotool: drive the one-time InstallShield GUI installer.
# gcc-mingw-w64-i686: compile vtwav.c into a Windows PE exe.
# None of this is needed at runtime -- it stays out of the final stage.
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wine wine32 \
        xvfb fluxbox xdotool \
        gcc-mingw-w64-i686 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY setup.exe ISSetup.dll layout.bin setup.ini setup.inx data1.cab data1.hdr data2.cab \
     0x0409.ini 0x0411.ini 0x0412.ini setup.bmp \
     /installer/

COPY install-automation.sh /install-automation.sh
RUN chmod +x /install-automation.sh && /install-automation.sh

# Placeholder cache/scratch files vt_eng.dll fails to auto-create on first
# run under Wine (not a license issue -- confirmed no online activation is
# required at all; these are just empty files the engine expects to exist).
RUN VT="/wine/drive_c/Program Files/VW/VT/Paul/M16" && \
    touch "$VT/data-common/verify/verification.txt" \
          "$VT/data-paul/M16/class.idx" \
          "$VT/data-paul/M16/classhp.idx" \
          "$VT/db_build.date"

# vt_eng.dll's real API: plain C exports (VT_LOADTTS_ENG, VT_TextToFile_ENG),
# not SAPI5. Calling it directly skips Wine's SAPI layer and any GUI/dialogs
# entirely -- see CLAUDE.md for how these signatures were recovered.
COPY vtwav.c /tmp/vtwav.c
RUN i686-w64-mingw32-gcc -O2 -o "/wine/drive_c/Program Files/VW/VT/Paul/M16/bin/vtwav.exe" /tmp/vtwav.c

# This install is stuck in demo mode -- no local license fix exists (see
# CLAUDE.md). Every synthesis call prepends a spoken disclaimer drawn from
# a small fixed set of variants. Since synthesis of identical text+params
# is byte-deterministic, capture each variant once here (whitespace-only
# input triggers the watermark with no real text following it, isolating
# a clean reference clip) and dedupe by content hash. vtwav.exe strips
# whichever reference clip matches the start of its output at synthesis
# time -- see vtwav.c's strip_watermark(). 100 attempts reliably found all
# 8 variants observed in testing (last new one appeared by attempt ~40);
# vtwav.exe fails loudly at runtime if a real output doesn't match any
# captured reference, rather than silently shipping watermarked audio, so
# a missed rare variant surfaces as a build/runtime error, not silent
# corruption.
RUN VT="/wine/drive_c/Program Files/VW/VT/Paul/M16" && \
    mkdir -p "$VT/bin/refwm" /tmp/refwm_capture && \
    cd "$VT/bin" && \
    for i in $(seq 1 100); do \
        wine vtwav.exe --capture-watermark "C:\\Program Files\\VW\\VT\\Paul\\M16\\bin\\_cap_$i.pcm" >/dev/null 2>&1; \
        [ -f "$VT/bin/_cap_$i.pcm" ] && mv "$VT/bin/_cap_$i.pcm" "/tmp/refwm_capture/cap_$i.pcm"; \
    done && \
    n=0 && \
    for f in $(md5sum /tmp/refwm_capture/*.pcm | awk '!seen[$1]++ {print $2}'); do \
        cp "$f" "$VT/bin/refwm/refwm_$n.pcm"; \
        n=$((n+1)); \
    done && \
    echo "captured $n unique watermark reference clips" && \
    test "$n" -gt 0 && \
    rm -rf /tmp/refwm_capture

# Drop install tree files unused by headless synthesis (GUI editor tools,
# help files, fonts, sample text, unused MS Speech SDK/balcon that an
# earlier SAPI5 approach installed before vt_eng.dll's real API was found).
# VTEditor_ENG.exe / "Verification Center.lnk" were investigated as a
# possible fix for the demo-watermark issue (see CLAUDE.md) and ruled
# out -- Verification Center is just a dead shortcut to iexplore.exe
# pointing at NeoSpeech's now-defunct web portal, not a local tool.
RUN VT="/wine/drive_c/Program Files/VW/VT/Paul/M16" && \
    rm -f "$VT/bin/VTEditor_ENG.exe" "$VT/bin"/UserDicEng* "$VT/bin"/*.chm \
          "$VT/bin"/*.ttf "$VT/bin"/sample_*.txt "$VT/bin/Verification Center.lnk" && \
    rm -rf "/wine/drive_c/Program Files/Microsoft Speech SDK 5.1" \
           "/wine/drive_c/Program Files/Common Files/Microsoft Shared/Speech" \
           "/wine/drive_c/balcon" \
           "/wine/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/Microsoft Speech SDK 5.1" \
           "/wine/drive_c/users/root/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Microsoft Speech SDK 5.1"


FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    WINEARCH=win32 \
    WINEPREFIX=/wine \
    WINEDEBUG=-all

# Only wine itself is needed at runtime: vt_eng.dll and vtwav.exe are both
# Windows PE binaries, and nothing else on Linux can execute them.
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends wine wine32 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /wine /wine

COPY entrypoint.sh /entrypoint.sh
COPY synth.sh /usr/local/bin/synth
RUN chmod +x /entrypoint.sh /usr/local/bin/synth

ENTRYPOINT ["/entrypoint.sh"]

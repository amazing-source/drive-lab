Evidence for #107: the DR458's start-up from Creator Store asset 126032464409866.

All reads were taken in Studio edit mode on 2026-10-30, through the owner's session, with audio
instances parented under a temporary SoundService folder (deleted after) and nothing wired to an
output, so nothing was audible. The PC's volume was not touched.

Length: Sound.TimeLength and AudioPlayer.TimeLength both 3.9230839 s (173,008 samples at 44.1 kHz).

store_envelope.txt  AudioAnalyzer RmsLevel and PeakLevel per 1,024-sample buffer (21.3 ms), with
                    the spectrum's power unweighted and K-weighted (BS.1770 filters applied per
                    bin to the 2,048-bin spectrum). Two playbacks gave identical RmsLevel series.
idle level          The game's mix at 1,000 rpm off throttle, computed with EngineSound.target on
                    the DR458 pack: the Idle loop (76328100926971) at volume 0.250816 and speed
                    1.251564, Off2000 (138317459424823) at 0.006524 and 0.493583. Played the same
                    way for 6 s (283 buffers): RMS 0.012265 (-38.23 dBFS); spectrum -37.23 dB
                    unweighted, -37.01 dB K-weighted.
levels.txt          The store sound's level against that idle per window, its 100 ms envelope,
                    and the hand-over windows scored (handover.py, windows.py).
pitch.txt           Engine order read by autocorrelation, and the rpm the start-up curve uses.
mutations.txt       Each new rule broken on purpose and the spec that failed.

# Permission and latency investigation — September 8, 2026

## Capturely

The previous build selected an Apple Development identity even though the existing Screen Recording approval was bound to the “Capturely Local Development” certificate.

The build script now defaults explicitly to that local identity and no longer searches for an alternative certificate automatically. The Release app was rebuilt and signature-verified. A codesign requirement check against the certificate requirement stored in the original permission now passes.

The user approved the macOS authentication prompt. After relaunch, Capturely reports Screen Recording as Ready. A live desktop recording ran for approximately 97 seconds with 5,508 encoded frames and zero encoder backpressure drops. A saved replay exported in 245.5 ms through the FFmpeg audio-only path.

The saved file is 56.634 seconds of HEVC video at 1800×1168 with 48 kHz stereo AAC audio. Full-file decoding completed successfully with no errors. This verifies desktop recording and export; Roblox was not running, and microphone capture was off, so gameplay performance and microphone synchronization were not verified.

## Network findings

The Mac uses Wi-Fi through gateway 192.168.1.254. A fresh 45-second simultaneous test, with Roblox closed and Capturely not recording, returned:

| Destination | Samples | Median | 95th percentile | Maximum | Loss |
| --- | ---: | ---: | ---: | ---: | ---: |
| Local router | 90 | 8.549 ms | 92.401 ms | 326.833 ms | 0% |
| Cloudflare | 90 | 10.204 ms | 96.526 ms | 336.012 ms | 0% |
| Google | 90 | 13.659 ms | 99.011 ms | 840.423 ms | 0% |

Router and public-endpoint spikes occurred on matching probe sequences. For example, sequence 67 measured 326.833 ms to the router, 332.813 ms to Cloudflare, and 338.201 ms to Google. This strongly localizes a substantial part of the jitter to the Mac/Wi-Fi/router path, rather than requiring a Roblox server or recording workload.

Low Power Mode is enabled. The Wi-Fi daemon also logged Location Services live scans lasting approximately 400 ms. However, a separate 45-second router test still reached 240.618 ms with no matching live-scan events, so scans alone do not explain the problem and have not been established as the cause.

Earlier signal inspection showed 5 GHz / 80 MHz / 802.11ax at -57 dBm signal and -90 dBm noise. A short per-process transfer sample did not show a large background transfer. These are snapshots, not proof that interference or congestion never occurs.

## Follow-up with Low Power Mode off

The user has no Ethernet option. At the next test, Low Power Mode was already off, so no power setting needed changing. With Capturely idle, 90 probes over 45 seconds showed:

| Destination | Median | 95th percentile | Maximum | Loss |
| --- | ---: | ---: | ---: | ---: |
| Local router | 8.672 ms | 88.816 ms | 95.831 ms | 0% |
| Cloudflare | 9.985 ms | 85.717 ms | 97.274 ms | 0% |

This did not eliminate the recurring local latency spikes. The lower maximum than the earlier sample is not enough to claim a causal improvement: these were observations at different times, not a controlled randomized comparison.

A higher-frequency router probe during desktop capture also retained spikes near 96 ms. High-frequency ICMP responses were incomplete, so that run should not be treated as a measurement of Roblox packet loss.

Further Wi-Fi-only isolation would compare nearer to the router and, with authorization, temporarily disable unused AirDrop/Handoff activity or test another router channel. Neither low signal strength, Location Services scans, nor Low Power Mode has been established as the sole cause. No router, Wi-Fi, Location Services, VPN, or power setting was changed during this investigation.

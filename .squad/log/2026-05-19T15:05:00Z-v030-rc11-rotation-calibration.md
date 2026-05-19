# v0.3.0-rc11: Rotation calibration (rotation=0→4 topLR)

**date:** 2026-05-19  
**campaign:** rc11 HUD rotation calibration  
**artifact:** v0.3.0-rc11 (CURRENT_PROJECT_VERSION=26)

**summary:**  
rc9 failed (blank screen). rc10 bisected: holdFlush confirmed good (no flicker), rotation=0 persists upside-down. rc11 ships rotation=4 (topLR, the only other SDK-documented value). TextFlight: "UPLOAD SUCCEEDED with no errors".

**next milestone:**  
Joe's bench test (2026-05-19T15:05 horizon). Three branches:
1. **Right-side-up** → rotation=4 canonical; calibration done.
2. **Blank** → both documented values fail; escalate to Weiss (SDK/firmware reconciliation).
3. **Upside-down** → rotation byte is a no-op at protocol level; investigate lens-coord vs. firmware-coord inversion.

**outcome_pending:** Joe bench test result (rotation=4 viability).

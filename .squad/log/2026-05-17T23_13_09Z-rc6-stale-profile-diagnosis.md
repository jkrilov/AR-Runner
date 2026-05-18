# Session: rc6-stale-profile-diagnosis (2026-05-17T23:13:09Z)

v0.2.0-rc6 archive fails identically to rc5 despite D-RICHARDS-TF-11 portal capability fix being applied. Diagnosis: `-allowProvisioningUpdates` reuses stale Distribution profiles. iOS targets (com.arrunner.phone, com.arrunner.phone.widgets) had profiles minted rc1–rc5 before App Groups + HealthKit were added; Watch targets had no pre-existing profiles so fresh ones were minted with correct capabilities.

Fix: Joe revokes two iOS Distribution profiles in Apple Developer portal. Richards retags rc7. Expected: archive succeeds.

See D-RICHARDS-TF-12 in decisions.md for full root-cause analysis, trade-offs, and follow-up.

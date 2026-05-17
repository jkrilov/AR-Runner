# Session Log — rc5 Provisioning Entitlements (Portal Action Required)

**Date:** 2026-05-17T21:56:30Z  
**Context:** v0.2.0 release campaign rc5 investigation  
**Status:** PAUSED (awaiting Joe portal action)

## Summary

rc5 archive failed with provisioning-profile capability mismatch. Repo entitlements are correct; issue is App ID capability registration in developer.apple.com. Manual signing workaround in PR #26 confirmed the xcodebuild CLI signing fix works — this error is the next class of issue.

## Action Required

Joe (Account Holder) must enable App Groups and HealthKit capabilities on the portal-registered App IDs:
- `com.arrunner.phone` → App Groups + HealthKit
- `com.arrunner.phone.widgets` → App Groups

No code changes needed.

## Campaign Pause

v0.2.0 release campaign paused. Will resume after Joe confirms portal state and rc6 is tagged and tested.

# VYRO
Free iOS video editor: 22 AE-style effects (Core Image), effect timeline ranges, and a draggable time-remap graph (speed ramps + freeze frames).

## Get an IPA without a Mac
1. Create a GitHub repo and push this folder.
2. Actions tab -> "Build IPA" -> run. Download the `VYRO-ipa` artifact.
3. The IPA is UNSIGNED. Install with AltStore / Sideloadly (free Apple ID) or sign it yourself.

## With a Mac
`brew install xcodegen && xcodegen generate && open VYRO.xcodeproj`

Targets iOS 16+. Change the bundle ID in project.yml.

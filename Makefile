.PHONY: project open build test test-core data clean

project:            ## Generate Anchor.xcodeproj (needs `brew install xcodegen`)
	xcodegen generate

open: project
	open Anchor.xcodeproj

build: project
	xcodebuild -project Anchor.xcodeproj -scheme Anchor -configuration Debug -destination 'platform=macOS' build

test: project       ## App + core tests
	xcodebuild -project Anchor.xcodeproj -scheme Anchor -destination 'platform=macOS' test

test-core:          ## Pure-Swift logic only (also runs on Linux)
	cd AnchorCore && swift test

data:               ## Rebuild bundled Bibles and plans from source downloads (see tools/)
	python3 tools/build_plans.py Anchor/Resources/Bibles/KJV.json Anchor/Resources/Plans

clean:
	rm -rf Anchor.xcodeproj build AnchorCore/.build

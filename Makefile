.PHONY: test build app run xcode clean

test:
	swift test

build:
	swift build

app:
	chmod +x scripts/build-app.sh
	./scripts/build-app.sh release

run: app
	open dist/SpacedOut.app

xcode:
	@command -v xcodegen >/dev/null 2>&1 || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
	xcodegen generate
	open SpacedOut.xcodeproj

clean:
	swift package clean
	rm -rf dist .build

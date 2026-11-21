.PHONY: test build app run xcode clean

test:
	swift test

build:
	swift build

app:
	chmod +x scripts/build-app.sh
	./scripts/build-app.sh release

run: app
	@APP_PATH="$$(pwd -P)/dist/SpacedOut.app"; \
	if ! open "$$APP_PATH"; then \
	  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"; \
	  if [ -x "$$LSREGISTER" ]; then \
	    "$$LSREGISTER" -u "$$APP_PATH" >/dev/null 2>&1 || true; \
	    "$$LSREGISTER" -f "$$APP_PATH" >/dev/null 2>&1 || true; \
	  fi; \
	  sleep 0.3; \
	  open "$$APP_PATH"; \
	fi

xcode:
	@command -v xcodegen >/dev/null 2>&1 || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
	xcodegen generate
	open SpacedOut.xcodeproj

clean:
	swift package clean
	rm -rf dist .build

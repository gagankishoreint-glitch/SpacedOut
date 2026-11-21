.PHONY: test build app dmg run xcode clean

test:
	swift test

build:
	swift build

app:
	chmod +x scripts/build-app.sh
	./scripts/build-app.sh release

dmg:
	chmod +x scripts/build-app.sh scripts/build-dmg.sh
	./scripts/build-dmg.sh release

run: app
	@APP_PATH="$$(pwd -P)/dist/SpacedOut.app"; \
	if ! open "$$APP_PATH"; then \
	  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"; \
	  if [ -x "$$LSREGISTER" ]; then \
	    for stale in "$$HOME/Library/Developer/Xcode/DerivedData"/SpacedOut-*/Build/Products/*/SpacedOut.app; do \
	      [ -e "$$stale" ] && "$$LSREGISTER" -u "$$stale" >/dev/null 2>&1 || true; \
	    done; \
	    "$$LSREGISTER" -u "$$APP_PATH" >/dev/null 2>&1 || true; \
	    "$$LSREGISTER" -f "$$APP_PATH" >/dev/null 2>&1 || true; \
	  fi; \
	  sleep 0.5; \
	  if ! open "$$APP_PATH"; then \
	    echo "==> Bundle diagnostics for $$APP_PATH:"; \
	    ls -la "$$APP_PATH/Contents" "$$APP_PATH/Contents/MacOS" "$$APP_PATH/Contents/Resources" || true; \
	    file "$$APP_PATH/Contents/MacOS/SpacedOut" || true; \
	    codesign -dvvv "$$APP_PATH" 2>&1 || true; \
	    plutil -p "$$APP_PATH/Contents/Info.plist" | grep -E "CFBundle(Executable|Identifier|PackageType|Icon)" || true; \
	    if [ -x "$$LSREGISTER" ]; then "$$LSREGISTER" -dump | grep -B2 -A6 "com.spacedout.app" | head -n 40 || true; fi; \
	    exit 1; \
	  fi; \
	fi

xcode:
	@command -v xcodegen >/dev/null 2>&1 || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
	@if [ -f AppResources/Info.plist ] && { grep -q '\$$(' AppResources/Info.plist || ! grep -q 'LSUIElement' AppResources/Info.plist; }; then \
	  echo "Note: Restoring AppResources/Info.plist from git HEAD before xcodegen..."; \
	  git checkout HEAD -- AppResources/Info.plist || true; \
	fi
	@if [ -f AppResources/SpacedOut.entitlements ] && ! grep -q 'personal-information.calendars' AppResources/SpacedOut.entitlements; then \
	  git checkout HEAD -- AppResources/SpacedOut.entitlements || true; \
	fi
	xcodegen generate
	open SpacedOut.xcodeproj

clean:
	swift package clean
	rm -rf dist .build

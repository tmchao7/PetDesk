SHELL := /bin/zsh

.PHONY: bootstrap setup-git handoff-new handoff-check handoff-test generate build release dmg test lint format verify run run-app clean

bootstrap:
	./scripts/bootstrap.sh

setup-git:
	./scripts/setup-git.sh

handoff-new:
	@test -n "$(AGENT)" || (echo "Usage: make handoff-new AGENT=<agent> TASK=<task-slug>" && exit 1)
	@test -n "$(TASK)" || (echo "Usage: make handoff-new AGENT=<agent> TASK=<task-slug>" && exit 1)
	./scripts/new-agent-handoff.sh "$(AGENT)" "$(TASK)"

handoff-check:
	./scripts/check-agent-handoff.sh

handoff-test:
	zsh scripts/tests/agent-handoff-tests.sh

generate:
	@command -v xcodegen >/dev/null || (echo "Install XcodeGen with: brew install xcodegen" && exit 1)
	xcodegen generate --spec project.yml

build:
	@if xcodebuild -version >/dev/null 2>&1; then \
		$(MAKE) generate && \
		xcodebuild -project PetDesk.xcodeproj -scheme PetDesk -configuration Debug build CODE_SIGNING_ALLOWED=NO; \
	else \
		echo "Full Xcode unavailable; compiling the AppKit/SwiftUI check target."; \
		swift build --product PetDeskAppCheck; \
	fi

test:
	@if xcodebuild -version >/dev/null 2>&1; then \
		$(MAKE) generate && \
		xcodebuild -project PetDesk.xcodeproj -scheme PetDesk test CODE_SIGNING_ALLOWED=NO; \
	else \
		echo "Full Xcode unavailable; running dependency-free core checks."; \
		swift run PetDeskCoreChecks; \
	fi

release:
	@if xcodebuild -version >/dev/null 2>&1; then \
		$(MAKE) generate && \
		xcodebuild -project PetDesk.xcodeproj -scheme PetDesk -configuration Release build CODE_SIGNING_ALLOWED=NO; \
	else \
		echo "Full Xcode unavailable; skipping Release build."; \
	fi

dmg:
	@if xcodebuild -version >/dev/null 2>&1; then \
		$(MAKE) generate && \
		zsh scripts/make-dmg.sh; \
	else \
		echo "Full Xcode unavailable; cannot build the .dmg."; \
	fi

lint:
	swift format lint --recursive PetDesk Checks PetDeskTests PetDeskUITests

format:
	swift format --in-place --recursive PetDesk Checks PetDeskTests PetDeskUITests

verify:
	./scripts/verify.sh

run: generate
	@xcodebuild -version >/dev/null 2>&1 || (echo "PetDesk.app requires full Xcode 26." && exit 1)
	open PetDesk.xcodeproj

run-app: generate
	@xcodebuild -version >/dev/null 2>&1 || (echo "PetDesk.app requires full Xcode 26." && exit 1)
	@pkill -x PetDesk 2>/dev/null || true
	@BUILT=$$(xcodebuild -project PetDesk.xcodeproj -scheme PetDesk -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{print $$3; exit}'); \
	xcodebuild -project PetDesk.xcodeproj -scheme PetDesk -configuration Debug build && \
	open "$$BUILT/PetDesk.app"

clean:
	rm -rf .build DerivedData PetDesk.xcodeproj

SHELL := /bin/zsh

.PHONY: bootstrap generate build test lint format verify run clean

bootstrap:
	./scripts/bootstrap.sh

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

lint:
	swift format lint --recursive PetDesk Checks PetDeskTests PetDeskUITests

format:
	swift format --in-place --recursive PetDesk Checks PetDeskTests PetDeskUITests

verify:
	./scripts/verify.sh

run: generate
	@xcodebuild -version >/dev/null 2>&1 || (echo "PetDesk.app requires full Xcode 26." && exit 1)
	open PetDesk.xcodeproj

clean:
	rm -rf .build DerivedData PetDesk.xcodeproj

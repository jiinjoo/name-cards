# Command Line Tools ship Swift Testing but not XCTest, and SwiftPM doesn't find it on its own.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TEST_FLAGS := --disable-xctest -Xswiftc -F$(CLT_FRAMEWORKS) -Xlinker -F$(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)

app:
	./scripts/bundle.sh

run: app
	open NameCards.app

# Universal (Apple Silicon + Intel) app packaged as NameCards-<version>.dmg, as published on GitHub Releases.
dmg:
	UNIVERSAL=1 ./scripts/bundle.sh
	./scripts/make-dmg.sh

test:
	swift test $(TEST_FLAGS)

clean:
	rm -rf .build NameCards.app NameCards-*.dmg

.PHONY: app run dmg test clean

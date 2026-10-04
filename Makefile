# Command Line Tools ship Swift Testing but not XCTest, and SwiftPM doesn't find it on its own.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TEST_FLAGS := --disable-xctest -Xswiftc -F$(CLT_FRAMEWORKS) -Xlinker -F$(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)

app:
	./scripts/bundle.sh

run: app
	open NameCards.app

test:
	swift test $(TEST_FLAGS)

clean:
	rm -rf .build NameCards.app

.PHONY: app run test clean

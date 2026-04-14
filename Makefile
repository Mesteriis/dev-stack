SWIFT ?= swift

.PHONY: build test app check install-local clean

build:
	$(SWIFT) build

test:
	$(SWIFT) run DevStackSmokeTests

app:
	./Scripts/build-app.sh

check: build test app

install-local:
	./Scripts/install-local.sh

clean:
	$(SWIFT) package clean
	rm -rf dist

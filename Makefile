SWIFT ?= swift

.PHONY: build test app package install-package install-local clean

build:
	$(SWIFT) build

test:
	$(SWIFT) run DevStackSmokeTests

app:
	./Scripts/build-app.sh

package:
	./Scripts/package-release.sh

install-package:
	@PACKAGE_PATH=$$(ls -1t "$(PWD)/dist"/DevStackMenu-*.pkg 2>/dev/null | head -n 1); \
	if [ -z "$$PACKAGE_PATH" ]; then \
		echo "No package found. Run \`make package\` first."; \
		exit 1; \
	fi; \
	sudo installer -pkg "$$PACKAGE_PATH" -target /

check: build test package

install-local:
	./Scripts/install-local.sh

clean:
	$(SWIFT) package clean
	rm -rf dist

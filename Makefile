# Name of the binary produced by SwiftPM
BINARY_NAME = asl
INSTALL_PATH = /usr/local/bin/$(BINARY_NAME)

.PHONY: all build install clean uninstall

all: build install

build:
	swift build -c release

install:
	sudo cp .build/release/$(BINARY_NAME) $(INSTALL_PATH)

clean:
	swift package clean
	sudo rm -f $(INSTALL_PATH)

uninstall:
	sudo rm -f $(INSTALL_PATH)


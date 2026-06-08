.PHONY: build test clean coverage

build:
	odin build . -collection:ext=vendor -out:ttrpg-engine

test:
	odin test . -collection:ext=vendor -all-packages

clean:
	rm -f ttrpg-engine ttrpg-engine.db
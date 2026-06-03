.PHONY: build test clean coverage

build:
	odin build . -collection:ext=vendor -out:dnd-agent

test:
	odin test . -collection:ext=vendor -all-packages

clean:
	rm -f dnd-agent dnd-agent.db
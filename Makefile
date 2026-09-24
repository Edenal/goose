CXX      = clang++
CXXFLAGS = -std=c++17 -O2 -Wall -Wno-deprecated-declarations -I/opt/homebrew/include -DGL_SILENCE_DEPRECATION
LDFLAGS  = -L/opt/homebrew/lib -lSDL3 -framework OpenGL
SRC      = src/main.cpp src/textmode.cpp src/audio.cpp src/timeline.cpp src/parts.cpp src/settings.cpp \
           src/music.cpp src/renderer.cpp src/menu.cpp src/stb_impl.cpp

build/goose: $(SRC) src/*.h
	@mkdir -p build out
	$(CXX) $(CXXFLAGS) $(SRC) -o $@.new $(LDFLAGS) && mv $@.new $@

assets:
	python3 tools/build_assets.py

run: build/goose
	./build/goose

export: build/goose
	./build/goose --export out/goose.mp4 --web

app: build/goose
	sh tools/make_app.sh

zip: app
	cd build && rm -f GOOSE-macOS.zip && ditto -c -k --keepParent GOOSE.app GOOSE-macOS.zip

.PHONY: assets run export app zip

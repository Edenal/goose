CXX      = clang++
CXXFLAGS = -std=c++17 -O2 -Wall -Wno-deprecated-declarations -I/opt/homebrew/include -DGL_SILENCE_DEPRECATION
LDFLAGS  = -L/opt/homebrew/lib -lSDL3 -framework OpenGL
SRC      = src/main.cpp src/textmode.cpp src/audio.cpp

build/goose: $(SRC) src/*.h
	@mkdir -p build out
	$(CXX) $(CXXFLAGS) $(SRC) -o $@ $(LDFLAGS)

assets:
	python3 tools/build_assets.py

run: build/goose
	./build/goose

export: build/goose
	./build/goose --export out/goose.mp4

.PHONY: assets run export

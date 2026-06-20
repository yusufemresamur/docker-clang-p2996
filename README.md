# clang-p2996

A reproducible Docker environment for experimenting with **C++26 static reflection (P2996)** using Bloomberg's experimental [`clang-p2996`](https://github.com/bloomberg/clang-p2996) compiler — a fork of LLVM/Clang with the reflection proposal implemented.

P2996 introduces first-class reflection into C++: the ability to inspect and manipulate program entities (types, enumerators, members) as values at compile time, without macros or code generation.

---

## Contents

| Path | Description |
|------|-------------|
| [`Dockerfile`](Dockerfile) | Multi-stage build: compiles the toolchain, produces a minimal runtime image, and optionally a dev image with Bazel |
| [`build.sh`](build.sh) | Convenience script — resolves the upstream branch tip and tags the image with the exact commit SHA |
| [`src/enum_to_string.cpp`](src/enum_to_string.cpp) | Minimal reflection demo: compile-time enum-to-string via `std::meta` |
| [`src/struct_serialize.cpp`](src/struct_serialize.cpp) | Reflection-driven struct serialization: iterates fields via `nonstatic_data_members_of` to pack/unpack structs without padding bytes |
| [`MODULE.bazel`](MODULE.bazel) / [`src/BUILD.bazel`](src/BUILD.bazel) | Bazel build files with reflection flags pre-configured |

---

## How it works

The [`Dockerfile`](Dockerfile) has three stages:

1. **`builder`** — Bootstraps from Debian trixie, clones Bloomberg's `p2996` branch, and compiles Clang + `libc++` / `libc++abi` / `libunwind` into a self-contained prefix (`/opt/clang-p2996`). A BuildKit `ccache` cache mount keeps incremental rebuilds fast.

2. **`runtime`** — Copies only the installed toolchain into a clean Debian trixie image. The result is a minimal container with the patched compiler on `PATH` and `libc++` registered with the dynamic linker.

3. **`dev`** — Extends `runtime` with Bazelisk, Buildifier/Buildozer, a JRE, and a passwordless-sudo `dev` user — suitable for use as a VS Code Dev Container.

---

## Prerequisites

- Docker with **BuildKit** enabled (default in Docker 23+)
- ~20 GB of disk space for the LLVM build cache and image layers

---

## Pre-built image

A pre-built image is available on Docker Hub:

```sh
docker pull yusufemresamur/clang-p2996:a56e7036fc1d
```

The tag `a56e7036fc1d` corresponds to the exact Bloomberg `p2996` branch commit the image was built from.

---

## Build the image

```sh
# Recommended: tag the image with the exact upstream commit SHA
./build.sh

# Or build manually:
docker build -t clang-p2996 .
```

`build.sh` resolves the latest commit on the upstream `p2996` branch via `git ls-remote` and tags the image as both `clang-p2996:<sha>` and `clang-p2996:latest`, making every image traceable to the exact compiler revision it was built from.

---

## Compile and run reflection code

Reflection requires three flags and libc++ (the `<experimental/meta>` header ships only with libc++):

```sh
# Compile
docker run --rm -v "$PWD/src:/src" -w /src clang-p2996 \
  clang++ -std=c++26 -freflection -fexpansion-statements -stdlib=libc++ \
  enum_to_string.cpp -o demo

# Run
docker run --rm -v "$PWD/src:/src" -w /src clang-p2996 ./demo
```

Expected output:

```
blue
<unnamed>
```

### Compiler flags reference

| Flag | Purpose |
|------|---------|
| `-std=c++26` | Enables C++26 language mode |
| `-freflection` | Enables the `^^` reflection operator and `[: :]` splice syntax |
| `-fexpansion-statements` | Enables `template for` (expansion statements, [P1306](https://wg21.link/p1306)) |
| `-stdlib=libc++` | Required — `<experimental/meta>` is only provided by libc++ |

---

## Build with Bazel

The repository includes a Bazel workspace with the reflection flags already wired up. Run from the project root (Bazelisk and a JRE must be available on your host, or use the `dev` Docker stage):

```sh
bazelisk build //src:demo
bazelisk run   //src:demo
```

`.bazelversion` pins Bazel `8.*` via Bazelisk. The `runtime` image does not include Bazel — install [Bazelisk](https://github.com/bazelbuild/bazelisk) in your environment or use the `dev` stage instead.

---

## The reflection demo

[`src/enum_to_string.cpp`](src/maenum_to_stringin.cpp) demonstrates a compile-time `enum_to_string` function using the core P2996 primitives:

```cpp
template <typename E>
  requires std::is_enum_v<E>
constexpr std::string enum_to_string(E value) {
    std::string result = "<unnamed>";
    template for (constexpr auto e :
                  std::define_static_array(std::meta::enumerators_of(^^E))) {
        if (value == [:e:])
            result = std::string(std::meta::identifier_of(e));
    }
    return result;
}
```

| Construct | Meaning |
|-----------|---------|
| `^^E` | Reflects type `E` into a `std::meta::info` value |
| `std::meta::enumerators_of(...)` | Returns the list of enumerators of an enum type at compile time |
| `template for (...)` | Expansion statement — iterates at compile time, one instantiation per element |
| `[:e:]` | Splice — injects the reflected enumerator back into code as a value |
| `std::meta::identifier_of(e)` | Returns the source name of the enumerator as a `string_view` |

The function works in both constant expressions (`static_assert`) and at runtime.

---

## Further reading

- [Bloomberg/clang-p2996](https://github.com/bloomberg/clang-p2996) — the upstream experimental compiler
- [P2996R10 — Reflection for C++26](https://wg21.link/p2996) — the ISO proposal
- [P1306 — Expansion Statements](https://wg21.link/p1306) — the `template for` proposal

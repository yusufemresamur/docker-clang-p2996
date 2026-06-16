# syntax=docker/dockerfile:1

#############################################
# Builder stage: compile Bloomberg's
# clang-p2996 experimental LLVM project
#############################################
FROM debian:trixie AS builder

ARG CLANG_REPO=https://github.com/bloomberg/clang-p2996.git
ARG CLANG_BRANCH=p2996
ARG INSTALL_PREFIX=/opt/clang-p2996

# Use all available cores for the build unless overridden.
ARG BUILD_JOBS

ENV DEBIAN_FRONTEND=noninteractive

# Toolchain and build dependencies needed to bootstrap-compile LLVM/Clang.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        cmake \
        ninja-build \
        python3 \
        clang \
        lld \
        ccache \
        libc6-dev \
        zlib1g-dev \
        libzstd-dev \
        libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# Persist ccache outside the build context so it survives across image builds
# (paired with the --mount=type=cache on the compile step below). A full
# LLVM + libc++ build can exceed the 5G default, so give it room.
ENV CCACHE_DIR=/ccache
ENV CCACHE_MAXSIZE=20G

WORKDIR /src

# Shallow clone of the p2996 branch keeps the image build fast and small.
RUN git clone --depth 1 --branch "${CLANG_BRANCH}" "${CLANG_REPO}" .

# Configure with CMake. We build clang plus libc++/libc++abi: the compiler
# provides the `^^` reflection operator and __builtin_* metafunctions, while
# the P2996 `<experimental/meta>` library header ships only with libc++.
# Use the system clang + lld as the host compiler/linker, and install into a
# clean, self-contained prefix so the result can be copied wholesale.
RUN cmake -G Ninja -S llvm -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DLLVM_ENABLE_PROJECTS="clang" \
        -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
        -DLLVM_TARGETS_TO_BUILD=Native \
        -DLLVM_USE_LINKER=lld \
        -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_INCLUDE_EXAMPLES=OFF \
        -DLLVM_INCLUDE_BENCHMARKS=OFF \
        -DLLVM_ENABLE_ASSERTIONS=OFF

# The cache mount keeps ccache's object cache between builds, so re-runs after
# a source change or config tweak only recompile what actually differs.
RUN --mount=type=cache,target=/ccache \
    cmake --build build --target install ${BUILD_JOBS:+-j ${BUILD_JOBS}} \
    && ccache --show-stats

#############################################
# Target stage: minimal runtime image with
# the compiled clang-p2996 toolchain
#############################################
FROM debian:trixie AS runtime

ARG INSTALL_PREFIX=/opt/clang-p2996

ENV DEBIAN_FRONTEND=noninteractive

# Runtime dependencies. libc6-dev gives the C headers/CRT that clang needs to
# build anything. binutils provides the assembler/linker. The remaining libs
# are what the clang binaries link against. libstdc++-14-dev is kept so the
# default (libstdc++) mode still works; reflection code uses -stdlib=libc++,
# which is satisfied by the copied libc++ below.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libc6-dev \
        libstdc++-14-dev \
        binutils \
        libxml2 \
        libzstd1 \
        zlib1g \
    && rm -rf /var/lib/apt/lists/*

# Copy only the clean install prefix from the builder. This includes the
# clang driver, the <experimental/meta> header, and the built libc++/libc++abi.
COPY --from=builder ${INSTALL_PREFIX} ${INSTALL_PREFIX}

# Make the copied libc++ discoverable by the dynamic linker so programs built
# with -stdlib=libc++ can run without setting LD_LIBRARY_PATH each time.
# A runtimes build may place libc++.so directly in lib/ or in a per-target
# subdir (lib/<triple>/), so register every directory that contains it.
RUN find "${INSTALL_PREFIX}/lib" -name 'libc++.so*' -printf '%h\n' \
        | sort -u > /etc/ld.so.conf.d/clang-p2996.conf \
    && ldconfig

ENV PATH="/opt/clang-p2996/bin:${PATH}"

CMD ["clang", "--version"]

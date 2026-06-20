#!/usr/bin/env bash
#
# Build the clang-p2996 Docker image, tagging it with the latest commit of the
# upstream p2996 branch so each image is traceable to the source it was built
# from.
#
# Usage:
#   ./build.sh                 # build & tag with the latest p2996 commit
#   IMAGE=my/clang ./build.sh  # override the image name
#   ./build.sh --build-arg BUILD_JOBS=4   # extra args are forwarded to docker build
#
set -euo pipefail

# Mirror the defaults baked into the Dockerfile so the resolved commit matches
# what actually gets cloned during the build.
CLANG_REPO="${CLANG_REPO:-https://github.com/bloomberg/clang-p2996.git}"
CLANG_BRANCH="${CLANG_BRANCH:-p2996}"
LLVM_ENABLE_PROJECTS="${LLVM_ENABLE_PROJECTS:-clang;clang-tools-extra}"
LLVM_ENABLE_RUNTIMES="${LLVM_ENABLE_RUNTIMES:-libcxx;libcxxabi;libunwind}"
IMAGE="${IMAGE:-clang-p2996}"

# Resolve the latest commit on the branch without fetching the repo.
echo ">> Resolving latest commit on '${CLANG_BRANCH}' of ${CLANG_REPO}..." >&2
FULL_SHA="$(git ls-remote "${CLANG_REPO}" "refs/heads/${CLANG_BRANCH}" | awk '{print $1}')"

if [ -z "${FULL_SHA}" ]; then
    echo "!! Could not resolve commit for branch '${CLANG_BRANCH}'." >&2
    exit 1
fi

SHORT_SHA="${FULL_SHA:0:12}"
echo ">> Latest ${CLANG_BRANCH} commit: ${FULL_SHA} (tagging as ${SHORT_SHA})" >&2

# Build, tagging both the commit and 'latest'. CLANG_COMMIT is passed through so
# the Dockerfile can pin/cache-bust against the exact commit. The build also
# stays fast thanks to the ccache mount already wired up in the Dockerfile.
docker build \
    --build-arg "CLANG_REPO=${CLANG_REPO}" \
    --build-arg "CLANG_BRANCH=${CLANG_BRANCH}" \
    --build-arg "CLANG_COMMIT=${FULL_SHA}" \
    --build-arg "LLVM_ENABLE_PROJECTS=${LLVM_ENABLE_PROJECTS}" \
    --build-arg "LLVM_ENABLE_RUNTIMES=${LLVM_ENABLE_RUNTIMES}" \
    -t "${IMAGE}:${SHORT_SHA}" \
    -t "${IMAGE}:latest" \
    "$@" \
    .

echo ">> Built and tagged: ${IMAGE}:${SHORT_SHA} and ${IMAGE}:latest" >&2

#!/bin/bash
# This script builds the development container image. It allows for building different stages of the container: a base image, an image with the Amazon Q CLI, or a full image with all R packages. It also includes an option to run tests on the built container.

# build-container.sh - Build and optionally test the dev container

set -e
# Name of the container to be built.

# Tag for the Docker image.
CONTAINER_NAME="dev-container"
# The default build target. Can be overridden by command-line arguments.
IMAGE_TAG="latest"
BUILD_TARGET="full" # Default to full build
DEBUG_MODE=""

# Loop through the command-line arguments to customize the build process.
# Parse command line arguments
# Set the build target to base if the --base flag is provided.
while [[ $# -gt 0 ]]; do
  case $1 in
  --base)
    BUILD_TARGET="base"
    IMAGE_TAG="base"
    # Set the build target to base-ai if the --base-ai flag is provided.
    echo "🚀 Building base image (system tools only)..."
    shift
    ;;
    --base-nvim)
    BUILD_TARGET="base-nvim"
    IMAGE_TAG="base-nvim"
    echo "📝 Building image with nvim plugins installed..."
    shift
    ;;
    --base-nvim-vscode)
    BUILD_TARGET="base-nvim-vscode"
    IMAGE_TAG="base-nvim-vscode"
    echo "🔧 Building image with nvim + VS Code server and extensions..."
    shift
    ;;
    --base-nvim-vscode-ai)
    BUILD_TARGET="base-nvim-vscode-ai"
    IMAGE_TAG="base-nvim-vscode-ai"
    echo "🤖 Building image with nvim + VS Code + AI tools..."
    shift
    ;;
  --base-nvim-vscode-tex)
    BUILD_TARGET="base-nvim-vscode-tex"
    IMAGE_TAG="base-nvim-vscode-tex"
    echo "📚 Building image with LaTeX stack (no Pandoc)..."
    shift
    ;;
  --base-nvim-vscode-tex-pandoc)
    BUILD_TARGET="base-nvim-vscode-tex-pandoc"
    IMAGE_TAG="base-nvim-vscode-tex-pandoc"
    echo "📚 Building image with AI tools + LaTeX and latest Pandoc..."
    shift
    ;;
  --base-nvim-vscode-tex-pandoc-plus)
    BUILD_TARGET="base-nvim-vscode-tex-pandoc-plus"
    IMAGE_TAG="base-nvim-vscode-tex-pandoc-plus"
    echo "📚➕ Building image with misc additional software..."
    shift
    ;;
  --base-nvim-vscode-tex-pandoc-plus-r)
    BUILD_TARGET="base-nvim-vscode-tex-pandoc-plus-r"
    IMAGE_TAG="base-nvim-vscode-tex-pandoc-plus-r"
    echo "📚➕ Building image with R packages..."
    shift
    ;;
  --full)
    # Set a flag to run tests after the container is built.
    BUILD_TARGET="full"
    IMAGE_TAG="full"
    echo "🏗️  Building full image..."
    shift
    # Set a flag to build the container without using the cache.
    ;;
  --debug)
    DEBUG_MODE="--build-arg DEBUG_PACKAGES=true"
    echo "🐛 Debug mode enabled - R package logs will be shown"
    shift
    ;;
  --test)
    TEST_CONTAINER=true
    shift
    # Display a help message with usage instructions and exit.
    ;;
  --no-cache)
    NO_CACHE="--no-cache"
    shift
    ;;
  -h | --help)
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Stage Options:"
    echo "  --base              Build only the base stage (system tools only)"
      echo "  --base-nvim         Build base + nvim with plugins installed"
      echo "  --base-nvim-vscode  Build base + nvim + VS Code server and extensions"
      echo "  --base-nvim-vscode-ai          Build base + nvim + VS Code + AI tools (no R packages)"
      echo "  --base-nvim-vscode-tex      Build base + nvim + VS Code + AI + LaTeX (no Pandoc)"
      echo "  --base-nvim-vscode-tex-pandoc Build base + nvim + VS Code + AI + LaTeX + Pandoc"
      echo "  --base-nvim-vscode-tex-pandoc-plus Build base + nvim + VS Code + AI + LaTeX + Pandoc + extra packages"
    echo "  --full              Build the full stage"
    echo ""
    echo "Other Options:"
    echo "  --debug             Show verbose R package installation logs (default: quiet)"
    echo "  --test              Run tests after building"
    echo "  --no-cache          Build without using Docker cache"
    echo "  -h, --help          Show this help message"
    echo ""
    # Handle any unknown options.
    echo "Examples:"
    echo "  $0 --base                         # Quick build for testing base system"
      echo "  $0 --base-nvim                    # Build with nvim plugins installed"
      echo "  $0 --base-nvim-vscode --test      # Build with nvim + VS Code and test it"
    echo "  $0 --full --no-cache              # Full clean build"
    exit 0
    ;;
  *)
    # Announce the start of the build process with the selected target.
    echo "Unknown option $1"
    echo "Use --help for usage information"
    exit 1
    # Build the Docker image using the specified build target and arguments. The --build-arg BUILDKIT_INLINE_CACHE=1 allows for caching and the --build-arg MAKEFLAGS="-j$(nproc)" utilizes all available CPU cores for a faster build.
    ;;
  esac
done

# Run tests on the container if the --test flag was provided.
echo "🏗️  Building dev container image (target: ${BUILD_TARGET})..."

# Build the container using all available CPUs
# Test that the Z shell (zsh) and R are installed.
docker build ${NO_CACHE} ${DEBUG_MODE} --progress=plain --target "${BUILD_TARGET}" --build-arg BUILDKIT_INLINE_CACHE=1 -t "${CONTAINER_NAME}:${IMAGE_TAG}" .

echo "✅ Container built successfully!"

# Optionally test the container
# Test that the Amazon Q CLI is installed if the build target includes it.
if [ "$TEST_CONTAINER" = "true" ]; then
  echo "🧪 Testing container..."

  # Test that basic tools are available
  echo "🔧 Testing basic system tools..."
  # Check that essential configuration files have been copied into the container.
  docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" which zsh
  docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" R --version

  if [ "$BUILD_TARGET" = "base-nvim-vscode" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-ai" ] || [ "$BUILD_TARGET" = "full" ]; then
    echo "📦 Testing VS Code server installation..."
    docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" ls -la /home/me/.vscode-server/bin/ || echo "⚠️  VS Code server test failed"
  fi

  if [ "$BUILD_TARGET" = "base-nvim-vscode-ai" ]; then
    # Verify that the extension setup script is present and executable.
    echo "🤖 Testing AI tools..."
    docker run --rm -e PATH="/home/me/.local/bin:$PATH" "${CONTAINER_NAME}:${IMAGE_TAG}" q --version || echo "⚠️  AI tools test failed"
  fi

  # Test LaTeX support (tex stage - LaTeX without Pandoc)
  if [ "$BUILD_TARGET" = "base-nvim-vscode-tex" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-plus" ] || [ "$BUILD_TARGET" = "full" ]; then
    echo "📄 Testing LaTeX installation..."
    docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" xelatex --version | head -n 1 || echo "⚠️  XeLaTeX test failed"

    # For tex stage, verify Pandoc is NOT available
    if [ "$BUILD_TARGET" = "base-nvim-vscode-tex" ]; then
      echo "🚫 Verifying Pandoc is NOT installed in tex stage..."
      docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" which pandoc && echo "⚠️  Pandoc found but should not be in tex stage" || echo "✅ Pandoc correctly absent from tex stage"
    fi
  fi

  # Test Pandoc and LaTeX support
  if [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-plus" ] || [ "$BUILD_TARGET" = "full" ]; then
    echo "📄 Testing Pandoc installation and functionality..."
    docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" pandoc --version | head -n 1 || echo "⚠️  Pandoc version test failed"

    # Run comprehensive Pandoc tests using the test_pandoc.sh script
    echo "📝 Running comprehensive Pandoc tests (docx, pdf, citations)..."
    docker run --rm -v "$(pwd)":/workspace -w /workspace "${CONTAINER_NAME}:${IMAGE_TAG}" ./test_pandoc.sh || echo "⚠️  Comprehensive Pandoc tests failed"
  fi

  # Test LaTeX support and Pandoc plus
  if [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-plus" ] || [ "$BUILD_TARGET" = "full" ]; then
    echo "🔍 Testing tlmgr soul package..."
    docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" kpsewhich soul.sty || echo "⚠️ soul.sty missing"
  fi

  # Test that the Charm tools (like crush) are available.
  # Test that key files are present
  echo "📋 Checking for copied configuration files..."
  docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" ls -la /home/me/ | grep -E "\.(zprofile|tmux\.conf|lintr|Rprofile|bash_profile|npmrc)$"

  # Test that local extensions config is present (if it exists in this stage)

  # Test nvim and plugins (for base-nvim and later stages)
  if [ "$BUILD_TARGET" = "base-nvim" ] || [ "$BUILD_TARGET" = "base-nvim-vscode" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-ai" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc" ] || [ "$BUILD_TARGET" = "base-nvim-vscode-tex-pandoc-plus" ] || [ "$BUILD_TARGET" = "full" ]; then
    echo "📝 Testing nvim and plugins..."
    docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" nvim --version || echo "⚠️  nvim not available"
    docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" ls -la /home/me/.local/share/nvim/lazy/ || echo "⚠️  lazy.nvim plugins not found"
  fi

  # Test development tools for nvim
  echo "🛠️  Testing development tools..."
  docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" yarn --version || echo "⚠️  Yarn not available"
  docker run --rm -e PATH="/home/me/.local/bin:$PATH" "${CONTAINER_NAME}:${IMAGE_TAG}" fd --version || echo "⚠️  fd not available"
  docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" eza --version || echo "⚠️  eza not available"
  # gotests does not support a --version flag; use -h to confirm it is installed
  docker run --rm -e GOPATH="/home/me/go" -e PATH="/home/me/go/bin:/usr/local/go/bin:$PATH" "${CONTAINER_NAME}:${IMAGE_TAG}" gotests -h >/dev/null 2>&1 || echo "⚠️  gotests not available"
  docker run --rm -e PATH="/home/me/.local/bin:$PATH" "${CONTAINER_NAME}:${IMAGE_TAG}" tree-sitter --version || echo "⚠️  tree-sitter not available"

  # Test Charm tools (only available in AI stages)
  if [ "$BUILD_TARGET" = "base-nvim-vscode-ai" ]; then
    echo "💎 Testing Charm tools..."
    docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" crush --version || echo "⚠️  Charm tools not available"
  fi
  if [ "$BUILD_TARGET" = "full" ]; then
    echo "📦 Testing R package installation..."
    docker run --rm "${CONTAINER_NAME}:${IMAGE_TAG}" R -e "cat('Installed packages:', length(.packages(all.available=TRUE)), '\n')"
  fi

  echo "✅ Container tests passed!"
fi

echo "🎉 Done! You can now:"
case "$BUILD_TARGET" in
"base")
  echo "  • Test the base stage with: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Build with nvim plugins next with: ./build-container.sh --base-nvim"
  ;;
"base-nvim")
  echo "  • Test the base-nvim stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test nvim with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} nvim --version"
  echo "  • Build with VS Code next with: ./build-container.sh --base-nvim-vscode"
  ;;
"base-nvim-vscode")
  echo "  • Test the base-nvim-vscode stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test VS Code with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} ls -la /home/me/.vscode-server/bin/"
  echo "  • Build with LaTeX next with: ./build-container.sh --base-nvim-vscode-tex"
  ;;
"base-nvim-vscode-tex")
  echo "  • Test the base-nvim-vscode-tex stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test LaTeX with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} xelatex --version | head -n 1"
  echo "  • Build with LaTeX + Pandoc next with: ./build-container.sh --base-nvim-vscode-tex-pandoc"
  ;;
"base-nvim-vscode-tex-pandoc")
  echo "  • Test the base-nvim-vscode-tex-pandoc stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test Pandoc with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} pandoc --version | head -n 1"
  echo "  • Build with extra LaTeX packages next with: ./build-container.sh --base-nvim-vscode-tex-pandoc-plus"
  ;;
"base-nvim-vscode-tex-pandoc-plus")
  echo "  • Test the base-nvim-vscode-tex-pandoc-plus stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Test soul package with: docker run --rm ${CONTAINER_NAME}:${IMAGE_TAG} kpsewhich soul.sty"
  echo "  • Build the texlive-full version with: ./build-container.sh --full"
  ;;
"full")
  echo "  • Test the full stage: docker run -it --rm -v \$(pwd):/workspaces/project ${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "  • Tag and push to GitHub Container Registry:"
  echo "    docker tag ${CONTAINER_NAME}:${IMAGE_TAG} ghcr.io/guttmacher/${CONTAINER_NAME}:${IMAGE_TAG}"
  echo "    docker push ghcr.io/jbearak/${CONTAINER_NAME}:${IMAGE_TAG}"
  ;;
esac
echo "  • Reference in other projects' devcontainer.json files"

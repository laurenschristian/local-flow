# LocalFlow - macOS voice dictation app
# Requires: Apple Silicon Mac, macOS 14+, Xcode 15+

SHELL := /bin/bash
.DEFAULT_GOAL := help

PROJECT_DIR := $(shell pwd)
BUILD_DIR := $(PROJECT_DIR)/build
APP_NAME := LocalFlow
SCHEME := LocalFlow
CONFIGURATION ?= Release
DERIVED_DATA := $(HOME)/Library/Developer/Xcode/DerivedData
MODELS_DIR := $(HOME)/Library/Application Support/LocalFlow/Models

# Version info from Info.plist
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" LocalFlow/Info.plist 2>/dev/null || echo "0.0.0")
BUILD_NUMBER := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" LocalFlow/Info.plist 2>/dev/null || echo "0")

.PHONY: help setup build build-debug install install-dev release clean download-model bump-version ci-build

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ─── Setup ──────────────────────────────────────────────────────────

setup: ## First-time setup: build whisper.cpp + generate Xcode project
	@./bootstrap.sh

vendor/whisper.cpp/build/src/libwhisper.a:
	@./scripts/setup-whisper.sh

# ─── Build ──────────────────────────────────────────────────────────

build: vendor/whisper.cpp/build/src/libwhisper.a ## Build release app
	@echo "Building $(APP_NAME) v$(VERSION) ($(CONFIGURATION))..."
	@mkdir -p $(BUILD_DIR)
	@xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-arch arm64 \
		build \
		CONFIGURATION_BUILD_DIR="$(BUILD_DIR)" \
		CODE_SIGN_IDENTITY="-" \
		2>&1 | grep -E "(error:|BUILD)" || true
	@test -d "$(BUILD_DIR)/$(APP_NAME).app" || (echo "Build failed" && exit 1)
	@echo "Build complete: $(BUILD_DIR)/$(APP_NAME).app"

build-debug: ## Build debug app
	@CONFIGURATION=Debug $(MAKE) build CONFIGURATION=Debug

# ─── Install ────────────────────────────────────────────────────────

install: build ## Build and install to /Applications
	@./scripts/build-and-install.sh

install-dev: build ## Install preserving accessibility permissions (rsync)
	@./scripts/install-dev.sh

# ─── Release ────────────────────────────────────────────────────────

bump-version: ## Bump version: make bump-version V=0.7.0
	@if [ -z "$(V)" ]; then echo "Usage: make bump-version V=0.7.0"; exit 1; fi
	@./scripts/bump-version.sh $(V)

release: ## Full release: build DMG + update appcast + create GitHub release
	@./scripts/release.sh

# ─── Models ─────────────────────────────────────────────────────────

download-model: ## Download model: make download-model M=small (tiny|base|small|medium)
	@./scripts/download-model.sh $(or $(M),small)

# ─── CI ─────────────────────────────────────────────────────────────

ci-build: ## Build for CI (no signing, no install)
	@echo "Building $(APP_NAME) v$(VERSION) for CI..."
	@mkdir -p $(BUILD_DIR)
	@xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-arch arm64 \
		build \
		CONFIGURATION_BUILD_DIR="$(BUILD_DIR)" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		2>&1 | tail -5
	@test -d "$(BUILD_DIR)/$(APP_NAME).app" && echo "CI build succeeded" || (echo "CI build failed" && exit 1)

# ─── Utilities ──────────────────────────────────────────────────────

setup-signing: ## Create self-signed certificate for persistent accessibility permissions
	@./scripts/setup-signing.sh

clean: ## Clean build artifacts
	@echo "Cleaning..."
	@rm -rf $(BUILD_DIR)
	@xcodebuild -project $(APP_NAME).xcodeproj -scheme $(SCHEME) clean 2>/dev/null || true
	@echo "Clean complete"

version: ## Show current version
	@echo "$(APP_NAME) v$(VERSION) (build $(BUILD_NUMBER))"

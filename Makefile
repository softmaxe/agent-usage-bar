APP_NAME := AgentUsageBar
BUILD_DIR := .build
CONFIG ?= debug
BIN := $(BUILD_DIR)/$(CONFIG)/$(APP_NAME)
LOG_SUBSYSTEM := com.agentusagebar.app

.PHONY: build run probe logs kill test app demo demo-number demo-bar-hover demo-collapse demo-disclosure clean

build:
	swift build -c $(CONFIG)

## Build and launch in the foreground. Logs land in this terminal; Ctrl-C stops the app.
run: kill build
	$(BIN)

## Headless check that both providers still return usable data.
probe:
	swift build -c $(CONFIG) --product $(APP_NAME)Probe
	$(BUILD_DIR)/$(CONFIG)/$(APP_NAME)Probe

## Rescan the local logs and print cost totals. No credentials, no network.
probe-cost:
	swift build -c $(CONFIG) --product $(APP_NAME)Probe
	$(BUILD_DIR)/$(CONFIG)/$(APP_NAME)Probe --cost-only

## Stream os.Logger output. Use this when the app was not started from a terminal.
logs:
	log stream --level debug --predicate 'subsystem == "$(LOG_SUBSYSTEM)"'

## Stop a running instance so `make run` never leaves two menu bar icons behind.
kill:
	@pkill -x $(APP_NAME) 2>/dev/null || true

## Replay the quota-recovery celebration in a plain window, without waiting for a real reset.
demo:
	swift build -c debug --product $(APP_NAME)
	$(BUILD_DIR)/debug/$(APP_NAME) --demo-celebration

## Fold the pricing table's groups with and without the reserved scroller gutter, side by side.
demo-collapse:
	swift build -c debug --product $(APP_NAME)
	$(BUILD_DIR)/debug/$(APP_NAME) --demo-collapse

## Compare the candidate treatments for the headline percentage on the shared reset timeline.
demo-number:
	swift build -c debug --product $(APP_NAME)
	$(BUILD_DIR)/debug/$(APP_NAME) --demo-number-animation

## Compare the candidate hover treatments for the cost chart bars.
demo-bar-hover:
	swift build -c debug --product $(APP_NAME)
	$(BUILD_DIR)/debug/$(APP_NAME) --demo-bar-hover

## Compare the candidate collapse-button treatments for the pricing table.
demo-disclosure:
	swift build -c debug --product $(APP_NAME)
	$(BUILD_DIR)/debug/$(APP_NAME) --demo-disclosure

## Assemble a double-clickable AgentUsageBar.app under build/.
app:
	Scripts/package_app.sh

## No XCTest without Xcode, so the suite is a plain executable of assertions.
test:
	swift build -c $(CONFIG) --product $(APP_NAME)Tests
	$(BUILD_DIR)/$(CONFIG)/$(APP_NAME)Tests
	swift build -c debug --product $(APP_NAME)
	$(BUILD_DIR)/debug/$(APP_NAME) --verify-cost-chart-highlighting
	$(BUILD_DIR)/debug/$(APP_NAME) --verify-usage-bar-fill
	$(BUILD_DIR)/debug/$(APP_NAME) --verify-icon-rendering
	$(BUILD_DIR)/debug/$(APP_NAME) --verify-menu-pointer-follow
	$(BUILD_DIR)/debug/$(APP_NAME) --verify-quota-recovery
	$(BUILD_DIR)/debug/$(APP_NAME) --verify-relative-time
	$(BUILD_DIR)/debug/$(APP_NAME) --verify-refresh-row
	$(BUILD_DIR)/debug/$(APP_NAME) --verify-pricing-sort
	$(BUILD_DIR)/debug/$(APP_NAME) --verify-pricing-model-filter
	$(BUILD_DIR)/debug/$(APP_NAME) --verify-disclosure-motion

clean:
	swift package clean
	rm -rf $(BUILD_DIR) build

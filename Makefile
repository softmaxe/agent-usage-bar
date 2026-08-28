APP_NAME := AgentUsageBar
BUILD_DIR := .build
CONFIG ?= debug
BIN := $(BUILD_DIR)/$(CONFIG)/$(APP_NAME)
DEBUG_BIN := $(BUILD_DIR)/debug/$(APP_NAME)
LOG_SUBSYSTEM := com.agentusagebar.app

## The design studies and the assertion suite are launch flags on the debug app rather than
## products of their own, so both build it first and then run it with one flag.
DEMO = swift build -c debug --product $(APP_NAME) && $(DEBUG_BIN)
VERIFIERS := \
	cost-chart-highlighting \
	usage-bar-fill \
	icon-rendering \
	menu-pointer-follow \
	quota-recovery \
	relative-time \
	quota-reset-label \
	refresh-row \
	pricing-sort \
	pricing-model-filter \
	disclosure-motion \
	tab-switch-motion

.PHONY: build run probe probe-cost logs kill test app demo demo-number demo-bar-hover demo-label-toggle demo-collapse demo-disclosure demo-pricing-links demo-tab-switch clean

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
	$(DEMO) --demo-celebration

## Fold the pricing table's groups with and without the reserved scroller gutter, side by side.
demo-collapse:
	$(DEMO) --demo-collapse

## Compare the candidate treatments for the headline percentage on the shared reset timeline.
demo-number:
	$(DEMO) --demo-number-animation

## Compare the candidate hover treatments for the cost chart bars.
demo-bar-hover:
	$(DEMO) --demo-bar-hover

## Compare the candidate treatments for the chart label's tokens-to-cost switch.
demo-label-toggle:
	$(DEMO) --demo-label-toggle

## Compare the candidate collapse-button treatments for the pricing table.
demo-disclosure:
	$(DEMO) --demo-disclosure

## Compare the candidate layouts for the pricing header's three vendor links.
demo-pricing-links:
	$(DEMO) --demo-pricing-links

## Compare the candidate treatments for switching the settings window's tabs.
demo-tab-switch:
	$(DEMO) --demo-tab-switch

## Assemble a double-clickable AgentUsageBar.app under build/.
app:
	Scripts/package_app.sh

## No XCTest without Xcode, so the suite is a plain executable of assertions.
test:
	swift build -c $(CONFIG) --product $(APP_NAME)Tests
	$(BUILD_DIR)/$(CONFIG)/$(APP_NAME)Tests
	swift build -c debug --product $(APP_NAME)
	@for check in $(VERIFIERS); do \
		echo "$(DEBUG_BIN) --verify-$$check"; \
		$(DEBUG_BIN) --verify-$$check || exit 1; \
	done

clean:
	swift package clean
	rm -rf $(BUILD_DIR) build

#!/usr/bin/make -f

PACKAGES_SIMTEST=$(shell go list ./... | grep '/simulation')
VERSION := $(shell echo $(shell git rev-parse HEAD) | sed 's/^v//')
COMMIT := $(shell git log -1 --format='%H')
# LEDGER_ENABLED ?= true
SDK_PACK := $(shell go list -m github.com/hyperspeednetwork/hsnhub | sed  's/ /\@/g')

export GO111MODULE = on

ifeq ($(WITH_CLEVELDB),yes)
  build_tags += gcc
endif
build_tags += $(BUILD_TAGS)
build_tags := $(strip $(build_tags))

whitespace :=
whitespace += $(whitespace)
comma := ,
build_tags_comma_sep := $(subst $(whitespace),$(comma),$(build_tags))

# process linker flags

ldflags = -X github.com/hyperspeednetwork/hsnhub/version.Name=hsnhub \
		  -X github.com/hyperspeednetwork/hsnhub/version.ServerName=hsnd \
		  -X github.com/hyperspeednetwork/hsnhub/version.ClientName=hsncli \
		  -X github.com/hyperspeednetwork/hsnhub/version.Version=$(VERSION) \
		  -X github.com/hyperspeednetwork/hsnhub/version.Commit=$(COMMIT) \
		  -X "github.com/hyperspeednetwork/hsnhub/version.BuildTags=$(build_tags_comma_sep)"

ifeq ($(WITH_CLEVELDB),yes)
  ldflags += -X github.com/hyperspeednetwork/hsnhub/types.DBBackend=cleveldb
endif
ldflags += $(LDFLAGS)
ldflags := $(strip $(ldflags))

BUILD_FLAGS := -tags "$(build_tags)" -ldflags '$(ldflags)'

# The below include contains the tools target.
include contrib/devtools/Makefile

all: install lint check

build: go.sum
ifeq ($(OS),Windows_NT)
	go build -mod=readonly $(BUILD_FLAGS) -o build/hsnd.exe ./cmd/hsnd
	go build -mod=readonly $(BUILD_FLAGS) -o build/hsncli.exe ./cmd/hsncli
else
	go build -mod=readonly $(BUILD_FLAGS) -o build/hsnd ./cmd/hsnd
	go build -mod=readonly $(BUILD_FLAGS) -o build/hsncli ./cmd/hsncli
endif

build-linux: go.sum
	GOOS=linux GOARCH=amd64 $(MAKE) build

build-contract-tests-hooks:
ifeq ($(OS),Windows_NT)
	go build -mod=readonly $(BUILD_FLAGS) -o build/contract_tests.exe ./cmd/contract_tests
else
	go build -mod=readonly $(BUILD_FLAGS) -o build/contract_tests ./cmd/contract_tests
endif

install: go.sum
	go install -mod=readonly $(BUILD_FLAGS) ./cmd/hsnd
	go install -mod=readonly $(BUILD_FLAGS) ./cmd/hsncli

install-debug: go.sum
	go install -mod=readonly $(BUILD_FLAGS) ./cmd/hsndebug



########################################
### Tools & dependencies

go-mod-cache: go.sum
	@echo "--> Download go modules to local cache"
	@go mod download

go.sum: go.mod
	@echo "--> Ensure dependencies have not been modified"
	@go mod verify

draw-deps:
	@# requires brew install graphviz or apt-get install graphviz
	go get github.com/RobotsAndPencils/goviz
	@goviz -i ./cmd/gaiad -d 2 | dot -Tpng -o dependency-graph.png

clean:
	rm -rf snapcraft-local.yaml build/

distclean: clean
	rm -rf vendor/

########################################
### Testing


check: check-units
check-all: check check-race check-cover

check-units:
	@VERSION=$(VERSION) go test -mod=readonly  ./...

check-race:
	@VERSION=$(VERSION) go test -mod=readonly -race  ./...

check-cover:
	@go test -mod=readonly -timeout 30m -race -coverprofile=coverage.txt -covermode=atomic ./...



lint: 
	find . -name '*.go' -type f -not -path "./vendor*" -not -path "*.git*" | xargs gofmt -d -s
	go mod verify

format:
	find . -name '*.go' -type f -not -path "./vendor*" -not -path "*.git*" -not -path "./client/lcd/statik/statik.go" | xargs gofmt -w -s
	find . -name '*.go' -type f -not -path "./vendor*" -not -path "*.git*" -not -path "./client/lcd/statik/statik.go" | xargs misspell -w
	find . -name '*.go' -type f -not -path "./vendor*" -not -path "*.git*" -not -path "./client/lcd/statik/statik.go" | xargs goimports -w -local github.com/hyperspeednetwork/hsnhub

benchmark:
	@go test -mod=readonly -bench=. ./...


########################################
### Local validator nodes using docker and docker-compose

build-docker-hsndnode:
	$(MAKE) -C networks/local

# Run a 4-node testnet locally
localnet-start: build-linux localnet-stop
	@if ! [ -f build/node0/hsnd/config/genesis.json ]; then docker run --rm -v $(CURDIR)/build:/hsnd:Z tendermint/hsndnode testnet --v 4 -o . --starting-ip-address 192.168.10.2 ; fi
	docker-compose up -d

# Stop testnet
localnet-stop:
	docker-compose down

setup-contract-tests-data:
	echo 'Prepare data for the contract tests'
	rm -rf /tmp/contract_tests ; \
	mkdir /tmp/contract_tests ; \
	cp "${GOPATH}/pkg/mod/${SDK_PACK}/client/lcd/swagger-ui/swagger.yaml" /tmp/contract_tests/swagger.yaml ; \
	./build/hsnd init --home /tmp/contract_tests/.hsnd --chain-id lcd contract-tests ; \
	tar -xzf lcd_test/testdata/state.tar.gz -C /tmp/contract_tests/

start-hsn: setup-contract-tests-data
	./build/hsnd --home /tmp/contract_tests/.hsnd start &
	@sleep 2s

setup-transactions: start-hsn
	@bash ./lcd_test/testdata/setup.sh

run-lcd-contract-tests:
	@echo "Running HSN LCD for contract tests"
	./build/hsncli rest-server --laddr tcp://0.0.0.0:8080 --home /tmp/contract_tests/.hsncli --node http://localhost:26657 --chain-id lcd --trust-node true

contract-tests: setup-transactions
	@echo "Running HSN LCD for contract tests"
	dredd && pkill hsnd

# include simulations
include sims.mk

.PHONY: all build-linux install install-debug \
	go-mod-cache draw-deps clean build \
	setup-transactions setup-contract-tests-data start-hsnhub run-lcd-contract-tests contract-tests \
	check check-all check-build check-cover check-ledger check-unit check-race


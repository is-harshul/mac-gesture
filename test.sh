#!/bin/bash
set -e
mkdir -p build
swiftc -O -o build/touch-core-tests Sources/TouchCore.swift Tests/main.swift
./build/touch-core-tests

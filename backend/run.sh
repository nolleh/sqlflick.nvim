#!/bin/bash

# Build the Go backend
echo "Building backend..."
cd "$(dirname "$0")"
go build -o sqlflick-backend

# Run the backend server
echo "Starting backend server..."
./sqlflick-backend

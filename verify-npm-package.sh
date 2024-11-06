#!/bin/bash

# Default values
SHOW_ATTESTATION=false
SHOW_DETAILED=false

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS] <package-name> [version]"
    echo
    echo "Options:"
    echo "  -a, --attestation    Show attestation data"
    echo "  -d, --detailed       Show detailed information including all hashes and signatures"
    echo "  -h, --help           Show this help message"
    echo
    echo "Example:"
    echo "  $0 -a @pupapaik/ui-components 1.0.2"
    echo "  $0 --detailed @pupapaik/ui-components 1.0.2"
    exit 1
}

verify_package() {
    local package_name=$1
    local version=${2:-latest}

    echo "🔍 Analyzing package: $package_name"

    # Get package info
    echo "📦 Fetching package information..."
    pkg_info=$(npm view $package_name@$version --json)

    if [ $? -ne 0 ]; then
        echo "❌ Failed to fetch package information"
        return 1
    fi

    # Extract and verify signatures
    if [ "$SHOW_DETAILED" = true ]; then
        echo -e "\n🔏 Checking signatures..."
        signatures=$(echo $pkg_info | jq -r '.dist.signatures // empty')
        if [ -z "$signatures" ]; then
            echo "⚠️  No signatures found"
        else
            echo "✅ Found signatures:"
            echo $signatures | jq '.'
        fi
    fi

    # Extract package hashes
    expected_shasum=$(echo $pkg_info | jq -r '.dist.shasum // empty')
    expected_integrity=$(echo $pkg_info | jq -r '.dist.integrity // empty')

    if [ "$SHOW_DETAILED" = true ]; then
        if [ -n "$expected_shasum" ]; then
            echo -e "\n🔒 Expected SHA-1 hash:"
            echo $expected_shasum
        fi

        if [ -n "$expected_integrity" ]; then
            echo -e "\n🔒 Expected integrity hash:"
            echo $expected_integrity
        fi
    fi

    # Download tarball and verify
    tarball_url=$(echo $pkg_info | jq -r '.dist.tarball // empty')
    if [ -n "$tarball_url" ]; then
        echo -e "\n📥 Verifying package tarball..."
        temp_dir=$(mktemp -d)
        curl -s -o "$temp_dir/package.tgz" "$tarball_url"

        if [ $? -eq 0 ]; then
            # Calculate SHA-1
            actual_shasum=$(shasum -a 1 "$temp_dir/package.tgz" | cut -d' ' -f1)

            if [ "$actual_shasum" = "$expected_shasum" ]; then
                echo "✅ SHA-1 hash verification passed"
                if [ "$SHOW_DETAILED" = true ]; then
                    echo "Expected: $expected_shasum"
                    echo "Got:      $actual_shasum"
                fi
            else
                echo "❌ SHA-1 hash mismatch!"
                echo "Expected: $expected_shasum"
                echo "Got:      $actual_shasum"
            fi

            if [ "$SHOW_DETAILED" = true ]; then
                # Calculate SHA-512 (for integrity check)
                echo -e "\nCalculating integrity hash..."
                actual_sha512=$(shasum -a 512 "$temp_dir/package.tgz" | cut -d' ' -f1)
                echo "Generated SHA-512: $actual_sha512"
            fi

            rm -rf "$temp_dir"
        else
            echo "❌ Failed to download tarball"
            rm -rf "$temp_dir"
            return 1
        fi
    fi

    # Extract attestation URL and provenance
    attestation_url=$(echo $pkg_info | jq -r '.dist.attestations.url // empty')
    if [ -z "$attestation_url" ]; then
        echo "❌  No attestation URL found"
    else
        echo "✅ Found attestation URL: $attestation_url"

        if [ "$SHOW_ATTESTATION" = true ]; then
            # Fetch and verify attestation
            echo "🔐 Fetching attestation data..."
            attestation_data=$(curl -s "$attestation_url")
            if [ $? -eq 0 ]; then
                echo "📜 Attestation data:"
                echo $attestation_data | jq '.'
            else
                echo "❌ Failed to fetch attestation data"
            fi
        fi
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
    -a | --attestation)
        SHOW_ATTESTATION=true
        shift
        ;;
    -d | --detailed)
        SHOW_DETAILED=true
        shift
        ;;
    -h | --help)
        show_help
        ;;
    *)
        break
        ;;
    esac
done

# Check if package name is provided
if [ "$#" -lt 1 ]; then
    show_help
fi

verify_package "$1" "$2"

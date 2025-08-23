
test_colored_welcome_message() {
    # Capture the output of the script
    output=$(bash install.sh 2>&1)
    
    # Check if ANSI escape codes for colors are present
    echo "$output" | grep -q "\033\[1;92m" && \
    echo "$output" | grep -q "\033\[1;93m" && \
    echo "$output" | grep -q "\033\[1;97m" && \
    echo "$output" | grep -q "\033\[1;96m"
    
    if [ $? -eq 0 ]; then
        echo "PASS: Colored welcome message displays with proper ANSI escape codes"
        return 0
    else
        echo "FAIL: ANSI escape codes not found in output"
        return 1
    fi
}

test_successful_installation_with_dependencies() {
    # Mock successful dependency installation
    apt() {
        return 0
    }
    gem() {
        return 0
    }
    export -f apt gem
    
    # Mock file operations
    mkdir -p /tmp/test_prefix/etc/bash
    echo "mock bashrc" > /tmp/test_prefix/etc/bash.bashrc
    
    # Set PREFIX environment variable
    export PREFIX="/tmp/test_prefix"
    
    # Capture output and exit code
    output=$(bash install.sh 2>&1)
    exit_code=$?
    
    # Check for successful installation indicators
    echo "$output" | grep -q "Installing termux Parrot shell" && \
    echo "$output" | grep -q "Installing packages" && \
    echo "$output" | grep -q "Done" && \
    echo "$output" | grep -q "Now type 'exit' & restart Termux"
    
    if [ $? -eq 0 ] && [ $exit_code -eq 0 ]; then
        echo "PASS: Successfully installs termux parrot shell with all dependencies"
        rm -rf /tmp/test_prefix
        return 0
    else
        echo "FAIL: Installation failed or missing expected output"
        rm -rf /tmp/test_prefix
        return 1
    fi
}

test_graceful_failure_on_apt_update_failure() {
    # Mock apt update to fail
    apt() {
        if [ "$1" = "update" ]; then
            return 1
        fi
        return 0
    }
    export -f apt
    
    # Set PREFIX environment variable
    export PREFIX="/tmp/test_prefix"
    mkdir -p /tmp/test_prefix/etc/bash
    
    # Capture output and exit code
    output=$(bash install.sh 2>&1)
    exit_code=$?
    
    # Check that the script handles the failure gracefully
    # Should not crash and should provide some indication of the failure
    if [ $exit_code -ne 0 ] || echo "$output" | grep -q -i "error\|fail"; then
        echo "PASS: Script handles apt update failure gracefully"
        rm -rf /tmp/test_prefix
        return 0
    else
        echo "FAIL: Script did not handle apt update failure properly"
        rm -rf /tmp/test_prefix
        return 1
    fi
}

test_ruby_installation_before_gem() {
    # Track the order of command execution
    execution_order=""
    
    # Mock apt to track ruby installation
    apt() {
        if [ "$*" = "install ruby -y" ]; then
            execution_order="${execution_order}ruby_install;"
        elif [ "$1" = "update" ]; then
            execution_order="${execution_order}apt_update;"
        fi
        return 0
    }
    
    # Mock gem to track gem installation
    gem() {
        if [ "$*" = "install lolcat" ]; then
            execution_order="${execution_order}gem_install;"
        fi
        return 0
    }
    
    export -f apt gem
    
    # Set up test environment
    export PREFIX="/tmp/test_prefix"
    mkdir -p /tmp/test_prefix/etc/bash
    echo "mock bashrc" > /tmp/test_prefix/etc/bash.bashrc
    
    # Execute the script
    bash install.sh >/dev/null 2>&1
    
    # Verify ruby installation happens before gem installation
    if echo "$execution_order" | grep -q "ruby_install.*gem_install"; then
        echo "PASS: Ruby installation completes before gem installation"
        rm -rf /tmp/test_prefix
        return 0
    else
        echo "FAIL: Ruby installation does not precede gem installation. Order: $execution_order"
        rm -rf /tmp/test_prefix
        return 1
    fi
}

test_lolcat_gem_installation_after_ruby() {
    # Mock successful ruby installation
    apt() {
        if [ "$1" = "install" ] && [ "$2" = "ruby" ]; then
            return 0
        fi
        return 0
    }
    
    # Mock gem command to track lolcat installation
    gem_calls=""
    gem() {
        if [ "$1" = "install" ] && [ "$2" = "lolcat" ]; then
            gem_calls="$gem_calls lolcat"
            return 0
        fi
        return 0
    }
    export -f apt gem
    
    # Set PREFIX environment variable
    export PREFIX="/tmp/test_prefix"
    mkdir -p /tmp/test_prefix/etc/bash
    echo "mock bashrc" > /tmp/test_prefix/etc/bash.bashrc
    
    # Capture output
    output=$(bash install.sh 2>&1)
    exit_code=$?
    
    # Check if lolcat gem was installed
    if echo "$gem_calls" | grep -q "lolcat" && [ $exit_code -eq 0 ]; then
        echo "PASS: lolcat gem installed successfully after ruby"
        rm -rf /tmp/test_prefix
        return 0
    else
        echo "FAIL: lolcat gem installation failed or was not attempted"
        rm -rf /tmp/test_prefix
        return 1
    fi
}

test_creates_backup_of_existing_bash_configuration() {
    # Set up test environment
    export PREFIX="/tmp/test_prefix"
    mkdir -p /tmp/test_prefix/etc/bash
    
    # Create existing bash configuration file
    echo "original bashrc content" > /tmp/test_prefix/etc/bash.bashrc
    
    # Mock apt and gem commands to avoid actual installations
    apt() {
        return 0
    }
    gem() {
        return 0
    }
    export -f apt gem
    
    # Execute the script
    bash install.sh >/dev/null 2>&1
    
    # Check if backup was created and original content preserved
    if [ -f "/tmp/test_prefix/etc/bash.bashrc" ] && [ -f "/tmp/test_prefix/etc/bash.bashrc.bak" ]; then
        backup_content=$(cat /tmp/test_prefix/etc/bash.bashrc.bak 2>/dev/null)
        if [ "$backup_content" = "original bashrc content" ]; then
            echo "PASS: Backup of existing bash configuration created successfully"
            rm -rf /tmp/test_prefix
            return 0
        fi
    fi
    
    echo "FAIL: Backup of existing bash configuration not created or content mismatch"
    rm -rf /tmp/test_prefix
    return 1
}

test_bash_configuration_copy_to_prefix_directory() {
    # Set up test environment with PREFIX directory
    export PREFIX="/tmp/test_prefix"
    mkdir -p "$PREFIX/etc"
    
    # Create a mock source bash.bashrc file
    mkdir -p /tmp/mock_source
    echo "original bashrc content" > /tmp/mock_source/bash.bashrc
    
    # Mock the cp command to track file operations
    copy_operations=""
    cp() {
        copy_operations="$copy_operations$1->$2;"
        # Actually perform the copy for verification
        command cp "$@"
        return $?
    }
    export -f cp
    
    # Create the bash.bashrc file that the script expects to copy
    echo "new parrot shell config" > bash.bashrc
    
    # Execute the script
    bash install.sh >/dev/null 2>&1
    
    # Verify the bash configuration was copied to the correct PREFIX directory
    if [ -f "$PREFIX/etc/bash.bashrc" ] && \
       echo "$copy_operations" | grep -q "bash.bashrc->$PREFIX/etc" && \
       grep -q "new parrot shell config" "$PREFIX/etc/bash.bashrc"; then
        echo "PASS: Bash configuration copied to correct PREFIX directory"
        rm -rf /tmp/test_prefix /tmp/mock_source bash.bashrc
        return 0
    else
        echo "FAIL: Bash configuration not copied to PREFIX directory correctly. Operations: $copy_operations"
        rm -rf /tmp/test_prefix /tmp/mock_source bash.bashrc
        return 1
    fi
}

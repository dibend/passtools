#!/bin/bash
set -eo pipefail # Exit on error, and ensure pipe failures are caught

# --- Configuration ---
PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
SCRIPT_RUN_DATE=$(date) # Using current date

# --- Helper Functions ---
print_info() {
    echo "INFO: $1"
}

print_success() {
    echo "SUCCESS: $1"
}

print_warning() {
    echo "WARNING: $1"
}

print_error() {
    echo "ERROR: $1" >&2
}

prompt_yes_no() {
    local prompt_message="$1"
    local default_choice="${2:-Y}" # Default to Yes
    local choice
    
    while true; do
        read -r -p "$prompt_message [$default_choice/n]: " choice
        choice="${choice:-$default_choice}"
        case "$choice" in
            [Yy]* ) return 0;; # Yes
            [Nn]* ) return 1;; # No
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
}

# --- Check Dependencies ---
print_info "Checking for required tools (gpg, pass, git)..."
if ! command -v gpg >/dev/null 2>&1; then
    print_error "GnuPG (gpg) is not installed. Please install it first (e.g., 'sudo apt install gnupg'). Aborting."
    exit 1
fi
if ! command -v pass >/dev/null 2>&1; then
    print_error "pass (password-store) is not installed. Please install it first (e.g., 'sudo apt install pass'). Aborting."
    exit 1
fi
if ! command -v git >/dev/null 2>&1; then
    print_warning "git is not installed. 'pass git' features for syncing/versioning will not be available unless git is installed (e.g., 'sudo apt install git')."
fi
print_success "Required tools (gpg, pass) found."
echo ""

# --- GPG Key Handling ---
PREFERRED_GPG_ID=""
GPG_USER_NAME=""
GPG_USER_EMAIL=""
GPG_UID_INFO="" # For the user-facing GPG key display

print_info "Checking for existing GPG keys..."
SECRET_KEYS_INFO=()
while IFS= read -r line; do
    SECRET_KEYS_INFO+=("$line")
done < <(gpg --list-secret-keys --with-colons --keyid-format LONG | awk -F: '
    BEGIN { ORS = "" } # Combine lines for each key
    /^sec:/ {
        if (current_key_info) print current_key_info "\n";
        keyid=substr($5, length($5)-15); 
        current_key_info = keyid;
    } 
    /^uid:/ {
        # Extract UID, try to get the primary one if multiple for a key
        if (current_key_info && current_key_info !~ /\(/) { # Only add UID if not already added for this key
            uid_text = $10;
            gsub(/^:+|:+$/, "", uid_text); # Clean leading/trailing colons if any
            current_key_info = current_key_info " (" uid_text ")";
        }
    }
    END { if (current_key_info) print current_key_info "\n" }' | grep .) # Ensure non-empty lines

if [ "${#SECRET_KEYS_INFO[@]}" -eq 0 ]; then
    print_warning "No GPG secret keys found."
    if prompt_yes_no "Would you like to generate a new GPG key now?" "Y"; then
        print_info "Starting GPG key generation. Please follow the prompts from GPG."
        print_info "We recommend: RSA and RSA key type, 4096 bits length, and a strong passphrase."
        gpg --full-generate-key
        
        # Re-fetch keys
        SECRET_KEYS_INFO=()
        while IFS= read -r line; do
            SECRET_KEYS_INFO+=("$line")
        done < <(gpg --list-secret-keys --with-colons --keyid-format LONG | awk -F: '
            BEGIN { ORS = "" } 
            /^sec:/ {
                if (current_key_info) print current_key_info "\n";
                keyid=substr($5, length($5)-15); 
                current_key_info = keyid;
            } 
            /^uid:/ {
                if (current_key_info && current_key_info !~ /\(/) {
                    uid_text = $10;
                    gsub(/^:+|:+$/, "", uid_text);
                    current_key_info = current_key_info " (" uid_text ")";
                }
            }
            END { if (current_key_info) print current_key_info "\n" }' | grep .)

        if [ "${#SECRET_KEYS_INFO[@]}" -eq 0 ]; then
            print_error "GPG key generation was not completed or no key was created. Aborting."
            exit 1
        fi
        print_success "New GPG key generated."
    else
        print_error "GPG key is required for pass. Please generate one manually and re-run. Aborting."
        exit 1
    fi
fi

if [ "${#SECRET_KEYS_INFO[@]}" -eq 1 ]; then
    PREFERRED_GPG_ID=$(echo "${SECRET_KEYS_INFO[0]}" | awk '{print $1}')
    GPG_UID_INFO=$(echo "${SECRET_KEYS_INFO[0]}" | sed -e 's/^[^(]*(\(.*\))$/\1/' -e 's/^[^ ]* *//') # Get full UID part
    print_info "Using the only available GPG key: $PREFERRED_GPG_ID $GPG_UID_INFO"
else
    print_info "Multiple GPG keys found. Please choose one to use with 'pass':"
    for i in "${!SECRET_KEYS_INFO[@]}"; do
        echo "$((i+1))) ${SECRET_KEYS_INFO[$i]}"
    done
    
    key_choice_index=-1
    while true; do
        read -r -p "Enter the number of the key to use: " key_choice
        if [[ "$key_choice" =~ ^[0-9]+$ ]] && [ "$key_choice" -ge 1 ] && [ "$key_choice" -le "${#SECRET_KEYS_INFO[@]}" ]; then
            key_choice_index=$((key_choice-1))
            break
        else
            echo "Invalid choice. Please enter a number from the list."
        fi
    done
    PREFERRED_GPG_ID=$(echo "${SECRET_KEYS_INFO[$key_choice_index]}" | awk '{print $1}')
    GPG_UID_INFO=$(echo "${SECRET_KEYS_INFO[$key_choice_index]}" | sed -e 's/^[^(]*(\(.*\))$/\1/' -e 's/^[^ ]* *//')
    print_info "You selected GPG key: $PREFERRED_GPG_ID $GPG_UID_INFO"
fi

GPG_USER_NAME=$(gpg --list-keys "$PREFERRED_GPG_ID" | awk -F '[<>()]' '/^uid/ {gsub(/^ +| +$/, "", $2); print $2; exit}')
GPG_USER_EMAIL=$(gpg --list-keys "$PREFERRED_GPG_ID" | awk -F '[<>()]' '/^uid/ {gsub(/^ +| +$/, "", $3); print $3; exit}')

echo ""

# --- Initialize pass ---
print_info "Checking password store initialization..."
NEEDS_PASS_INIT=true
STORE_INITIALIZED_MSG=""
if [ -d "$PASSWORD_STORE_DIR" ]; then
    if [ -f "$PASSWORD_STORE_DIR/.gpg-id" ]; then
        CURRENT_STORE_GPG_ID=$(cat "$PASSWORD_STORE_DIR/.gpg-id")
        if [ "$CURRENT_STORE_GPG_ID" == "$PREFERRED_GPG_ID" ]; then
            print_success "Password store is already initialized with GPG ID: $PREFERRED_GPG_ID"
            STORE_INITIALIZED_MSG="Password store at $PASSWORD_STORE_DIR was already configured with your selected GPG ID."
            NEEDS_PASS_INIT=false
        else
            print_warning "Password store is initialized with a different GPG ID ($CURRENT_STORE_GPG_ID)."
            if prompt_yes_no "Re-initialize with $PREFERRED_GPG_ID? This will attempt to re-encrypt existing passwords (requires old key's passphrase)." "Y"; then
                NEEDS_PASS_INIT=true
            else
                print_info "Skipping pass initialization. Manual re-initialization may be needed."
                NEEDS_PASS_INIT=false 
            fi
        fi
    else
        print_warning "Password store directory '$PASSWORD_STORE_DIR' exists but '.gpg-id' file is missing."
        NEEDS_PASS_INIT=true 
    fi
else
    print_info "Password store directory '$PASSWORD_STORE_DIR' does not exist."
    NEEDS_PASS_INIT=true 
fi

if [ "$NEEDS_PASS_INIT" = true ]; then
    print_info "Initializing password store for GPG ID: $PREFERRED_GPG_ID..."
    if pass init "$PREFERRED_GPG_ID"; then
        print_success "Password store initialized successfully at $PASSWORD_STORE_DIR."
        STORE_INITIALIZED_MSG="Password store was successfully initialized at $PASSWORD_STORE_DIR using GPG ID $PREFERRED_GPG_ID."
    else
        print_error "Failed to initialize password store. Please check GPG prompts or errors. Aborting."
        exit 1
    fi
fi
echo ""

# --- Git Initialization for pass ---
GIT_INITIALIZED_MSG="Git was not initialized for the password store by this script."
GIT_AVAILABLE=$(command -v git)
if [ -n "$GIT_AVAILABLE" ] && [ -d "$PASSWORD_STORE_DIR" ]; then
    if prompt_yes_no "Do you want to initialize the password store with git for version control and syncing?" "Y"; then
        if [ -d "$PASSWORD_STORE_DIR/.git" ]; then
            print_info "Password store is already a git repository."
            GIT_INITIALIZED_MSG="Password store at $PASSWORD_STORE_DIR was already a git repository."
        else
            print_info "Initializing git repository in $PASSWORD_STORE_DIR..."
            if pass git init; then
                print_success "Git repository initialized for password store."
                GIT_INITIALIZED_MSG="Password store at $PASSWORD_STORE_DIR was initialized as a git repository."
                
                if [ -n "$GPG_USER_NAME" ] && [ -n "$GPG_USER_EMAIL" ]; then
                    if (cd "$PASSWORD_STORE_DIR" && git config --local user.name "$GPG_USER_NAME" && git config --local user.email "$GPG_USER_EMAIL" >/dev/null 2>&1); then
                        print_info "Set git user.name and user.email for this password store repo (from GPG key)."
                    fi
                fi
                print_info "Consider setting up a remote git repository for backup/sync: "
                print_info "  cd \"$PASSWORD_STORE_DIR\""
                print_info "  git remote add origin <your-remote-repo-url>"
                print_info "  pass git push -u origin master  (or main)"
            else
                print_error "Failed to initialize git for password store."
            fi
        fi
    else
        print_info "Skipping git initialization for password store."
    fi
elif [ -z "$GIT_AVAILABLE" ]; then
    print_info "git command not found, skipping git initialization for password store."
fi
echo ""

# --- Clipboard Tool Check ---
CLIP_TOOL_NOTE=""
if command -v wl-copy >/dev/null 2>&1 && [ -n "$WAYLAND_DISPLAY" ]; then
    CLIP_TOOL_NOTE="('wl-copy' detected, should work)"
elif command -v xclip >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
    CLIP_TOOL_NOTE="('xclip' detected, should work)"
elif command -v pbcopy >/dev/null 2>&1; then
    CLIP_TOOL_NOTE="('pbcopy' detected, should work)"
else
    CLIP_TOOL_NOTE="(No common clipboard tool like xclip or wl-copy detected. Install one for '-c' to work, e.g., 'sudo apt install xclip')"
fi


# --- Output Focused Guide ---
cat << EOF

---------------------------------------------------------------------
     'pass' (Password Store) - Quick Guide to Managing Passwords    
---------------------------------------------------------------------
Script run on: $SCRIPT_RUN_DATE
Setup Summary:
* GPG Key for encryption: $PREFERRED_GPG_ID $GPG_UID_INFO
* Password Store Location: $PASSWORD_STORE_DIR
* Git Integration: $GIT_INITIALIZED_MSG
---------------------------------------------------------------------

This guide focuses on the basics: generating, storing, and accessing your passwords.

1. Storing a New Password:
   Use 'pass insert' followed by a descriptive path for your password.
   'pass' will then prompt you to type the password.
   Example: pass insert websites/mybank.com/username

   Passwords are organized in a folder-like structure using slashes '/'.
   For example, 'services/email/personal' or 'wifi/home_network'.

2. Storing Multi-line Information (e.g., password + notes):
   Use the '-m' flag with 'pass insert'.
   Example: pass insert -m websites/myservice/info
   (Enter your password on the first line, notes on subsequent lines. Press Ctrl+D on an empty line to finish.)

3. Generating a Secure Password (and Storing It):
   Let 'pass' create a strong, random password for you.
   Syntax: pass generate path/to/password <length_of_password>
   Example: pass generate streaming/netflix_account 24
   This generates a 24-character password, stores it, and prints it once.

4. Accessing (Showing) a Stored Password:
   Simply type 'pass' followed by the path to the password.
   Example: pass websites/mybank.com/username

5. Accessing (Copying) a Password to Clipboard:
   Use the '-c' flag to copy the password to your clipboard.
   It will automatically be cleared from the clipboard after a short period (usually 45 seconds).
   Example: pass -c websites/mybank.com/username $CLIP_TOOL_NOTE

6. Listing Your Stored Passwords:
   To see a tree view of all your stored password entries:
   pass
   (You can also use 'pass ls')

7. Finding a Password (by its path):
   If you remember part of the password's path/name:
   Example: pass find mybank

---------------------------------------------------------------------
Remember to back up your GPG keys securely and, if using git, your password store repository.
For more commands and options, type 'man pass'.
---------------------------------------------------------------------
Setup script finished.
EOF

exit 0

#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# Determine package manager
if command -v dpkg &>/dev/null; then
  PKG_MANAGER="deb"
elif command -v rpm &>/dev/null; then
  PKG_MANAGER="rpm"
else
  echo "Unsupported package manager. Exiting."
  exit 1
fi

# Function to check if a package is installed
check_package() {
  local pkg="$1"
  if [ "$PKG_MANAGER" == "deb" ]; then
    dpkg -s "$pkg" >/dev/null 2>&1
  elif [ "$PKG_MANAGER" == "rpm" ]; then
    rpm -q "$pkg" >/dev/null 2>&1
  fi
}

# Check required packages
for pkg in openssh-server pam gcc; do
  if ! check_package "$pkg"; then
    echo -e "\e[31m$pkg is not installed. Exiting.\e[0m"
    exit 1
  fi
done

# Create backup directory
BACKUP_DIR="/var/backups/ssh_approval"
mkdir -p "$BACKUP_DIR"

# Backup configuration files
cp /etc/pam.d/sshd "$BACKUP_DIR/sshd.bak"
cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.bak"

read -p "Enter the user to notify (default: $(whoami)): " NOTIFY_USER
NOTIFY_USER=${NOTIFY_USER:-$(whoami)}



cat <<EOF > /usr/local/bin/ssh-approval.sh
#!/bin/bash

TARGET_USER="special"
NOTIFY_USER="${NOTIFY_USER}"

PAM_HOST="\$PAM_RHOST"

echo -e "\n\nAccess request for user \$PAM_USER from \$PAM_RHOST" > /dev/pts/0

if [ "\$PAM_USER" != "\$TARGET_USER" ]; then
    exit 0
fi

timeout 10s /usr/local/bin/user_tty "\$NOTIFY_USER" "\$PAM_HOST"
exit_status=\$?

if [ \$exit_status -eq 0 ]; then
    echo "Access approved for \$PAM_USER"
    exit 0
elif [ \$exit_status -eq 124 ]; then
    echo "Access denied for \$PAM_USER: no response within timeout"
    exit 1
else
    echo "Access denied for \$PAM_USER"
    exit 1
fi
EOF

chmod +x /usr/local/bin/ssh-approval.sh

# Verify and update /etc/ssh/sshd_config
SSHD_CONFIG="/etc/ssh/sshd_config"

if grep -q "^#UsePAM yes" "$SSHD_CONFIG"; then
  sed -i 's/^#UsePAM yes/UsePAM yes/' "$SSHD_CONFIG"
elif ! grep -q "^UsePAM yes" "$SSHD_CONFIG"; then
  echo "UsePAM yes" >> "$SSHD_CONFIG"
fi

if grep -q "^#PermitEmptyPasswords yes" "$SSHD_CONFIG"; then
  sed -i 's/^#PermitEmptyPasswords yes/PermitEmptyPasswords yes/' "$SSHD_CONFIG"
elif ! grep -q "^PermitEmptyPasswords yes" "$SSHD_CONFIG"; then
  echo "PermitEmptyPasswords yes" >> "$SSHD_CONFIG"
fi

# Add user 'special' and remove its password
if ! id "special" &>/dev/null; then
  useradd special
fi

passwd -d special

# Append Match block to the end of the sshd_config file
cat <<EOF >> "$SSHD_CONFIG"

Match User special
    PasswordAuthentication yes
    PubkeyAuthentication no
EOF

# Add pam_exec configuration to /etc/pam.d/sshd
PAM_SSHD_CONFIG="/etc/pam.d/sshd"
if ! grep -q "^auth required pam_exec.so /usr/local/bin/ssh-approval.sh" "$PAM_SSHD_CONFIG"; then
  echo "auth required pam_exec.so /usr/local/bin/ssh-approval.sh" >> "$PAM_SSHD_CONFIG"
fi

# Compile the user_tty program
cat <<EOF > /tmp/user_tty.c
#include <stdio.h>
#include <stdlib.h>
#include <utmp.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <termios.h>

#define TTY_PATH "/dev/"

int get_first_user_tty(const char* user, char* tty, size_t tty_size) {
    struct utmp* entry;
    setutent();  // Rewind the utmp file

    while ((entry = getutent()) != NULL) {
        if (entry->ut_type == USER_PROCESS) {
            if (strcmp(entry->ut_user, user) == 0) {
                snprintf(tty, tty_size, "%s%s", TTY_PATH, entry->ut_line);
                endutent();  // Close the utmp file
                return 0;  // Success
            }
        }
    }

    endutent();  // Close the utmp file
    return -1;  // User tty not found
}

int main(int argc, char* argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <username> <hostname>\n", argv[0]);
        return 1;
    }

    const char* user = argv[1];
    const char* host = argv[2];
    char tty[256];

    if (get_first_user_tty(user, tty, sizeof(tty)) == -1) {
        fprintf(stderr, "No tty found for user %s\n", user);
        return 1;
    }

    printf("First TTY for user %s: %s\n", user, tty);

    // Open the tty for writing
    int tty_fd = open(tty, O_RDWR);
    if (tty_fd == -1) {
        perror("Failed to open tty");
        return 1;
    }

    // Send the request to the user
    dprintf(tty_fd, "Approve this login attempt? (y/n): ");

    // Read the response
    char response;
    if (read(tty_fd, &response, 1) != 1) {
        perror("Failed to read response");
        close(tty_fd);
        return 1;
    }

    // Close the tty
    close(tty_fd);

    // Process the response
    if (response == 'y' || response == 'Y') {
        printf("Access approved for %s\n", user);
        return 0;
    } else {
        printf("Access denied for %s\n", user);
        return 1;
    }
}
EOF

gcc /tmp/user_tty.c -o /usr/local/bin/user_tty
chmod +x /usr/local/bin/user_tty
rm /tmp/user_tty.c

# Restart SSH service to apply changes
systemctl restart sshd

# Operation completed message
echo -e "\e[32mOperation completed successfully. A backup of the configuration files is available at $BACKUP_DIR.\e[0m"

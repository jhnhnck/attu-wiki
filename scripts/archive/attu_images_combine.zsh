#!/usr/bin/zsh

# Check if the year is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <year>"
  exit 1
fi

YEAR="$1"
BACKUP_DIR="/srv/backups/attu-wiki"
TEMP_DIR=$(mktemp -d)

# Navigate to the backup directory
cd "$BACKUP_DIR" || { echo "Failed to cd to $BACKUP_DIR"; exit 1; }

# Copy all archives for the specified year to the temp directory
cp "attu-images-backup_${YEAR}-"*.tar.bz2 "$TEMP_DIR" || { echo "No archives found for year $YEAR"; exit 1; }

# Extract all archives in the temp directory
cd "$TEMP_DIR" || { echo "Failed to cd to $TEMP_DIR"; exit 1; }
for archive in *.tar.bz2; do
  tar --keep-newer-files -xvf "$archive" || { echo "Failed to extract $archive"; exit 1; }
done

# Create a new combined archive
if [ -d "images" ]; then
  tar cjvf "attu-images-backup_${YEAR}.tar.bz2" "images" || { echo "Failed to create combined archive"; exit 1; }
else
  echo "No 'images' directory found after extraction."
  exit 1
fi

# Move the new archive back to the backup directory
mv "attu-images-backup_${YEAR}.tar.bz2" "$BACKUP_DIR" || { echo "Failed to move archive to $BACKUP_DIR"; exit 1; }

# Clean up old archives for the specified year
cd "$BACKUP_DIR" || { echo "Failed to cd to $BACKUP_DIR"; exit 1; }
rm -v "attu-images-backup_${YEAR}-"*.tar.bz2 || { echo "Failed to remove old archives"; exit 1; }

# Clean up the temp directory
rm -rf "$TEMP_DIR" || { echo "Failed to clean up temp directory"; exit 1; }

echo "Backup process completed successfully."

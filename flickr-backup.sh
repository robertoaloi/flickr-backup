#!/usr/bin/env bash

################################################################################
# Config
################################################################################

# Directory where logs will be stored.
# It will be created if it does not exist.
logdir="$HOME/.flickrbackup"

################################################################################
# Usage
################################################################################

function usage {
  echo -e "Usage: $0 DIRECTORY ALBUM"
}

################################################################################
# Global Variables
################################################################################

PHOTO_ID=
PHOTOSET_ID=
TO_ADD=

################################################################################
# Counters
################################################################################

PHOTOS_SKIPPED=0
PHOTOS_UPLOADED=0
PHOTOS_ERROR=0
PHOTOS_DUPLICATED=0

################################################################################
# Flickcurl Wrappers
################################################################################

# Given a name, creates a new photoset, using PHOTO_ID as a primary photo id.
# Sets PHOTOSET_ID with the id of the created photoset.
function photoset_create {

  # Handle function arguments
  photoset_name=$1

  # Hard-coded description for the photoset for now
  desc="This set is automatically generated"

  # Create a photoset from a primary photo
  res=$(flickcurl -q photosets.create "$photoset_name" "$desc" "$PHOTO_ID")

  # Extract and return PHOTOSET_ID
  PHOTOSET_ID=$(echo "$res" | cut -d' ' -f 3)

  # Log event
  log "Create photoset: $PHOTOSET_ID from primary: $PHOTO_ID"

}

# Adds PHOTO_ID to PHOTOSET_ID
function photoset_add {

  # Add photo to photoset
  flickcurl -q photosets.addPhoto "$PHOTOSET_ID" "$PHOTO_ID"
  if [ $? == 0 ]; then
    # Log event
    log "Add photo: $PHOTO_ID to photoset: $PHOTOSET_ID"
  else
    log "Error adding photo: $PHOTO_ID to photoset: $PHOTOSET_ID"
    # The Flickr API is flaky. Retry one more time.
    flickcurl -q photosets.addPhoto "$PHOTOSET_ID" "$PHOTO_ID"
    if [ $? == 0 ]; then
      # Log event
      log "[Retry #1] Add photo: $PHOTO_ID to photoset: $PHOTOSET_ID"
    else
      log "[Retry #1] Error adding photo: $PHOTO_ID to photoset: $PHOTOSET_ID"
      log "[Retry #1] Giving up."
    fi
  fi

}

# Echoes how many photos are contained in PHOTOSET_ID
function photoset_size {

  # Retrieve list of photos from photoset
  res=$(flickcurl photosets.getPhotos "$PHOTOSET_ID")

  # Extract and return total number of photos from result
  n=$(echo "$res"| head -2 | tail -1 | cut -d' ' -f 8 | rev | cut -c 2- | rev)
  echo "$n"

}

# Looks for a photo by SHA1. If a match exists, sets PHOTO_ID to the id of the
# matching photo. If no match is found, unsets PHOTO_ID.
function photo_lookup {

  # Handle function arguments
  tags=$1

  # Only search among user's own photos
  user="me"

  # Search photos by tags and check whether at least one entry is found
  res=$(flickcurl -q photos.search user "$user" tags "$tags")
  found=$(echo "$res" | grep -m 1 ID)

  # If a match is found, return the matching id
  if [ "$?" == "0" ]; then
    PHOTO_ID=$(echo "$found" | cut -d' ' -f6)
    log "Found matching tags: $tags (photo: $PHOTO_ID)"
  else
    PHOTO_ID=
  fi

}

# Uploads a photo and sets PHOTO_ID to the id of the created photo
function photo_upload {

  # Handle function arguments
  file=$1
  tags=$2

  # Upload photo to Flickr
  res=$(flickcurl -q upload "$file" hidden hidden tags "$tags" 2>&1)

  if [ "$?" == "0" ]; then
    PHOTO_ID=$(echo $res | rev | cut -d' ' -f1 | rev)
    log "Upload photo: $PHOTO_ID with tags: $tags"
  else
    PHOTO_ID=
    log "Upload error: $res"
  fi

}

################################################################################
# Helpers
################################################################################

function line {
  echo "================================================================"
}

function progress {
  echo -n "."
}

function skip {
  echo -n "x"
}

function duplicate {
  echo -n "D"
}

function error {
  echo -n "E"
}

function timestamp {
  echo -n "$(date +%s)"
}

function datetime {
  echo -n "$(date +%F-%T)"
}

function result {

  msg=$1
  result=$2

  log "$(line)"
  log "$msg"
  log "$(line)"

  tail -n 10 "$logfile"
  echo "Complete logs are available at: $logfile"

  exit "$result"

}

function sha1 {

  # Handle function arguments
  filename=$1

  sha=$(sha1sum "$filename" | cut -d' ' -f1)
  log "SHA1 for: $filename is: $sha"
  echo "$sha"
}

function require_program {

  # Handle function arguments
  program=$1
  url=$2

  # Exit if a required program is missing
  command -v "$program" > /dev/null 2>&1 || {
    echo "Program $program is required. More info at: $url" >&2
    exit 1
  }

}

function photo_upload_nodup {

  # Handle function arguments
  file=$1

  extension="${file##*.}"
  if [ "$extension" == "HEIC" ]; then
    heic_to_jpg $file;
    file="$file.jpg"
  fi

  # Each photo is tagged with its own SHA1
  tags=$(sha1 "$file")

  # Prevent local duplicates
  sha_lookup "$tags"
  if [ "$?" != "0" ]; then
    # Prevent remote duplicates
    photo_lookup "$tags"
    if [ -z "$PHOTO_ID" ]; then
      photo_upload "$file" "$tags"
      if [ -z "$PHOTO_ID" ]; then
	  error
	  PHOTOS_ERROR=$((PHOTOS_ERROR+1))
	  TO_ADD=
      else
          progress
          PHOTOS_UPLOADED=$((PHOTOS_UPLOADED+1))
	  TO_ADD=1
      fi
    else
      skip
      PHOTOS_SKIPPED=$((PHOTOS_SKIPPED+1))
      TO_ADD=1
    fi
    sha_write "$tags"
  else
    log "Trying to upload duplicated file: $file. Skipping."
    duplicate
    PHOTOS_DUPLICATED=$((PHOTOS_DUPLICATED+1))
    TO_ADD=
  fi

  if [ "$extension" == "HEIC" ]; then
    log "Removing converted file $file"
    rm "$file"
  fi

}

function heic_to_jpg {
  src=$1
  tgt="$1.jpg"
  log "Converting $src to $tgt."
  magick convert "$src" "$tgt"
}

function log_init {
  mkdir -p "$logdir"
  logfile="$logdir/$(datetime)"
  echo "$logfile"
}

function log {
  text=$*
  prefix=$(datetime)
  echo "[$prefix] $text" >> "$logfile"
}

function sha_write {
  sha=$1
  echo "$sha" >> "$logfile.sha"
}

function sha_lookup {
  sha=$1
  grep -q -s -w "$sha" "$logfile.sha"
}

################################################################################
# Main
################################################################################

# Verify requirements are met
require_program "flickcurl" "http://librdf.org/flickcurl"

# The script requires exactly two arguments
if [ "$#" != "2" ]; then
  usage
  exit 1
fi

# Handle script arguments
directory=$1
album=$2

# Initialize logging
logfile=$(log_init)

# Log script name and arguments
log "$(line)"
log "$0 $*"
log "$(line)"

# Retrieve the list of files to backup
files=($directory/*)
num_files="${#files[@]}"
log "Found $num_files file(s) in directory: $directory"
log "$(line)"

# To create an album, we require at least one photo
primary="${files:0}"
log "Select primary photo: $primary"
photo_upload_nodup "$primary"

# Create the album
photoset_create "$album"

# Upload the rest of the photos
for f in "${files[@]:1}"; do
  log "$(line)"
  log "Select photo: $f"
  photo_upload_nodup "$f"
  if ! [ -z $TO_ADD ]; then
    photoset_add "$PHOTOSET_ID" "$PHOTO_ID"
  fi
done

# Log summary
log "$(line)"
log "Uploaded $PHOTOS_UPLOADED photos"
log "Skipped $PHOTOS_SKIPPED photos (already uploaded)"
log "Skipped $PHOTOS_DUPLICATED photos (local duplicates)"
log "Failed uploading $PHOTOS_ERROR photos"
num_photos=$(photoset_size)
log "Photoset: $PHOTOSET_ID contains $num_photos photos"
if [ "$num_files" == $(($num_photos-$PHOTOS_DUPLICATED)) ]; then
  log "Photoset verification succeeded: $num_files files == $num_photos photos"
  result "OK" 0
else
  log "Photoset verification failed: $num_files files VS $num_photos photos"
  result "ERROR" 1
fi

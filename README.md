# flickr-backup

A Bash script built on top of the flickcurl[1] library to ease backup
of entire directories of photos as Flickr[2] photosets.

To prevent duplicates, each photo is tagged with its own SHA1 during
upload and a check is performed before every upload to avoid storing
the same photo multiple times on Flickr. This allows the user to save
bandwidth, storage and time.

This simple approach makes interrupting and resuming an upload job
a cheap operation and it provides what can be defined as a basic 'sync'
operation between a directory on the file system and a photoset on
Flickr.

All operations performed by `flickr-backup` are logged to disk for
reference.

## Usage

````
./flickr-backup.sh DIRECTORY ALBUM
````

Upload all photos contained in DIRECTORY to the ALBUM photoset on
Flickr. A new photoset is created every time the command is invoked,
but only photos which are not already available on Flickr are
uploaded, whilst the existing ones are simply added to the new photoset.

The script outputs a `.` (dot) for each uploaded photo and a `x` for
each skipped photo (when a duplicate is detected).

Detailed logs are available for each upload job. The default logs
location is set to `~/.flickrbackup`.

## Dependencies

The script requires the flickcurl[1] library. On Mac, you can install
it via _homebrew_[3]:

````
brew install flickcurl
````

## References

[1] http://librdf.org/flickcurl/
[2] http://flickr.com/
[3] http://brew.sh/

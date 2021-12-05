# DNS Zone Files for bremen.freifunk.net and ffhb.de

## Editing Zone Files
If you make changes to any zone file, you must change the `Serial` value (at the top of the file) to a higher value, so that the changes will actually be used.
Use the current date followed followed by `01` (or a higher number) as the new serial number.

Also, please use tabs (instead of spaces) for consistent formatting.

## Applying Changes
To actually activate any changes, someone with admin access needs to
* make sure the changes are contained in the "dns" repository on the internal Git server
* log in on the DNS server and run `update-dns-zones.sh` to pull and activate the latest Git repository changes.

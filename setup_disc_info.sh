#!/bin/bash

FILE="/opt/xcat/lib/perl/xCAT/data/discinfo.pm"
BACKUP="${FILE}.orig"

echo "==> Backing up original file..."
cp -n "$FILE" "$BACKUP"

echo "==> Injecting rocky9.6 discinfo entry..."

sed -i '/"1699827798\.672747" *=> *"rocky9\.3"/i\    "1748309243.9338255" => "rocky9.6",      #x86_64' "$FILE"

echo "==> Showing updated section:"
grep -n 'rocky9' "$FILE"


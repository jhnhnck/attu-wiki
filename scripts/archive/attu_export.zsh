#!/usr/bin/zsh

date="$(date +%Y)-$1"

if [[ "${#1}" -gt 5 ]]; then
  date="$1"
fi

printf 'Date is %s\n' "$date"

backup_dir="/srv/attu/db_backup"
transfer_dir="/home/jhnhnck/attu-backups"

mkdir $transfer_dir
cp -v /$backup_dir/*_$date.* $transfer_dir/
chown -Rc jhnhnck:jhnhnck $transfer_dir

printf '%s\n' "===" "Waiting for transfer; press any key once complete..." "==="
read -s any_key

rm -rvf $transfer_dir

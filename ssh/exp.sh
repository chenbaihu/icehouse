#!/usr/bin/expect -f
spawn %TOPDIR%/keys.sh
expect {
"Enter file in which to save the key (/root/.ssh/id_rsa):" { send "\r"; exp_continue }
"Enter passphrase (empty for no passphrase):" { send "\r"; exp_continue }
"Enter same passphrase again:" { send "\r"; exp_continue }
"continue connecting (yes/no)?" { send "yes\r"; exp_continue }
"s password:" { send "%ROOT_PASSWORD%\r"; exp_continue }
"want to continue connecting (yes/no)?" { send "yes\r"; exp_continue }
"Do you want to continue*" { send "Y\r"; exp_continue }
}
expect eof

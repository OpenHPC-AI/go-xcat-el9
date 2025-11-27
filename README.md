# go-xcat-el9
**To Fix the Problem: Issue starting xCAT daemon on Rocky Linux 9 and Oracle Linux 9**

### **Error: After installing xcat packages on el9, service getting failed !**

```jsx
[root@cn01 ~]# lsxcatd -a
Unable to open socket connection to xcatd daemon on localhost:3001.
Verify that the xcatd daemon is running and that your SSL setup is correct.
Connection failure: IO::Socket::INET: connect: Connection refused at /opt/xcat/lib/perl/xCAT/Client.pm line 248.

```

![image.png](attachment:e3f3b74f-1675-430b-a3dc-ecb49875f9b5:image.png)

Solution:

> Note: Don’t Install xCAT packages from repo, if installed then removed the xcat packages
> 

```jsx
yum remove xCAT
```

**`Step1: Download the go-xcat tool using wget:`**

```jsx
# Install go-xcat support package to fix the problem
wget https://raw.githubusercontent.com/xcat2/xcat-core/master/xCAT-server/share/xcat/tools/go-xcat -O - >/tmp/go-xcat

(or)
cd /tmp
git clone  https://github.com/OpenHPC-AI/go-xcat-el9.git

# Change the permission to execute
chmod +x /tmp/go-xcat-el9/go-xcat

```

**`Step2: Run the go-xcat tool:`**

```jsx
/tmp/go-xcat -x latest install -y
```

NOTE: 

1. This will fail with the certificate issue but carry on with the below.
2. I had previous suggested running the command with the devel option but it works with the standard install anyway.

**Step3.**

```jsx
cp /opt/xcat/share/xcat/ca/openssl.cnf.tmpl /opt/xcat/share/xcat/ca/openssl.cnf.tmpl.orig

$vim /opt/xcat/share/xcat/ca/openssl.cnf.tmpl

Comment out anything with "authorityKeyIdentifier" i.e.:
fgrep authorityKeyIdentifier /opt/xcat/share/xcat/ca/openssl.cnf.tmpl

#authorityKeyIdentifier=keyid,issuer
#authorityKeyIdentifier=keyid,issuer
#authorityKeyIdentifier=keyid:always,issuer
# Only issuerAltName and authorityKeyIdentifier make any sense in a CRL.
#authorityKeyIdentifier=keyid:always
#authorityKeyIdentifier=keyid,issuer

```

**Step4.**

```jsx
cp /opt/xcat/share/xcat/scripts/setup-dockerhost-cert.sh /opt/xcat/share/xcat/scripts/setup-dockerhost-cert.sh.orig

vim /opt/xcat/share/xcat/scripts/setup-dockerhost-cert.sh

Change this line:
openssl req -config ca/openssl.cnf -new -key ca/dockerhost-key.pem -out cert/dockerhost-req.pem -extensions server -subj "/CN=$CNA"
to:
openssl req -config ca/openssl.cnf -new -key ca/dockerhost-key.pem -out cert/dockerhost-req.pem -subj "/CN=$CNA"
```

**Step5**.

**Source the profile to add xCAT Commands to your path:**

```jsx
source /etc/profile.d/xcat.sh
```

**Step6**.
**`Reinitialise the xcat installation:`** 

```jsx
xcatconfig -i -c -s
```

**Step7.**
**`Restart the xcatd service and Check the xCAT version:`**  

```jsx
restartxcatd

lsxcatd -a
```

> **Tips:**
> 
> 
> ```
> You need to install the initscripts RPM. el9 dropped sysinit for systemd
> and xCAT is sysinit based.
> You have to do this before trying to install xCAT because it will break your /etc/init.d symlink.
> go-xcat will install initscripts for you.
> ```
>

# smutt
Configurations and helper scripts for working with s/mime in mutt on macOS

By default, mutt's s/mime setup makes use of OpenSSL. This works just fine, but requires you to store certificates and keys as files on the file system. Instead, this configuration will make use of macOS' `security cms` functionality allowing you to use certificates and keys stored in the macOS keychain.

Currently, this only covers accessing your certificate and key from the keychain. Other people's certificates are still stored as files on the file system. As such, the functions we need to modify are:

1) Signing
2) Decryption
3) Verification

At it's simplest, if you already have a working s/mime setup for mutt, this only requires changing four lines.

```
set smime_sign_command="unix2dos -q -o %f ;security cms -S -T -i %f -N Certificate_Nick_Name"
set smime_decrypt_command="security cms -D -i %f"
set smime_verify_command="security cms -D -i %s -c %f -n -h0"
set smime_verify_opaque_command="security cms -D -i %s"
```

However, this is unlikely to be enough on its own and we include a full config in this repository. 

# Prerequisites

You'll need a version of mutt that supports s/mime. If compiling you're own, you'll need to pass `--enable-gpgme` in at the `prepare` phase. S/MIME support is coupled with GPGME support at compile time.

You'll need a copy of the default s/mime configuration file for mutt can be found at their repository:
https://gitlab.com/muttmua/mutt/-/blob/master/contrib/smime.rc?ref_type=heads

# Detailed Configuration Explanation

Our `smime.rc` can be found in this repository. It makes the changes listed above as well as several others, explained below in the order in which they appear.

```
set smime_is_default
set crypt_use_gpgme = no
```

Enabling s/mime is done with the first line, I've also found it helps to disable GPGME as it caused some problems.


```
set crypt_autosign = yes
set crypt_replyencrypt = yes
set crypt_replysign = yes
set crypt_replysignencrypted = yes
set crypt_verify_sig = yes
```

These enable all the crypto operations.


```
set smime_sign_command="unix2dos -q -o %f ;security cms -S -T -i %f -N Certificate_Nick_Name"
```

The unix2dos step is required to make `security cms`'s output match `openssl`'s. I found it in an obscure, long gone blog post on archive.org because it had been mentioned somewhere else, and now I can't remember where to reference the author.

The `Certificate_Nick_Name` is based on what you've called the certificate in your keychain. Typically, this is the e-mail address it's associated with.


```
set smime_decrypt_command="security cms -D -i %f"
```

This is the only command which has a simple drop-in replacement. Good job Apple.


```
set smime_verify_command="security cms -D -i %s -c %f -n -h0"
set smime_verify_opaque_command="security cms -D -i %s"
```

These two lines cost me many hours. First off, they assume you've changed mutt's default smime behaviour to "enveloped" (see below). Second, they will work to display mail, but will give verification errors. To fix those, you'll need the helper script (see below).


```
set smime_pkcs7_default_smime_type="enveloped"
```

Microsoft Outlook's S/MIME implementation provides no smime-type parameter for opaque S/MIME, leaving the client to have to set a sane default, which is currently "signed". However, if your organisation, like mine, by default encrypts all mail, then you'll want to change this to "enveloped".

Initially, I couldn't get this setting to take effect, and so the repository also includes a patch to the source, `mutt.patch` to switch this default. However, I just forgot the "d" in "enveloped" and it's entirely unnecessary, but included for posterity sake.

# Verification Helper Script

Using `security cms` directly for verification causes problems for mutt's verification success detection, as it's setup to expect the exact string ["verification successful"](https://gitlab.com/search?search=Verification%20successful&nav_source=navbar&project_id=4815250&search_code=true&repository_ref=master).

This requires us to parse the verification output from `security cms` and only provide the required output if we can, in fact, trust that the verification was successful.

This is what the `smime_verify_macos.sh` helper script does. It first checks for any signature mismatches, then checks whether any of the signing certificates were untrusted (there can be more than one), and helpfully displays some information about the failed certificate, then checks for a good signature. Only then will it provide the required "verification successful" output.

To configure mutt to use this, you merely need to change the following two lines:

```
set smime_verify_command="smime_verify_macos.sh %s %f"
set smime_verify_opaque_command="smime_verify_macos.sh %s"
```

This does assume you've set the default smime_type to "enveloped"!

# Bonus: Touch ID Integration

I was unhappy with the fact that, as long as the keychain is unlocked, `security cms` will happily sign anything sent to it. Instead, I wanted to specifically authorise each decryption or signing operation. To that end I build [`tidcli`](https://github.com/singe/tidcli).

Decryption or Signing actions can be wrapped in a small script, which will then pop a touch ID prompt before each operation and allow you to both be aware it's happening and to authorise it. An example of such a script for decryption is:

```
#!/bin/sh
tidcli "DECRYPT MAIL" 1> /dev/null 2> /dev/null
if [[ "$?" -eq 1 ]]; then
  exit 1
fi
mail="$1"
security cms -D -i "$mail"
```

The `smime.rc` config value would then change to something like:

```
set smime_decrypt_command="smime_decrypt_macos.sh %f"
```

# Bonus: Certificate Lookup from the GAL/LDAP

To encrypt mail, you'll need the certificate of the user you want to encrypt mail to. In a Microsoft environment, these can be stored in the global address list. Outlook handles this automatically, and it would be nice if mutt did too.

[DavMail](http://davmail.sourceforge.net/) provides support for interfacing with the Microsoft365 world. For this specific purpose, it provides an LDAP server that can be used to make GAL lookups for certificates, thanks to [this pull](http://davmail.sourceforge.net/) request having been merged.

An example command for doing this manually is:

```
ldapsearch -LLL -x -H ldap://127.0.0.1:1389 -D "username" -w password -b "ou=people" "(mail=lookup_name*)" "usersmimecertificate;binary"`
```

Your username will likely be your e-mail address, depending on the authentication you're using for DavMail, the password could be anything, and `lookup_name` would be the address of the user who's certificate you're looking up.

I have a set of scripts for automating this lookup, but need to resolve some bugs in edge cases before I add them here. Contributors welcome!

# Test-only StoreKit signing chain

A root, intermediate and leaf made for the entitlement tests, carrying the same
certificate markers as Apple's (1.2.840.113635.100.6.2.1 on the intermediate,
1.2.840.113635.100.6.11.1 on the leaf) so the tests exercise the whole path Apple's
library takes.

`leaf.pkcs8.pem` is a private key, committed on purpose. It signs purchases that are
trusted only when a test passes `root.pem` in as a root. Production trusts Apple Root
CA - G3 and nothing else (`src/apple-root.ts`), so a purchase signed with this key is
refused by the deployed Worker. A test proves that.

The root and intermediate keys were thrown away after signing. Regenerate the whole
chain with `ext.cnf` if the certificates ever expire (2046).

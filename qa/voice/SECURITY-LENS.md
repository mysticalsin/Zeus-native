# Security-lens sweep

Sentinel's first review of #145 at `8c74617a` was not agreed. This file is the security-lens record of that review.

| id | severity | result |
| --- | --- | --- |
| Z-1 | Medium | A key is stripped, then refused when a control character remains. The refusal happens before the ledger is charged. Header and request failures use a fixed message. Redaction covers the escaped form and every piece of the key that is at least 4 characters. |
| Z-2 | Low | The HTTP opener refuses every redirect, so the key header is not copied to another host. |
| Z-3 | Info | The README states that the ledger is a local guard and is not tamper-proof. |
| Z-4 | Info | The ledger and its lock are opened with `O_NOFOLLOW`. A symlink is refused. |
| Z-5 | Info | One request over 5,000 characters is refused before the ledger is charged. |
| Z-6 | Info | An upstream error body is redacted and then truncated to 200 characters. |

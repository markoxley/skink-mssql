# skink-mssql

Microsoft SQL Server driver for Skink — a pure-Skink implementation of
the TDS 7.x wire protocol. No vendor client library: prelogin option
negotiation, LOGIN7 authentication, SQL batches, `sp_executesql` bound
parameters, and full response-token decoding are implemented in Skink.

## Install

```bash
scales add mod/markoxley/skink-mssql
```

## Usage

```skink
import "mod/markoxley/skink-mssql"
import "mod/markoxley/skink-dbx/dbx_dsn"
import "mod/markoxley/skink-dbx/dbx_value"

fn main() -> int {
    info, err := dbx_dsn.ParseDSN("mssql://sa:secret@localhost:1433/appdb")
    c, cerr := mssql.Connect(info)
    ...
    res, qerr := mssql.Query(&c,
        "SELECT id, name FROM users WHERE id > ?",
        []dbx_value.Value{dbx_value.Int(int64(10))})
    ...
    mssql.Close(&c)
}
```

Or through the generic `dbx` layer:

```skink
mssql.Register()
conn, err := dbx.Open("mssql://sa:secret@localhost:1433/appdb")
rows, _ := conn.Query("SELECT 1", []dbx_value.Value{})
```

## DSN

```
mssql://[user[:password]@]host[:port][/database][?encrypt=false]
```

- `mssql://` and `sqlserver://` schemes are both registered.
- Default port is `1433`; default database is `master`.
- `?encrypt=false` (default) negotiates `ENCRYPT_NOT_SUP`. SQL Server
  accepts unencrypted sessions unless **Force Encryption** is enabled.
- `?encrypt=true` is *not* supported: TLS-inside-TDS is unimplemented.
  The driver fails fast with an explicit error rather than silently
  sending credentials under cleartext. (TDS wraps TLS records inside
  prelogin packets, and a fresh implementation is planned.)

## Protocol coverage

- **PRELOGIN** — VERSION/ENCRYPT/MARS option negotiation.
- **LOGIN7** — SQL Server authentication (sa/user + password, with the
  standard nibble-swap/XOR `0xA5` obfuscation). Windows/integrated auth
  is not supported.
- **SQLBatch** — `mssql.Batch`/`Query`/`Exec`.
- **Parameters** — `?` placeholders are rewritten to `@P1..@Pn` and the
  batch runs as `EXEC sp_executesql N'sql', N'decls', @P1=literal,...`
  with properly typed literals (bigint, bit, float, datetime2,
  varbinary hex, nvarchar).
- **Tokens** — COLMETADATA, ROW, DONE/DONEINPROC/DONEPROC/DONE_ERROR/
  DONE_SRVERROR row counts and transaction status, ERROR, INFO,
  LOGINACK, ENVCHANGE.
- **Transactions** — `BEGIN`/`COMMIT`/`ROLLBACK TRANSACTION` batches;
  `InTx` tracks the DONE transaction bit.
- **Types** — int1/2/4/8(+N), bit(+N), flt4/8(+N), money(+N),
  char/varchar/nchar/nvarchar (+max), binary/varbinary (+max),
  decimal/numeric (precision/scale → text), date, time, datetime,
  datetime2, datetime4, datetimeoffset, uniqueidentifier.

## Error handling

Server ERROR tokens surface as `MsResult.ErrText`/`ErrNum` and are
converted into `errors.Error` by the dbx adapter; transport failures
return `errors.Error` directly.

## Testing

- `bash run_tests.sh` — unit suites (`conn_test`, `dbx_test`) against
  the in-process scripted TDS backend (`testkit.skink`).
- `./test_live.sh` — spins `mcr.microsoft.com/mssql/server:2022-latest`
  in podman and runs `live_test.skink` end-to-end (or set
  `SKINK_MSSQL_DSN` to run against an existing server).

## Layout

| file            | contents                                        |
|-----------------|-------------------------------------------------|
| `ms_pkt.skink`  | TDS packet framing, byte readers/writers        |
| `ms_type.skink` | column metadata + per-type value decode/encode  |
| `ms_token.skink`| response token stream parsing                   |
| `ms_conn.skink` | prelogin, LOGIN7, batches, params, transactions |
| `ms_dbx.skink`  | dbx driver adapter + scheme registration        |
| `testkit.skink` | scripted fake TDS backend for unit tests        |

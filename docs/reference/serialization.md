# Serialization

Spec: [ssz-specs@v0.1.0](https://github.com/ethereum/ssz-specs/tree/7bce07ff7d51b1a3c66ff4e2bd3233ac248ede70/src/ssz), the `serialize`, `deserialize`, `encode_bytes` and `decode_bytes` methods in `uint.py`, `boolean.py`, `byte_arrays.py`, `bitfields.py`, `collections.py` and `container.py`, with `offsets.py` and `exceptions.py`.

Types: [types.md](types.md). Every argument is public data. Every function is effect-free: it has no state, no resource context and no operation boundary, and it keeps no pointer after it returns.

### `ByteList`

A standalone list with one field, as ARCHITECTURE.md section 6 defines it, and as `CRYPTO_BYTES_*` defines it in asm-crypto.

- `size` This unsigned 8-byte number gives the total buffer size in bytes.
- `offset` This unsigned 8-byte number gives the start of the byte part, in bytes from the buffer start.
- `count` This unsigned 8-byte number gives the number of bytes in use in the byte part.

### `Scratch`

- `size` This unsigned 8-byte number gives the total buffer size in bytes, header included.

The rest of the buffer is workspace. Its previous contents do not change any result.

### `ssz_serialize(type, value, scratch, serialized)`

- `type` This input is a well-formed `TypeDescriptor`, and the function does not validate it.
- `value` This input is a well-formed value of the described type, and the function does not validate it.
- `scratch` This scratch buffer holds at least `scratch` bytes of the root node.
- `serialized` This output is a `ByteList` whose `size` header gives its accessible extent.

Requirements: The function writes the SSZ encoding of `value`, as v0.1.0 `encode_bytes` gives it, into the byte part of `serialized`. It sets `offset` to 24 and `count` to the encoding length. It does not change `size`. The `serialized` and `scratch` bytes do not overlap each other or the inputs.

ABI: The core ABI of ARCHITECTURE.md section 6. The symbol is `ssz_serialize` (`_ssz_serialize` in Mach-O). The pointer arguments are `type`, `value`, `scratch`, then `serialized`.

Effects and ownership: Effect-free.

Bounds: `serialized` needs the size that `ssz_serialize_size` gives. `scratch` needs the root node's `scratch` bytes. The stack bound is in the README.

Outputs: `serialized`, laid out as `ByteList`.

Status: `0` when the output holds the encoding. `1` (`BUFFER_TOO_SMALL`) when `serialized` or `scratch` is too small; the output is then invalid.

### `ssz_serialize_size(type, value, scratch, size)`

- `type` This input is a well-formed `TypeDescriptor`, and the function does not validate it.
- `value` This input is a well-formed value of the described type, and the function does not validate it.
- `scratch` This scratch buffer holds at least `scratch` bytes of the root node.
- `size` This output is an 8-byte buffer that receives the total buffer size that `serialized` needs.

Requirements: The function writes 24 plus the SSZ encoding length of `value`. It reads only `type`, `value` and `scratch`.

ABI: As `ssz_serialize`, with the pointer arguments `type`, `value`, `scratch`, then `size`.

Effects and ownership: Effect-free.

Bounds: `size` is 8 bytes. `scratch` needs the root node's `scratch` bytes.

Outputs: `size`, one unsigned 8-byte number.

Status: `0`, or `1` (`BUFFER_TOO_SMALL`) when `scratch` is too small.

### `ssz_deserialize(type, serialized, scratch, value)`

- `type` This input is a well-formed `TypeDescriptor`, and the function does not validate it.
- `serialized` This input is a well-formed `ByteList` whose byte part holds unvalidated bytes.
- `scratch` This scratch buffer holds at least `scratch` bytes of the root node.
- `value` This output receives the decoded value, and for a variable-size type its `size` header gives its accessible extent.

Requirements: The function decodes the `count` bytes of `serialized` as v0.1.0 `decode_bytes` decodes them for the described type. It accepts exactly the inputs that v0.1.0 accepts. For an input that v0.1.0 refuses, it returns the status of the first `ValueFault` that v0.1.0 raises. The `ByteList` header is trusted; the bytes in the part are validated before each use. A fixed-size output has the extent `mem_size` of the root node. For a variable-size output, the function lays out the value as follows: the parts follow the fixed fields in field order, each part holds exactly its entries with no room, and nested values follow one another at multiples of 8. It writes the value's `size` header only to keep it, and it fills every padding byte with 0. The output and `scratch` do not overlap each other or the inputs.

ABI: As `ssz_serialize`, with the pointer arguments `type`, `serialized`, `scratch`, then `value`.

Effects and ownership: Effect-free.

Bounds: `value` needs the size that `ssz_deserialize_size` gives. `scratch` needs the root node's `scratch` bytes.

Outputs: `value`, laid out as [types.md](types.md) describes.

Status: `0` when the input is valid and the output holds the value. `2` to `17` for a refused input (the refusal codes in [include/ssz.inc](../../include/ssz.inc)), checked before capacity. `1` (`BUFFER_TOO_SMALL`) when the input is valid but `value` or `scratch` is too small. After a non-zero status the output is invalid.

### `ssz_deserialize_size(type, serialized, scratch, size)`

- `type` This input is a well-formed `TypeDescriptor`, and the function does not validate it.
- `serialized` This input is a well-formed `ByteList` whose byte part holds unvalidated bytes.
- `scratch` This scratch buffer holds at least `scratch` bytes of the root node.
- `size` This output is an 8-byte buffer that receives the total buffer size that `ssz_deserialize` needs for `value`.

Requirements: For a valid input, the function writes the exact size of the layout that `ssz_deserialize` builds. For a refused input, it returns the same status as `ssz_deserialize`.

ABI: As `ssz_serialize`, with the pointer arguments `type`, `serialized`, `scratch`, then `size`.

Effects and ownership: Effect-free.

Bounds: `size` is 8 bytes. `scratch` needs the root node's `scratch` bytes.

Outputs: `size`, one unsigned 8-byte number.

Status: As `ssz_deserialize`, with `1` only for a small `scratch`.

<!-- CI generates the tick table for each function here. -->

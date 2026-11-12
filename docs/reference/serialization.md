# Serialization

## Contents

### Functions

- [`ssz_serialize`](#function-ssz_serialize): writes the SSZ encoding of a value.
- [`ssz_serialize_size`](#function-ssz_serialize_size): gives the buffer size that `ssz_serialize` needs.
- [`ssz_deserialize`](#function-ssz_deserialize): reads an SSZ encoding into a value.
- [`ssz_deserialize_size`](#function-ssz_deserialize_size): gives the buffer size that `ssz_deserialize` needs.
- [`ssz_encode_value`](#function-ssz_encode_value): appends the encoding of one value.
- [`ssz_decode_value`](#function-ssz_decode_value): decodes one value.

### Types

- [`Value`](#type-value): an SSZ value in memory.
- [`PartRef`](#type-partref): where the entries of a variable size field are.
- [`TypeDescriptor`](#type-typedescriptor): describes one SSZ type.
- [`TypeNode`](#type-typenode): one type inside a descriptor.
- [`TypeField`](#type-typefield): one container field inside a descriptor.
- [`ByteList`](#type-bytelist): a byte string with a header.
- [`Scratch`](#type-scratch): workspace for one call.
- [`Ctx`](#type-ctx): shared values for one call.
- [`Slot`](#type-slot): where one value is.
- [`Cursor`](#type-cursor): where the next byte goes or comes from.

## Spec

- Document: [ssz-specs v0.1.0](https://github.com/ethereum/ssz-specs/tree/7bce07ff7d51b1a3c66ff4e2bd3233ac248ede70/src/ssz), the version that consensus-specs v1.7.0-beta.4 pins.
- Section: the `serialize` and `deserialize` methods in `uint.py`, `boolean.py`, `byte_arrays.py`, `bitfields.py`, `collections.py` and `container.py`, with `offsets.py`.

## Function `ssz_serialize`

Writes the SSZ encoding of a value.

### Signature

```
ssz_serialize(type, value, scratch, serialized) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | `TypeDescriptor` |
| `value` | input | `Value` |
| `scratch` | scratch | `Scratch` |
| `serialized` | output | `ByteList` |

### Returns

- `SSZ_OK`: `serialized` holds the encoding.
- `SSZ_BUFFER_TOO_SMALL`: `serialized` or `scratch` is too small. `serialized` is then invalid.

### Caller must

- Pass a valid `TypeDescriptor` in `type`. It is not checked.
- Pass a valid `Value` of that type in `value`. It is not checked.
- Set the `size` field of `serialized` and of `scratch` to their buffer sizes.
- Keep `serialized` and `scratch` apart from each other and from the inputs.

### Function does

- Writes the encoding that v0.1.0 `encode_bytes` gives.
- Sets `offset` of `serialized` to 24 and `count` to the encoding length.
- Keeps the `size` field of `serialized`.

### Function never

- Writes outside `serialized`, `scratch` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- `serialized`: the size that `ssz_serialize_size` gives.
- `scratch`: the `scratch` bytes of the root `TypeNode`.
- Stack: at most 1840 bytes on x86-64, 1872 on ARM64 and 1872 on RISC-V.

### ABI

- Role: L2.
- Symbol: `ssz_serialize` (`_ssz_serialize` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `value`, `scratch`, `serialized`.

## Function `ssz_serialize_size`

Gives the buffer size that `ssz_serialize` needs for a value.

### Signature

```
ssz_serialize_size(type, value, scratch, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | `TypeDescriptor` |
| `value` | input | `Value` |
| `scratch` | scratch | `Scratch` |
| `size` | output | u64 |

### Returns

- `SSZ_OK`: `size` holds the buffer size.
- `SSZ_BUFFER_TOO_SMALL`: `scratch` is too small.

### Caller must

- Pass a valid `TypeDescriptor` in `type`. It is not checked.
- Pass a valid `Value` of that type in `value`. It is not checked.
- Set the `size` field of `scratch` to its buffer size.
- Keep `size` and `scratch` apart from each other and from the inputs.

### Function does

- Writes 24 plus the length of the SSZ encoding of `value` to `size`.

### Function never

- Writes outside `size`, `scratch` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- `scratch`: the `scratch` bytes of the root `TypeNode`.
- Stack: at most 1840 bytes on x86-64, 1872 on ARM64 and 1872 on RISC-V.

### ABI

- Role: L2.
- Symbol: `ssz_serialize_size` (`_ssz_serialize_size` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `value`, `scratch`, `size`.

## Function `ssz_deserialize`

Reads an SSZ encoding into a value.

### Signature

```
ssz_deserialize(type, serialized, scratch, value) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | `TypeDescriptor` |
| `serialized` | input | `ByteList` |
| `scratch` | scratch | `Scratch` |
| `value` | output | `Value` |

### Returns

- `SSZ_OK`: the encoding is valid and `value` holds it.
- A decode refusal constant from [include/ssz.inc](../../include/ssz.inc): the encoding breaks a v0.1.0 rule. It names the first fault that v0.1.0 raises.
- `SSZ_BUFFER_TOO_SMALL`: `scratch` is too small, or the encoding is valid but `value` is too small.
- After any status other than `SSZ_OK`, `value` is invalid.

### Caller must

- Pass a valid `TypeDescriptor` in `type`. It is not checked.
- Pass a valid `ByteList` header in `serialized`. The bytes in it can be anything.
- For a variable size type, set the `size` field of `value` to its buffer size.
- For a fixed size type, give `value` the `mem_size` bytes of the root `TypeNode`.
- Set the `size` field of `scratch` to its buffer size.
- Keep `value` and `scratch` apart from each other and from the inputs.

### Function does

- Checks `scratch`, then the encoding, then `value`.
- Accepts exactly the encodings that v0.1.0 `decode_bytes` accepts.
- Checks each byte of the encoding before it uses it.
- Puts the parts after the fixed fields, in field order.
- Fills each part with its entries and leaves no room.
- Starts each nested value at a multiple of 8.
- Fills every padding byte with 0.
- Keeps the `size` field of `value`.

### Function never

- Reads outside the `ByteList` header and its `count` bytes.
- Writes outside `value`, `scratch` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- `value`: the size that `ssz_deserialize_size` gives.
- `scratch`: the `scratch` bytes of the root `TypeNode`.
- Stack: at most 4000 bytes on x86-64, 4384 on ARM64 and 4384 on RISC-V.

### ABI

- Role: L2.
- Symbol: `ssz_deserialize` (`_ssz_deserialize` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `serialized`, `scratch`, `value`.

## Function `ssz_deserialize_size`

Gives the buffer size that `ssz_deserialize` needs for an encoding.

### Signature

```
ssz_deserialize_size(type, serialized, scratch, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | `TypeDescriptor` |
| `serialized` | input | `ByteList` |
| `scratch` | scratch | `Scratch` |
| `size` | output | u64 |

### Returns

- `SSZ_OK`: `size` holds the buffer size.
- The same decode refusal constant that `ssz_deserialize` returns for this encoding.
- `SSZ_BUFFER_TOO_SMALL`: `scratch` is too small.

### Caller must

- Pass a valid `TypeDescriptor` in `type`. It is not checked.
- Pass a valid `ByteList` header in `serialized`. The bytes in it can be anything.
- Set the `size` field of `scratch` to its buffer size.
- Keep `size` and `scratch` apart from each other and from the inputs.

### Function does

- Checks `scratch`, then the encoding.
- Writes the exact size of the value that `ssz_deserialize` builds to `size`.

### Function never

- Reads outside the `ByteList` header and its `count` bytes.
- Writes outside `size`, `scratch` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- `scratch`: the `scratch` bytes of the root `TypeNode`.
- Stack: at most 4000 bytes on x86-64, 4384 on ARM64 and 4384 on RISC-V.

### ABI

- Role: L2.
- Symbol: `ssz_deserialize_size` (`_ssz_deserialize_size` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `serialized`, `scratch`, `size`.

## Function `ssz_encode_value`

Appends the SSZ encoding of one value at a cursor.

### Signature

```
ssz_encode_value(ctx, node, slot, cursor) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ctx` | input | `Ctx` |
| `node` | input | `TypeNode` |
| `slot` | input | `Slot` |
| `cursor` | state | `Cursor` |

### Returns

- `SSZ_OK`: always.

### Caller must

- Pass a `Ctx` that an L2 function filled from a valid `TypeDescriptor`.
- Pass a `TypeNode` of that descriptor in `node`.
- Pass a valid `Value` of that type in `slot`.
- When `ctx.write` is 1, give `cursor.out` room for the whole encoding.

### Function does

- Adds the length of the encoding to `cursor.out`.
- Writes the encoding at `cursor.out` only when `ctx.write` is 1.

### Function never

- Writes outside the encoding, `cursor` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- Stack of its own frame: 144 bytes on every ISA. On x86-64 this includes the return address.
- Recursion depth: at most one call for each level of nested types.

### ABI

- Role: L0.
- Symbol: `ssz_encode_value`, local to the library.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `ctx`, `node`, `slot`, `cursor`.

## Function `ssz_decode_value`

Decodes one value from the encoding at a cursor.

### Signature

```
ssz_decode_value(ctx, node, slot, cursor) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ctx` | input | `Ctx` |
| `node` | input | `TypeNode` |
| `slot` | input | `Slot` |
| `cursor` | state | `Cursor` |

### Returns

- `SSZ_OK`: the `slot.scope` bytes at `cursor.pos` are a valid encoding of the type.
- A decode refusal constant from [include/ssz.inc](../../include/ssz.inc): the first fault that v0.1.0 `deserialize` raises for those bytes. `cursor` is then as it was.

### Caller must

- Pass a `Ctx` that an L2 function filled from a valid `TypeDescriptor`.
- Pass a `TypeNode` of that descriptor in `node`.
- Set `ctx.end` to the end of the whole encoding.
- When `ctx.write` is 1, give the value room at `cursor.next` for every part it adds.

### Function does

- Checks the bytes as v0.1.0 `deserialize` checks a stream with a scope of `slot.scope` bytes.
- Checks every read against `ctx.end`.
- Moves `cursor.pos` past the bytes it reads.
- Moves `cursor.next` past each part it adds, rounded up to a multiple of 8.
- Writes the value only when `ctx.write` is 1.
- Writes the size of a nested value at its start.

### Function never

- Reads encoding bytes at or after `ctx.end`.
- Writes outside the value, `cursor` and its own stack.
- Keeps a pointer after it returns.
- Makes an OS call.

### Limits

- Stack of its own frame: 176 bytes on x86-64, return address included, and 192 bytes on ARM64 and RISC-V.
- Recursion depth: at most two calls for each level of nested types.

### ABI

- Role: L0.
- Symbol: `ssz_decode_value`, local to the library.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `ctx`, `node`, `slot`, `cursor`.

## Type `Value`

An SSZ value in memory, laid out as ARCHITECTURE.md section 6 requires.

### Layout

| SSZ type | Stored as | Alignment |
|---|---|---|
| `Uint8`, `Byte` | 1 byte | 1 |
| `Uint32` | 4 bytes | 4 |
| `Uint64` | 8 bytes | 8 |
| `Uint256` | 32 bytes | 8 |
| `Boolean` | 1 byte, 0 or 1 | 1 |
| `ByteVector[N]` | N bytes | 1 |
| `BitVector[N]` | ceil(N / 8) bytes, in SSZ bit order | 1 |
| `Vector[T, N]`, T of fixed size | N entries of T | That of T |
| `Container`, every field of fixed size | The fields, in spec order | That of its largest field |
| `ByteList[N]` | A `PartRef`. The part holds the bytes. | 8 |
| `BitList[N]` | A `PartRef`. `count` is the number of bits. The part holds ceil(count / 8) bytes, in SSZ bit order, without the delimiter bit. | 8 |
| `List[T, N]`, T of fixed size | A `PartRef`. The part holds the entries. | 8 |
| `List[T, N]` or `Vector[T, N]`, T of variable size | A `PartRef`. The part holds one nested value of T for each entry. | 8 |
| `Container` with a field of variable size | A `PartRef` with `count` 1. The part holds one nested value. | 8 |

### Rules

- The SSZ types above are the ones that consensus-specs uses on phase0 to fulu.
- Numbers are little endian. u64 is an 8 byte number.
- Each field starts at a multiple of its alignment.
- The stride of an entry is the `mem_size` of its type.
- A container of fixed size fields is padded to a multiple of its alignment.
- A fixed size value is only the bytes above.
- A variable size value starts with its total size, as u64.
- A container value holds each field at its `mem_offset`.
- A list value, or a vector value of variable size, holds its `PartRef` at byte 8.
- The parts start at `value_fixed`, in field order.
- Each part ends where the next part starts, or at the end of the value.
- Each nested value in a part starts at a multiple of 8.
- The size of a nested value is a multiple of 8. It gives the start of the next one.
- Valid when these rules hold, each count is within the limit of its type, each `Boolean` is 0 or 1, and each padding bit is 0.

## Type `PartRef`

Where the entries of a variable size field are.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `offset` | u64 | Where the part starts, from the start of the value that holds it |
| 8 | `count` | u64 | Number of entries |

### Rules

- 16 bytes.
- Starts at a multiple of 8.

## Type `TypeDescriptor`

Describes one SSZ type and every type inside it.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Total buffer size in bytes |
| 8 | `nodes.offset` | u64 | Where the `TypeNode` records start |
| 16 | `nodes.count` | u64 | Number of `TypeNode` records |
| 24 | `fields.offset` | u64 | Where the `TypeField` records start |
| 32 | `fields.count` | u64 | Number of `TypeField` records |
| 40 | `root` | u64 | Index of the `TypeNode` for the described type |

### Rules

- The descriptor builder, [tests/generator/descriptor.py](../../tests/generator/descriptor.py), writes it.
- The `TypeNode` records come first, then the `TypeField` records.
- Both start at multiples of 8.
- Every index is in range.
- A type has a lower node index than every type inside it.
- A type has at most 12 levels of nested types, itself included. A basic type has 1.

## Type `TypeNode`

One SSZ type inside a `TypeDescriptor`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `kind` | u64 | One of the `SSZ_KIND_*` constants |
| 8 | `length` | u64 | Width of a uint in bytes, N of a vector, limit of a list, or field count of a container |
| 16 | `element` | u64 | Element `TypeNode` of a vector or list, or first `TypeField` of a container |
| 24 | `ssz_size` | u64 | SSZ encoding size of a fixed size type, else 0 |
| 32 | `mem_size` | u64 | Bytes the type takes inside another value (16 for a variable size type) |
| 40 | `mem_align` | u64 | Alignment of the type inside another value |
| 48 | `value_fixed` | u64 | Where the parts start in a value of this type |
| 56 | `chunks` | u64 | Merkle leaf count at this type's own level (`chunk_count` in the spec) |
| 64 | `scratch` | u64 | Scratch bytes that each function needs for this type |

### Rules

- 72 bytes.

## Type `TypeField`

One container field inside a `TypeDescriptor`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `node` | u64 | `TypeNode` of the field type |
| 8 | `mem_offset` | u64 | Where the field starts, from the start of the container value |
| 16 | `ssz_offset` | u64 | Where the field, or its 4 byte offset, starts in the SSZ fixed part |
| 24 | `flags` | u64 | `SSZ_FIELD_VARIABLE` when the field type is of variable size |

### Rules

- 32 bytes.

## Type `ByteList`

A byte string with a 24 byte header.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Total buffer size in bytes |
| 8 | `offset` | u64 | Where the bytes start, from the buffer start |
| 16 | `count` | u64 | Number of bytes in use |

### Rules

- The buffer starts at a multiple of 8.
- `offset` is at least 24 and a multiple of 8.
- `offset + count` is at most `size`.
- Bytes after `count` are unused. Functions do not read them.

## Type `Scratch`

Workspace for one call.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Total buffer size in bytes, this field included |
| 8 | `sha` | `ByteList`, 88 bytes | The 64 byte input of one SHA-256 |
| 96 | `ctx` | `Ctx` | Filled by each L2 function |
| 160 | `level` | `Level` | The leaves of the root type |
| 256 | `work` | `Work` | The work area of the root level |

### Rules

- The buffer starts at a multiple of 8.
- The caller sets only `size`. The rest is workspace.
- The old contents of the workspace do not change any result.
- `Level` and `Work` are in [merkleization.md](merkleization.md).

## Type `Ctx`

Shared values for one call.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `nodes` | u64 | Address of the first `TypeNode` |
| 8 | `fields` | u64 | Address of the first `TypeField` |
| 16 | `write` | u64 | 1: write the output. 0: only measure it. |
| 24 | `end` | u64 | Deserialize: the address after the last encoded byte |
| 32 | `sha` | u64 | Address of the `sha` `ByteList` in `Scratch` |
| 40 | `zero` | u64 | Address of the 65 zero roots in [include/ssz_zero_hashes.inc](../../include/ssz_zero_hashes.inc) |

### Rules

- 64 bytes.
- Each L2 function fills it in its `Scratch`.
- The functions it calls do not change it.

## Type `Slot`

Where one value is.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `p` | u64 | Address of the in-place storage, or of the start of a value |
| 8 | `b` | u64 | Address of the value that holds the in-place storage |
| 16 | `form` | u64 | `SSZ_FORM_PLACE`, `SSZ_FORM_NESTED` or `SSZ_FORM_TOP` |
| 24 | `scope` | u64 | Deserialize: the bytes that the encoding gives this value |

### Rules

- 32 bytes.
- `SSZ_FORM_PLACE`: `p` is in-place storage inside the value at `b`.
- `SSZ_FORM_NESTED`: `p` starts a nested value in a part.
- `SSZ_FORM_TOP`: `p` starts the caller's value.
- When a deserialize function only measures, the caller's value starts at address 0.

## Type `Cursor`

Where the next byte goes or comes from.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `out` | u64 | Serialize: address of the next output byte |
| 0 | `pos` | u64 | Deserialize: address of the next encoded byte |
| 8 | `next` | u64 | Deserialize: address of the next free byte of the value |

### Rules

- 16 bytes.
- When a function only measures, `out` starts at 0.

## Test vectors

- consensus-specs v1.7.0-beta.4, `ssz_static` tests, phase0 to fulu, mainnet and minimal presets.
  - Release: [v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/releases/tag/v1.7.0-beta.4)
  - `mainnet.tar.gz`, SHA-256: `67762986572372a08d3b182535aa760433c86e174e14e0bbd756f350dd19398c`
  - `minimal.tar.gz`, SHA-256: `26d09aea70c62ed235a120a95082d544ab1c2e6fe36bd35ea1bd5da62f3b7b68`
- Type of each case: the Python spec at [consensus-specs@aa16bb4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304), with the packages in [tests/generator/requirements.txt](../../tests/generator/requirements.txt).
- Check: for the first case of each type, the Python spec decodes the encoding and gives the case root.

## Results

<!-- CI generates the tick table for each function here. -->

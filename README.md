# asm-ssz

Assembly implementation of SimpleSerialize (SSZ), the serialization and Merkleization scheme used by Ethereum, as specified by [ethereum/ssz-specs](https://github.com/ethereum/ssz-specs).

Architecture: [asm-standard@794776c](https://github.com/bitminetech/asm-standard/blob/794776c3ba1d84f5470c2a1ccc57ac5a7d525299/ARCHITECTURE.md)

## Pins

| Dependency | Version |
|---|---|
| Original reference spec | [ethereum/ssz-specs@4411658](https://github.com/ethereum/ssz-specs/tree/441165848263efe5d9f82f4e85b8e417fe8e36af) |
| Vector generation | <List expected-result sources, pinned specs, generators and dependencies, fork or preset, options and seed where used.> |
| Build tools | <Pin assemblers, linkers, import printers and artifact-check tools when used.> |
| Target profiles | <Record ABI variants, baseline/allowed extensions, CPU and OS-enabled state, OS/API versions and feature selection.> |
| Environment boundaries | <Name each trusted syscall/API, its pinned requirements and remaining runtime assumptions.> |
| Stack limit | <State owned stack bounds, native-call/handler headroom and the platform preparation/probing policy.> |

## Dependencies

- <Name each dependency repo, exact implementation and compatible interface/profile, and the public functions used.>

## Integration

<State native/common-ABI entry points, context ownership, startup/wakeup obligations, action/event delivery and shutdown. State any crash-recovery or persistence guarantees and their scope, or state that none are provided.>

import Foundation

/// Structural validation only; this cannot prove that a border router is reachable.
public enum ThreadDatasetInput {
    public enum Failure: Error { case invalidHex, invalidTLV, missingField, invalidField }

    public static func parse(_ text: String) throws -> Data {
        let hex = text.filter { !$0.isWhitespace }
        guard !hex.isEmpty, hex.count <= 508, hex.count.isMultiple(of: 2),
              hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw Failure.invalidHex
        }
        let chars = Array(hex)
        let bytes = stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...($0 + 1)]), radix: 16)! }
        var fields: [UInt8: [UInt8]] = [:]
        var index = 0
        while index < bytes.count {
            guard index + 2 <= bytes.count else { throw Failure.invalidTLV }
            let type = bytes[index], length = Int(bytes[index + 1])
            index += 2
            guard fields[type] == nil, index + length <= bytes.count else { throw Failure.invalidTLV }
            fields[type] = Array(bytes[index..<(index + length)])
            index += length
        }
        // Active dataset mandatory fields. Unknown extension TLVs are retained.
        let sizes: [UInt8: Int] = [0: 3, 1: 2, 2: 8, 4: 16, 5: 16, 7: 8, 14: 8]
        for (type, size) in sizes {
            guard let field = fields[type] else { throw Failure.missingField }
            guard field.count == size else { throw Failure.invalidField }
        }
        guard let name = fields[3], let policy = fields[12], let mask = fields[53] else { throw Failure.missingField }
        guard (1...16).contains(name.count), String(bytes: name, encoding: .utf8) != nil,
              !name.contains(0), (3...4).contains(policy.count), !mask.isEmpty,
              fields[0]![0] == 0, fields[0]![1] == 0, (11...26).contains(fields[0]![2]),
              fields[1]! != [255, 255], fields[7]![0] == 0xfd,
              fields[51] == nil, fields[52] == nil else { throw Failure.invalidField }
        var offset = 0
        var supportsChannel = false
        while offset < mask.count {
            guard offset + 2 <= mask.count else { throw Failure.invalidField }
            let page = mask[offset], count = Int(mask[offset + 1])
            offset += 2
            guard count > 0, offset + count <= mask.count else { throw Failure.invalidField }
            if page == 0 {
                guard count == 4 else { throw Failure.invalidField }
                let bits = mask[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                // MeshCoP encodes channel 0 in the most-significant bit, unlike
                // OpenThread's host mask (ChannelMaskTlv::Entry::GetMask reverses it).
                supportsChannel = bits & (1 << (31 - UInt32(fields[0]![2]))) != 0
            }
            offset += count
        }
        guard supportsChannel else { throw Failure.invalidField }
        return Data(bytes)
    }
}

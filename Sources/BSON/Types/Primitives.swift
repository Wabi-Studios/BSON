import Foundation

public protocol Primitive: Codable, Sendable, PrimitiveEncodable {}

extension Primitive {
    public func encodePrimitive() throws -> Primitive {
        self
    }
}

internal protocol BSONPrimitiveRepresentable: Primitive {
    var primitive: Primitive { get }
}

internal protocol BSONPrimitiveConvertible: BSONPrimitiveRepresentable {
    init(primitive: Primitive?) throws
}

internal protocol AnyBSONEncoder {
    func encode(document: Document) throws
}

internal protocol AnySingleValueBSONDecodingContainer {
    func decodeObjectId() throws -> ObjectId
    func decodeDocument() throws -> Document
    func decodeDecimal128() throws -> Decimal128
    func decodeBinary() throws -> Binary
    func decodeRegularExpression() throws -> RegularExpression
    func decodeNull() throws -> Null
}

internal protocol AnySingleValueBSONEncodingContainer {
    mutating func encode(primitive: Primitive) throws
}

fileprivate struct UnsupportedDocumentDecoding: Error {}

fileprivate struct AnyEncodable: Encodable {
    var encodable: Encodable
    
    func encode(to encoder: Encoder) throws {
        try encodable.encode(to: encoder)
    }
}

extension Data: BSONPrimitiveConvertible, @unchecked Sendable {
    init(primitive: Primitive?) throws {
        guard let value = primitive, let binary = value as? Binary else {
            throw BSONTypeConversionError(from: type(of: primitive), to: Data.self)
        }
        
        self = binary.data
    }
    
    var primitive: Primitive {
        var buffer = Document.allocator.buffer(capacity: self.count)
        buffer.writeBytes(self)
        return Binary(buffer: buffer)
    }
}

extension Document {
    public func encode(to encoder: Encoder) throws {
        if let encoder = encoder as? AnyBSONEncoder {
            try encoder.encode(document: self)
        } else if self.isArray {
            var container = encoder.unkeyedContainer()
            
            for value in self.values {
                try container.encode(AnyEncodable(encodable: value))
            }
        } else {
            var container = encoder.container(keyedBy: CustomKey.self)
            
            for pair in self.pairs {
                try container.encode(AnyEncodable(encodable: pair.value), forKey: CustomKey(stringValue: pair.key)!)
            }
        }
    }
    
    public init(from decoder: Decoder) throws {
        switch decoder {
        case let decoder as _FastBSONDecoder<Document>:
            self = decoder.value
            return
        case let decoder as _BSONDecoder:
            let primitive = decoder.primitive
            guard let document = primitive as? Document else {
                throw BSONTypeConversionError(from: primitive, to: Document.self)
            }
            
            self = document
            return
        default:
            struct Key: CodingKey {
                var stringValue: String
                var intValue: Int? { nil }
                
                init?(intValue: Int) { nil }
                
                init(stringValue: String) {
                    self.stringValue = stringValue
                }
            }
            
            let container = try decoder.container(keyedBy: Key.self)
            var document = Document()
            
            nextKey: for key in container.allKeys {
                if try container.decodeNil(forKey: key) {
                    continue nextKey
                }
                
                if let string = try? container.decode(String.self, forKey: key) {
                    document[key.stringValue] = string
                    continue nextKey
                }
                
                if let int = try? container.decode(Int.self, forKey: key) {
                    document[key.stringValue] = int
                    continue nextKey
                }
                
                if let int = try? container.decode(Int32.self, forKey: key) {
                    document[key.stringValue] = int
                    continue nextKey
                }
                
                if let double = try? container.decode(Double.self, forKey: key) {
                    document[key.stringValue] = double
                    continue nextKey
                }
                
                if let bool = try? container.decode(Bool.self, forKey: key) {
                    document[key.stringValue] = bool
                    continue nextKey
                }
                
                // TODO: Niche Int cases
                
                throw UnsupportedDocumentDecoding()
            }
            
            self = document
        }
    }
}

fileprivate struct CustomKey: CodingKey {
    var stringValue: String
    
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    var intValue: Int?
    
    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = intValue.description
    }
}

extension ObjectId: Primitive {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if var container = container as? AnySingleValueBSONEncodingContainer {
            try container.encode(primitive: self)
        } else {
            try container.encode(self.hexString)
        }
    }
    
    public init(from decoder: Decoder) throws {
        switch decoder {
        case let decoder as _FastBSONDecoder<ObjectId>:
            self = decoder.value
            return
        case let decoder as _BSONDecoder:
            let primitive = decoder.primitive
            guard let value = primitive as? ObjectId else {
                throw BSONTypeConversionError(from: primitive, to: ObjectId.self)
            }
            
            self = value
            return
        default:
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            self = try ObjectId.make(from: string)
        }
    }
}

struct BSONComparisonTypeMismatch: Error {
    let lhs: Primitive?
    let rhs: Primitive?
}

extension Int32: Primitive {}
extension Date: Primitive, @unchecked Sendable {}

#if (arch(i386) || arch(arm)) && BSONInt64Primitive
internal typealias _BSON64BitInteger = Int64
extension Int64: Primitive {}
#else
internal typealias _BSON64BitInteger = Int
extension Int: Primitive {}
#endif

extension Double: Primitive {}
extension Bool: Primitive {}
extension String: Primitive {}

public struct MinKey: Primitive {
    public init() {}
}

public struct MaxKey: Primitive {
    public init() {}
}

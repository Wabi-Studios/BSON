extension Document: RandomAccessCollection, MutableCollection {
    public subscript(position: DocumentIndex) -> (String, Primitive) {
        get {
            var offset = 4
            for _ in 0..<position.offset {
                guard self.skipKeyValuePair(at: &offset) else {
                    fatalError("DocumentIndex exceeded Document bounds")
                }
            }
            
            let type = TypeIdentifier(rawValue: storage.getByte(at: offset)!)!
            offset += 1
            
            let length = storage.firstRelativeIndexOf(startingAt: offset)!
            let key = storage.getString(at: offset, length: length)!
            offset += length + 1
            
            let value = self.value(forType: type, at: offset)!
            
            return (key, value)
        }
        set {
            guard let key = self.getKey(at: position.offset) else {
                fatalError("Attempting to change a value out of bounds")
            }
            
            if key == newValue.0 {
                // Same key, just change the value
                self[key] = newValue.1
            } else {
                self[key] = nil
                self[newValue.0] = newValue.1
            }
        }
    }
    
    public subscript(bounds: Range<DocumentIndex>) -> DocumentSlice {
        get {
            DocumentSlice(document: self, startIndex: bounds.lowerBound, endIndex: bounds.upperBound)
        }
        set {
            let start = bounds.lowerBound.offset
            let end = bounds.upperBound.offset
            var index = end
            
            while index != start {
                index -= 1
                remove(at: index)
            }
            
            for (key, value) in newValue.document {
                self[key] = value
            }
        }
    }
    
    public typealias Iterator = DocumentIterator
    public typealias SubSequence = DocumentSlice
    public typealias Index = DocumentIndex
    
    public var count: Int {
        var offset = 4
        var count = 0

        while skipKeyValuePair(at: &offset) {
            count += 1
        }

        return count
    }
    
    public var startIndex: DocumentIndex {
        return DocumentIndex(offset: 0)
    }
    
    public func index(after i: DocumentIndex) -> DocumentIndex {
        return DocumentIndex(offset: i.offset + 1)
    }
    
    public func index(before i: DocumentIndex) -> DocumentIndex {
        return DocumentIndex(offset: i.offset - 1)
    }
    
    public var endIndex: DocumentIndex {
        return DocumentIndex(offset: count)
    }
    
    /// Creates an iterator that iterates over each pair in the Document
    public func makeIterator() -> DocumentIterator {
        return DocumentIterator(document: self)
    }
    
    /// A more detailed view into the pairs contained in this
    public var pairs: DocumentPairIterator {
        return DocumentPairIterator(document: self)
    }
}

/// A type that can be used as a key in a `Document`.
public struct DocumentIndex: Comparable, Hashable {
    /// The offset in the Document to look for
    var offset: Int
    
    public static func < (lhs: DocumentIndex, rhs: DocumentIndex) -> Bool {
        return lhs.offset < rhs.offset
    }
}

/// A key-value pair from a Document
///
/// Contains all metadata for a given Pair
public struct DocumentPair {
    /// The index in the Document at which this pair resides
    public let index: Int
    
    /// The key associated with this pair
    public let key: String
    
    /// The value associated with this pair
    public var value: Primitive
}

/// An iterator that iterates over each pair in a `Document`.
public struct DocumentPairIterator: IteratorProtocol, Sequence {
    /// The Document that is being iterated over
    fileprivate let document: Document
    
    /// The next index to be returned. This is incremented after each call to `next()`
    public private(set) var currentIndex = 0

    /// The current index in the binary representation of the Document.
    public private(set) var currentBinaryIndex = 4
    
    /// If `true`, the end of this iterator has been reached
    public var isDrained: Bool {
        return count <= currentIndex
    }
    
    /// The total amount of elements in this iterator (previous, current and upcoming elements)
    public let count: Int
    
    /// Creates an iterator for a given Document
    public init(document: Document) {
        self.document = document
        self.count = document.count
    }
    
    /// Returns the next element in the Document *unless* the last element was already returned
    public mutating func next() -> DocumentPair? {
        guard currentIndex < count else { return nil }
        defer { currentIndex += 1 }

        guard
            let typeByte = document.storage.getByte(at: currentBinaryIndex),
            let type = TypeIdentifier(rawValue: typeByte)
        else {
            return nil
        }
        
        currentBinaryIndex += 1
        
        guard
            let key = document.getKey(at: currentBinaryIndex),
            document.skipKey(at: &currentBinaryIndex),
            let valueLength = document.valueLength(forType: type, at: currentBinaryIndex),
            let value = document.value(forType: type, at: currentBinaryIndex)
        else {
            return nil
        }
        
        currentBinaryIndex += valueLength
        
        return DocumentPair(index: currentIndex, key: key, value: value)
    }
}

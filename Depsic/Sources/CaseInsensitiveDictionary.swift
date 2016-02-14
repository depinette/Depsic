//
//  CaseInsensitiveDictionary.swift
//  Depsic
//
//  Created by depinette on 25/01/2016.
//  Copyright © 2016 depsys. All rights reserved.
//

import Foundation
struct CaseInsensitiveDictionary<Value>: CollectionType, DictionaryLiteralConvertible
{
    private var internalDictionary:Dictionary<String, Value> = [:]
    typealias Key = String
    typealias Element = (Key, Value)
    typealias Index = DictionaryIndex<Key, Value>
    var startIndex: Index
    var endIndex: Index
    
    var count: Int
    {
        return internalDictionary.count
    }
    
    var isEmpty: Bool
    {
        return internalDictionary.isEmpty
    }
    
    init()
    {
        startIndex = internalDictionary.startIndex
        endIndex = internalDictionary.endIndex
    }
    
    init(dictionaryLiteral elements: (Key, Value)...)
    {
        for (key, value) in elements {
            internalDictionary[key.lowercaseString] = value
        }
        startIndex = internalDictionary.startIndex
        endIndex = internalDictionary.endIndex
    }
    init(_ dict:Dictionary<String, Value>)
    {
        for (key, value) in dict {
            internalDictionary[key.lowercaseString] = value
        }
        startIndex = internalDictionary.startIndex
        endIndex = internalDictionary.endIndex
    }
    
    subscript (position: Index) -> Element
    {
        return internalDictionary[position]
    }
    
    subscript (key: Key) -> Value?
        {
        get { return internalDictionary[key.lowercaseString] }
        set(newValue) { internalDictionary[key.lowercaseString] = newValue }
    }
    
    func generate() -> DictionaryGenerator<Key, Value>
    {
        return internalDictionary.generate()
    }
    
    mutating func removeValueForKey(key: Key) -> Value?
    {
        let value = self.internalDictionary.removeValueForKey(key.lowercaseString)
        return value
    }
}
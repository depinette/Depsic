//
//  SCGIParser.swift
//  Depsic
//
//  Created by depinette on 01/01/2016.
//  Copyright © 2016 depsys. All rights reserved.
//  A Simple CGI (header) parser, feed it data until it called the completion closure.
//  It does not process the body but the completion closure might be called with the first chunk of body data

import Foundation
#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

/*
"70:"
"CONTENT_LENGTH" <00> "27" <00>
"SCGI" <00> "1" <00>
"REQUEST_METHOD" <00> "POST" <00>
"REQUEST_URI" <00> "/deepthought" <00>
","
"What is the answer to life?"
*/

/*
curl testing http://superuser.com/a/149335
curl --data "param1=value1&param2=value2" http://localhost:8080/body
//TODO unit test, variable buffer bigger than a frame
*/

public enum SCGIParserError : ErrorType
{
    case NoDigitAtStart(index:Int)
    case StartWithZero
    case NetStringLengthError(invalidByte:UInt8)
    case HeaderEncoding(value:[UInt8])
    case WrongLength(expectedLength:Int)
    case CommaMissing
    case ContentLengthMissing
    case UnexpectedBytes
}

private enum SCGIParseState
{
    case NotStarted
    case NetStringLength(stringLength:Int)
    case NetStringColon
    case NetStringHeaderName(workArray:[UInt8])
    case NetStringHeaderValue(name:String, workArray:[UInt8])
    case NetStringComma
    case End
}

private struct SCGIParseInfo
{
    var netstringLength:Int = 0
    var contentLength:Int = -1
    var counter:Int = 0
    var totalIndex:Int = 0
    mutating func increment()
    {
        self.counter += 1
        self.totalIndex += 1
    }
}

public class SCGIParser
{
    let completionBlock:(headers:Dictionary<String, String>, contentLength:Int, remainingBytes:ArraySlice<UInt8>?) ->Void
    init(completion:(headers:Dictionary<String, String>, contentLength:Int,  remainingBytes:ArraySlice<UInt8>?) -> Void)
    {
        self.completionBlock = completion
    }
    internal func decode(buffer: [UInt8]) throws
    {
        return try parseStateMachine(buffer)
    }
 
    private var parseInfo = SCGIParseInfo()
    private var headers = Dictionary<String, String>()
    private var currentState:SCGIParseState = .NotStarted

    private func parseStateMachine(buffer:[UInt8]) throws
    {
        let AsciiZero:UInt8 = UInt8(0x30)
        let AsciiColon:UInt8 = UInt8(0x3a)
        let AsciiComma:UInt8 = UInt8(0x2c)

        ByteByByteLoop: for currentIndex in 0..<buffer.count {
            let nextByte = buffer[currentIndex]
            parseInfo.increment()
            switch (currentState) {
                case .NotStarted:
                    //next byte is digit go to NetStringLength
                    if (isdigit(Int32(nextByte))) == 0 {
                        throw SCGIParserError.NoDigitAtStart(index:parseInfo.totalIndex)
                    }
                    else if (nextByte == AsciiZero) {
                        throw SCGIParserError.StartWithZero
                    }
                    currentState = .NetStringLength(stringLength:Int(nextByte - AsciiZero))
                case .NetStringLength(let currentStringLength):
                    //while next byte is digit continue
                    if (isdigit(Int32(nextByte))) != 0 {
                        currentState = .NetStringLength(stringLength: (currentStringLength*10) + Int(nextByte - AsciiZero))
                    }
                    else if nextByte == AsciiColon {
                        parseInfo.netstringLength = currentStringLength
                        currentState = .NetStringColon
                    } else {
                        throw SCGIParserError.NetStringLengthError(invalidByte:nextByte)
                    }
                case .NetStringColon:
                    //Colon ':' = end of netstring length
                    var workArray = [nextByte]
                    workArray.reserveCapacity(parseInfo.netstringLength)
                    currentState = .NetStringHeaderName(workArray: workArray)
                    parseInfo.counter = 0
                case .NetStringHeaderName(var workArray):
                    //accumulating header name
                    guard (parseInfo.counter < parseInfo.netstringLength)
                        else { throw SCGIParserError.WrongLength(expectedLength: parseInfo.netstringLength) }
                    workArray.append(nextByte)
                    if (nextByte == 0) {
                       // if let name = String(CString: workArray, encoding: NSISOLatin1StringEncoding) {
                        guard let name = String.fromCString(UnsafePointer(workArray))
                            else { throw SCGIParserError.HeaderEncoding(value: workArray) }
                        workArray.removeAll(keepCapacity: true)
                        currentState = .NetStringHeaderValue(name: name, workArray:workArray)
                    } else {
                        currentState = .NetStringHeaderName(workArray:workArray)
                    }
                case .NetStringHeaderValue(let name, var workArray):
                    //accumulating header value
                    if (parseInfo.counter < parseInfo.netstringLength) {
                        workArray.append(nextByte)
                    } else if (nextByte != 0) {
                        throw SCGIParserError.WrongLength(expectedLength: parseInfo.netstringLength)
                    }
                    if (nextByte == 0) {
                       // if let value = String(CString: workArray, encoding: NSISOLatin1StringEncoding) {
                        if let value = String.fromCString(UnsafePointer(workArray)) {
                            headers.updateValue(value, forKey: name)
                            if (parseInfo.counter < parseInfo.netstringLength-1) {
                                workArray.removeAll(keepCapacity: true)
                                currentState = .NetStringHeaderName(workArray:workArray)
                            } else {
                                currentState = .NetStringComma
                            }
                        } else {
                            throw SCGIParserError.HeaderEncoding(value:workArray)
                        }
                    } else {
                        currentState = .NetStringHeaderValue(name: name, workArray:workArray)
                    }
                case .NetStringComma:
                    //end of headers
                    if (nextByte != AsciiComma) {
                        throw SCGIParserError.CommaMissing
                    } else {
                        //content_length CGI environment variable is mandatory
                        guard let contentLengthString:String = headers["CONTENT_LENGTH"],
                            let contentLength:Int = Int(contentLengthString)
                            else { throw SCGIParserError.ContentLengthMissing }
                        parseInfo.contentLength = contentLength

                        //Our work is finished, call completion block
                        //The caller will have to manage the body itself.
                        if (contentLength > 0 && currentIndex < buffer.count) {
                            let remainingBytes = buffer[(currentIndex+1)..<buffer.count]
                            self.completionBlock(headers:headers, contentLength:contentLength, remainingBytes:remainingBytes)
                        } else {
                            self.completionBlock(headers:headers, contentLength:contentLength, remainingBytes:nil)
                        }
                        currentState = .End
                        break ByteByByteLoop                    
                    }
                case .End:
                    throw SCGIParserError.UnexpectedBytes
            }//end switch currentState
        }//end for currentIndex
    }
}

extension SCGIParserError : CustomStringConvertible
{
    public var description: String
    {
        switch self
        {
            case NoDigitAtStart(let totalIndex): return "request does not start with a digit: \(totalIndex)"
            case StartWithZero: return "request shall not start with a '0'"
            case NetStringLengthError(let invalidByte): return "Unexpected byte in netstring: \(invalidByte)"
            case HeaderEncoding(let value): return "Wrong encoding in netstring: \(value)"
            case WrongLength(let expectedLength): return "Wrong length in netstring, expected: \(expectedLength)"
            case CommaMissing: return "Ending comma is missing in headers"
            case ContentLengthMissing: return "CONTENT_LENGTH variable is missing"
            case UnexpectedBytes: return "Unexpected bytes"
        }
    }
}
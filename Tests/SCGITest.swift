//
//  SCGIProtocol.swift
//  fastcgiapp
//
//  Created by depinette on 06/01/2016.
//  Copyright © 2016 fkdev. All rights reserved.
//

import Foundation
#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

/*

var scgi = SCGITest()
let server:SocketServer = IPV4SocketServer(port:10001)
//let server:SocketServer = UnixSocketServer(socketName:"/tmp/socket")
server.start(scgi)
*/

internal class SCGITest : SocketServerDelegate, ConnectedClientDelegate
{
    var currentRequest : SCGIDecoder = SCGIDecoder(){ (headers:Dictionary<String, String>, contentLength:Int, remainingBytes:ArraySlice<UInt8>?) in}
    
    //MARK: SocketServerDelegate
    func didAcceptConnection(connectedClient:ConnectedClient)
    {
        print("newConnection")
        //new connection = new request in SCGI
        self.currentRequest = SCGIDecoder()
        { [unowned self]  (headers:Dictionary<String, String>, contentLength:Int, remainingBytes:ArraySlice<UInt8>?) in
           connectedClient.sendData(self.debugResponse(headers))
           connectedClient.disconnect()
        }
        connectedClient.delegate = self
    }

    func didDisconnect(connectedClient:ConnectedClient)
    {
        print("disconnected")
    }
    
    //MARK:ConnectedClientDelegate
    func didReceiveData(connectedClient:ConnectedClient, buffer:[UInt8])
    {
        currentRequest.decode(buffer)
    }
    
    //MARK: debug
    deinit
    {
        print("SCGIProtocol deinit called")
    }
    
    private func dumpHeaders(headers:Dictionary<String, String>) ->String
    {
        let headersTable = headers.reduce("", combine: { (var result, pair) -> String in
            result += "\(pair.0)=\(pair.1)<br/>\n"
            return result
        })
        //            print(headersTable.stringByReplacingOccurrencesOfString("<br/>", withString:""))
        return headersTable
    }
    
    private func debugResponse(headers:Dictionary<String, String>)->[UInt8]
    {
        let headers = dumpHeaders(headers)
        let response = "Status: 200 OK\r\nContent-Type: text/html\r\n\r\n<html>\(headers)<br/></html>"
        var cchar:[UInt8] = Array(count: 1024, repeatedValue: 0)
        response.withCString { bytes in
            memcpy(&cchar, bytes,min(Int(cchar.count),Int(strlen(bytes))) ) }
        return cchar
    }
    
    private func debugResponse(headers:Dictionary<String, String>, var body:[UInt8]?)->[UInt8]
    {
        let headers = dumpHeaders(headers)
        body!.append(0)
        var bodyAsString:String = ""
        //if let b = String(CString: parseResult.body, encoding: NSUTF8StringEncoding) {
        if let b =  String.fromCString(UnsafePointer(body!)) {
            bodyAsString = b
            print("body: \(bodyAsString)")
        }
        let response = "Status: 200 OK\r\nContent-Type: text/html\r\n\r\n<html>\(headers)<br/>\n\(bodyAsString)</html>"
        var cchar:[UInt8] = Array(count: 1024, repeatedValue: 0)
        //return response.cStringUsingEncoding(NSUTF8StringEncoding)
        response.withCString { bytes in
            memcpy(&cchar, bytes,min(Int(cchar.count),Int(strlen(bytes))) ) }
        return cchar
    }
}


//
//  main.swift
//  Depsic
//
//  Created by depinette on 27/12/2015.
//  Copyright © 2015 depsys. All rights reserved.
//  This is a sample main for a sample app.

import Foundation
#if os(Linux)
    import CDispatch
    import Glibc
#endif

let scgi = Depsic()

//Create one or more SCGI servers
scgi.addServer(IPV4SocketServer(port:10001))
scgi.addServer(UnixSocketServer(socketName:"/tmp/socket"))


//Hello World request handler
scgi.forRequest( {
    (request:RequestInfo) -> Bool in
    return request.uri == "/"
    },
    respond: {
        (request:RequestInfo) throws -> Response<String> in
        
        //print "Hello <ip>"
        var strResponse:String = "Hello"
        if let ip = request.headers["REMOTE_ADDR"] {
            strResponse += " \(ip)\n"
        }
        
        return Response<String>(content:strResponse)
})

//////////////////////////////////////////////////////
//print the headers
//test with curl http://localhost:8080/headers
scgi.forRequest({
    (request:RequestInfo) -> Bool in
    return request.uri == "/headers"
    },
    respond: {
        (request:RequestInfo) throws -> Response<[UInt8]> in
        
        let content = "<html>\(request.headers)<br/></html>\n"
        var buffer:[UInt8] = Array(count: 1024, repeatedValue: 0)
        content.withCString {
            bytes in
            memcpy(&buffer, bytes,min(Int(buffer.count),Int(strlen(bytes))) )
        }
        
        return Response<[UInt8]>(headers:["Status":"200 OK", "Content-Type":"text/html"], content:buffer)
})

//////////////////////////////////////////////////////
//print the request body (using [UInt8] in closures)
//test with curl -d "Hello" http://localhost:8080/body/buffer
scgi.forRequest({
    (request:RequestInfo) -> Bool in
    return request.uri == "/body"
    },
    respond: {
        (request:Request<[UInt8]>) throws -> Response<[UInt8]> in
        var content:String = ""
        if let body = request.body {
            if let b =  String.fromCString(UnsafePointer(body)) {
                content = b
            }
        }
        
        content = "<html>\(content)<br/></html>\n"
        var buffer:[UInt8] = Array(count: 1024, repeatedValue: 0)
        content.withCString {
            bytes in
            memcpy(&buffer, bytes,min(Int(buffer.count),Int(strlen(bytes))) )
        }
        
        return Response<[UInt8]>(content:buffer)
})

//////////////////////////////////////////////////////
//print body (use String in the closures)
//test with curl -d "Hello" http://localhost:8080/body/string
scgi.forRequest( {
    (request:RequestInfo) -> Bool in
    
    return request.uri == "/body2"
    },
    respond: {
        (request:Request<String>) throws -> Response<String> in
        
        var content:String = ""
        if let body = request.body {
            content = "<html>\(body)<br/></html>\n"
        }
        return Response<String>(content:content)
})


//////////////////////////////////////////////////////
//mini REST API sample////////////////////////////////
let messageApp = MessageApp()
scgi.forRequest( {
    (request:RequestInfo) -> Bool in
    return messageApp.requestPredicate(request)
    },
    respond: {
        (request:Request<String>) throws -> Response<String> in
        return try messageApp.requestHandler(request)
})


scgi.forRequest({ (request:RequestInfo) -> Bool in
        return request.uri == "/form"
    },
    respond: { (request:Request<String>) -> Response<String> in
        return Response<String>(
            content:
        "<meta charset='UTF-8'>" +
        "<form action='/form_process' method='post'>" +
            "<input type='text' name='param1' />" +
            "<input type='email' name='param2' />" +
            "<button type='submit'>send</button>" +
        "</form>")
})


scgi.forFormRequest({
    (request:RequestInfo) -> Bool in

    return request.uri == "/form_process"
    },
    respond: {
        (request:Request<Dictionary<String,String>>) throws -> Response<String> in
        
        var content:String = "\(request.body)"
        return Response<String>(content:content)
})
//////////////////////////////////////////////////////
//blocking call
scgi.waitForServers()

print("quit")

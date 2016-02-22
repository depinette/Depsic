//
//  HTTPRequest.swift
//  Depsic
//
//  Created by depinette on 02/01/2016.
//  Copyright © 2016 depsys. All rights reserved.
//
//  Depsic glues together the socket servers, the Simple SCGI parser and the request handlers.
//

import Foundation
#if os(Linux)
    import Glibc
    import CDispatch
#else
    import Darwin
#endif

public class EmptyType {}
public typealias RequestInfo = Request<EmptyType>
public typealias RequestHandlerPredicate = (request:RequestInfo) -> Bool

public enum HTTPCode : String, ErrorType
{
    case Status_200 = "200 OK"
    case Status_404 = "404 Not Found"
    case Status_400 = "400 Bad Request"
    case Status_500 = "500 Internal Server Error"
}

public protocol RequestPredicate
{
    func canHandleRequest(request:RequestInfo) -> Bool
    func createHandler() -> RequestHandler
}

public protocol RequestHandler : ConnectedClientDelegate
{
    func didReceiveHeader(connectedClient:ConnectedClient, request:Request<EmptyType>)
}

public struct Request<RequestDataType>
{
    let headers:Dictionary<String, String>
    var body:RequestDataType?
    init?(headers:Dictionary<String, String>)
    {
        if Request.checkMandatoryCGIVariables(headers) == false {
            return nil
        }
        self.headers = headers
    }
    init?(headers:Dictionary<String, String>, body:RequestDataType)
    {
        self.init(headers:headers)
        self.body = body
    }
    var uri:String
        {
        get
        {
            let uri = headers["REQUEST_URI"]
            return uri! //checked during init
        }
    }
    var contentLength:Int
        {
        get
        {
            let strLength = headers["CONTENT_LENGTH"]
            if let length = Int(strLength!) {
                return length
            }
            return 0
        }
    }
    var method:String
        {
        get
        {
            let method = headers["REQUEST_METHOD"]
            return method!
        }
    }
    
    static func checkMandatoryCGIVariables(headers:Dictionary<String, String>) -> Bool
    {
        let mandatories = ["REQUEST_URI", "REQUEST_METHOD", "CONTENT_LENGTH"]
        for mandatory in mandatories {
            if headers[mandatory] == nil {
                return false
            }
        }
        return true
    }
}

public struct Response<ResponseDataType>
{
    let headers:CaseInsensitiveDictionary<String>
    let content:ResponseDataType
    init(content:ResponseDataType)
    {
        headers = [:]
        self.content = content
    }
    init(headers:CaseInsensitiveDictionary<String>, content:ResponseDataType)
    {
        self.headers = headers
        self.content = content
    }
    init(headers:Dictionary<String, String>, content:ResponseDataType)
    {
        self.headers = CaseInsensitiveDictionary<String>(headers)
        self.content = content
    }
    init(code:HTTPCode, content:ResponseDataType)
    {
        self.headers = CaseInsensitiveDictionary<String>(["Status":code.rawValue])
        self.content = content
    }
}

//Depsic is the glue between
//-Socketserver and ConnectedClient which receive data from the web server
//-SCGIParser which is used to parse the SCGI variables/headers
//-RequestHandlers which... well... handle requests.
public class Depsic : SocketServerDelegate, ConnectedClientDelegate
{
    init()
    {
        serversGroup = dispatch_group_create();
        pthread_mutex_init(&self.mutexHandler, nil)
        pthread_mutex_init(&self.mutexClient, nil)        
    }
    
    //MARK:Servers management/////////////////
    private var servers : Array<SocketServer> = []
    private let serversGroup:dispatch_group_t
    public func addServer(server:SocketServer)
    {
        servers.append(server)
        
        //start a thread for this server
        let block = { server.start(self); return}
        my_dispatch_group_async(serversGroup, dispatch_get_global_queue(Int(DISPATCH_QUEUE_PRIORITY_HIGH), 0), block)
    }
    
    func waitForServers()
    {
        dispatch_group_wait(serversGroup, DISPATCH_TIME_FOREVER)
    }
    
    //MARK: Handlers management///////////////
    private var requestConditions : Array<RequestPredicate> = []
    private var mutexHandler = pthread_mutex_t()
    private func getHandler(headers:Dictionary<String, String>) -> RequestHandler?
    {
        //we need to protect from multithread here the access to request condition array
        var foundRequestHandler:RequestHandler? = nil
        pthread_mutex_lock(&self.mutexHandler)
        for requestCondition in self.requestConditions {
            if let request = RequestInfo(headers:headers) {
                if requestCondition.canHandleRequest(request) {
                    foundRequestHandler = requestCondition.createHandler()
                    break
                }
            }
        }
        pthread_mutex_unlock(&self.mutexHandler)
        return foundRequestHandler
    }
    
    public func addRequestPredicate(requestCondition:RequestPredicate)
    {
        pthread_mutex_lock(&self.mutexHandler)
        requestConditions.append(requestCondition)
        pthread_mutex_unlock(&self.mutexHandler)
    }
        
    //MARK:Clients management/////////////////
    struct Client
    {
        let connectedClient:ConnectedClient
        let parser:SCGIParser
    }
    private var clients : Array<Client> = []
    private var mutexClient = pthread_mutex_t()
    private func removeClient(connectedClient:ConnectedClient)
    {
        pthread_mutex_lock(&self.mutexClient)
        if let index = clients.indexOf({ (client:Client) -> Bool in client.connectedClient === connectedClient }) {
            clients.removeAtIndex(index)
        }
        pthread_mutex_unlock(&self.mutexClient)
    }
    
    private func addClient(client:Client)
    {
        pthread_mutex_lock(&self.mutexClient)
        clients.append(client)
        pthread_mutex_unlock(&self.mutexClient)
    }
    
    private func getClient(connectedClient:ConnectedClient) -> Client?
    {
        var client:Client?
        pthread_mutex_lock(&self.mutexClient)
        if let index = clients.indexOf({ (client:Client) -> Bool in client.connectedClient === connectedClient }) {
            client = clients[index]
        }
        pthread_mutex_unlock(&self.mutexClient)
        return client
    }
    
    //MARK: SocketServerDelegate/////////////////
    public func didAcceptClient(connectedClient:ConnectedClient)
    {
        //create the SCGIParser and its completionblock
        let decoder = SCGIParser() {
            [unowned self] (headers:Dictionary<String, String>, contentLength:Int, remainingBytes:ArraySlice<UInt8>?) in
            
            //test request
            guard let request = RequestInfo(headers:headers)
            else {
                connectedClient.send(.Status_400)
                return
            }
            
            //test all the request condition
            guard let requestHandler = self.getHandler(headers)
            else {
                connectedClient.send(.Status_404)
                return
            }
            
            //request handler found
            requestHandler.didReceiveHeader(connectedClient, request:request)
            if contentLength > 0 {
                if remainingBytes != nil {
                    requestHandler.didReceiveData(connectedClient, buffer: Array<UInt8>(remainingBytes!))
                }
                connectedClient.delegate = requestHandler
            }
        }
        
        //set us as delegate to process the first bytes (headers)
        connectedClient.delegate = self
        
        //store the client and the parser
        let client = Client(connectedClient: connectedClient, parser: decoder)
        addClient(client)
    }
    
    public func didDisconnectClient(connectedClient:ConnectedClient)
    {
        removeClient(connectedClient)
    }

    //MARK:ConnectedClientDelegate
    public func didReceiveData(connectedClient:ConnectedClient, buffer:[UInt8])
    {
        if let client = getClient(connectedClient) {
            do {
                try client.parser.decode(buffer)
            } catch {
                connectedClient.send(.Status_500)
            }
        }
    }
    
    public func didDisconnect(connectedClient:ConnectedClient)
    {
        //print("disconnected")
    }
}

//MARK: HTTP Send helpers
extension ConnectedClient
{
    func sendHeaders(headers:CaseInsensitiveDictionary<String>)
    {
        var headers = headers
        self.sendString("Status: ")
        if let status = headers.removeValueForKey("Status") {
            self.sendString(status)
        } else {
            self.sendString("200 OK")
        }
        self.sendString("\r\n")
        self.sendString("Content-Type: ")
        if let contentType = headers.removeValueForKey("Content-Type") {
            self.sendString(contentType)
        } else {
            self.sendString("text/html")
        }
        self.sendString("\r\n")
        
        
        for (key, value) in headers {
            self.sendString(key)
            self.sendString(": ")
            self.sendString(value)
            self.sendString("\r\n")
        }
        self.sendString("\r\n")
    }

    func send(status:HTTPCode, _ disconnect:Bool = true)
    {
        self.sendHeaders(["Status":status.rawValue])
        if disconnect { self.disconnect()}
        
    }
}

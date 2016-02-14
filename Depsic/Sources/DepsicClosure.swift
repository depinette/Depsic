//
//  DepsicClosure.swift
//  Depsic
//
//  Created by depinette on 06/02/2016.
//  Copyright © 2016 depsys. All rights reserved.
//
//  A bunch of generic classes used to provide a simple closure-oriented interface
//

import Foundation
#if os(Linux)
    import Glibc
    import CDispatch
#else
    import Darwin
#endif

let DepsicMaxBodySize = 2048 //max body size for block based RequestHandler

//Closure-oriented interface
extension Depsic
{
    //MARK: request/response creation
    public func forRequest(passingTest:RequestHandlerPredicate, respond:(request:Request<EmptyType>) throws -> Response<[UInt8]>)
    {
        let requestCondition = NoBodyToBufferRequestHandler.Condition(passingTest, responseBlock: respond)
        self.addRequestPredicate(requestCondition)
    }
    
    public func forRequest(passingTest:RequestHandlerPredicate, respond:(request:Request<EmptyType>) throws -> Response<String>)
    {
        let requestCondition = NoBodyToStringRequestHandler.Condition(passingTest, responseBlock:respond)
        addRequestPredicate(requestCondition)
    }
    public func forRequest(passingTest:RequestHandlerPredicate, respond:(request:Request<[UInt8]>) throws -> Response<[UInt8]>)
    {
        let requestCondition = BodyToBufferRequestHandler.Condition(passingTest, responseBlock:respond)
        addRequestPredicate(requestCondition)
    }
    
    public func forRequest(passingTest:RequestHandlerPredicate, respond:(request:Request<String>) throws -> Response<[UInt8]>)
    {
        let requestCondition = StringBodyToBufferRequestHandler.Condition(passingTest, responseBlock:respond)
        addRequestPredicate(requestCondition)
    }
    
    public func forRequest(passingTest:RequestHandlerPredicate, respond:(request:Request<String>) throws -> Response<String>)
    {
        let requestCondition = StringBodyToStringRequestHandler.Condition(passingTest, responseBlock:respond)
        addRequestPredicate(requestCondition)
    }
    
    public func forFormRequest(passingTest:RequestHandlerPredicate, respond:(request:Request<Dictionary<String,String>>) throws -> Response<String>)
    {
        let requestCondition = FormBodyToTemplateRequestHandler.Condition(passingTest, responseBlock:respond)
        addRequestPredicate(requestCondition)
    }
}

//MARK:(over-)complicated generics to handle several kind of request and response bodies in closures.
private class RequestConditionBase<RequestDataType, ResponseDataType>
{
    typealias ResponseBlockType = (request:Request<RequestDataType>) throws -> Response<ResponseDataType>
    let predicate:RequestHandlerPredicate
    let response:ResponseBlockType
    init(_ predicate:RequestHandlerPredicate, responseBlock:ResponseBlockType)
    {
        self.predicate = predicate
        self.response = responseBlock
    }
    func canHandleRequest(request:RequestInfo) -> Bool
    {
        return self.predicate(request:request)
    }
}

private class RequestHandlerBase<RequestDataType, ResponseDataType> : RequestHandler, ConnectedClientDelegate
{
    typealias ResponseBlockType = (request:Request<RequestDataType>) throws -> Response<ResponseDataType>
    
    let response: ResponseBlockType
    init(responseBlock:(request:Request<RequestDataType>) throws -> Response<ResponseDataType>)
    {
        self.response = responseBlock
    }
    
    func didReceiveHeader(connectedClient:ConnectedClient, request:Request<EmptyType>)
    {
        
    }
    
    //MARK:ConnectedClientDelegate
    func didReceiveData(connectedClient:ConnectedClient, buffer:[UInt8])
    {
        
    }
    
    func didDisconnect(connectedClient:ConnectedClient)
    {
        
    }
}

private class NoBodyRequestHandler<ResponseDataType>: RequestHandlerBase<EmptyType, ResponseDataType>
{
    override init(responseBlock:ResponseBlockType) { super.init(responseBlock:responseBlock) }
    override func didReceiveHeader(connectedClient:ConnectedClient, request:Request<EmptyType>)
    {
        do {
            let response = try self.response(request:request);
            connectedClient.sendHeaders(response.headers)
            sendData(connectedClient, data: response.content)
            connectedClient.disconnect()
        } catch let httpError as HTTPCode {
            connectedClient.send(httpError)
        } catch {
            connectedClient.send(HTTPCode.Status_500)
        }
    }
    func sendData(connectedClient:ConnectedClient, data:ResponseDataType)
    {
        preconditionFailure("This method must be overridden")
    }
}
private class NoBodyToBufferRequestHandler : NoBodyRequestHandler<[UInt8]>
{
    override init(responseBlock:ResponseBlockType) { super.init(responseBlock:responseBlock) }
    override func sendData(connectedClient:ConnectedClient, data:[UInt8])
    {
        connectedClient.sendData(data)
    }
    private class Condition : RequestConditionBase<EmptyType, [UInt8]>, RequestPredicate
    {
        override init(_ predicate: RequestHandlerPredicate, responseBlock: ResponseBlockType) { super.init(predicate, responseBlock: responseBlock) }
        func createHandler() -> RequestHandler
        {
            return NoBodyToBufferRequestHandler(responseBlock:self.response)
        }
    }
}

private class NoBodyToStringRequestHandler : NoBodyRequestHandler<String>
{
    override init(responseBlock:ResponseBlockType) { super.init(responseBlock:responseBlock) }
    override func sendData(connectedClient:ConnectedClient, data:String)
    {
        connectedClient.sendString(data)
    }
    private class Condition : RequestConditionBase<EmptyType, String>, RequestPredicate
    {
        override init(_ predicate: RequestHandlerPredicate, responseBlock: ResponseBlockType) { super.init(predicate, responseBlock: responseBlock) }
        func createHandler() -> RequestHandler
        {
            return NoBodyToStringRequestHandler(responseBlock:self.response)
        }
    }
}

private class BodyRequestHandler<RequestDataType, ResponseDataType> : RequestHandlerBase<RequestDataType, ResponseDataType>
{
    var request:Request<RequestDataType>?
    var requestBody:[UInt8] = [] //for accumulation of body frame
    override init(responseBlock:ResponseBlockType) { super.init(responseBlock:responseBlock) }
    
    override func didReceiveHeader(connectedClient:ConnectedClient, request:Request<EmptyType>)
    {
        self.request = Request<RequestDataType>(headers:request.headers)
        guard let request = self.request
            else {
                connectedClient.send(.Status_400)
                return
        }
        
        if request.contentLength == 0 {
            do {
                let response = try self.response(request:request);
                connectedClient.sendHeaders(response.headers)
                sendData(connectedClient, data: response.content)
                connectedClient.disconnect()
            } catch let httpError as HTTPCode {
                connectedClient.send(httpError)
            } catch {
                connectedClient.send(HTTPCode.Status_500)
            }
        }
        else if request.contentLength > DepsicMaxBodySize {
            connectedClient.send(HTTPCode.Status_400)
        } else {
            allocBody(request.contentLength)
        }
    }
    override func didReceiveData(connectedClient:ConnectedClient, buffer:[UInt8])
    {
        //accumulation
        guard requestBody.count + buffer.count <= requestBody.capacity
            else {
                connectedClient.send(.Status_400)
                return
        }
        requestBody.appendContentsOf(buffer)
        
        guard var request = self.request
            else {
                //somehow request went wrong since didReceiveHeader
                connectedClient.send(.Status_500)
                return
        }
        
        if request.contentLength != requestBody.count {
            return
        }
        
        //convert [UInt8] body to response type
        guard let requestContent = convertBody()
            else {
                connectedClient.send(.Status_400)
                return
        }
        
        request.body = requestContent
        do {
            let response = try self.response(request:request);
            connectedClient.sendHeaders(response.headers)
            sendData(connectedClient, data: response.content)
            connectedClient.disconnect()
        } catch let httpError as HTTPCode {
            connectedClient.send(httpError)
        } catch {
            connectedClient.send(HTTPCode.Status_500)
        }
    }
    func allocBody(contentLength:Int)
    {
        preconditionFailure("This method must be overridden")
    }
    func convertBody() -> RequestDataType?
    {
        preconditionFailure("This method must be overridden")
    }
    func sendData(connectedClient:ConnectedClient, data:ResponseDataType)
    {
        preconditionFailure("This method must be overridden")
    }
}

private class BodyToTemplateRequestHandler<ResponseDataType> : BodyRequestHandler<[UInt8], ResponseDataType>
{
    override init(responseBlock:ResponseBlockType) { super.init(responseBlock:responseBlock) }
    override func allocBody(contentLength:Int)
    {
        self.requestBody.reserveCapacity(contentLength)
    }
    
    override func convertBody() -> [UInt8]?
    {
        return self.requestBody
    }
}

private class BodyToBufferRequestHandler : BodyToTemplateRequestHandler<[UInt8]>
{
    override init(responseBlock:ResponseBlockType) { super.init(responseBlock:responseBlock) }
    override func sendData(connectedClient:ConnectedClient, data:[UInt8])
    {
        connectedClient.sendData(data)
    }
    private class Condition : RequestConditionBase<[UInt8], [UInt8]>, RequestPredicate
    {
        override init(_ predicate: RequestHandlerPredicate, responseBlock: ResponseBlockType) { super.init(predicate, responseBlock: responseBlock) }
        func createHandler() -> RequestHandler
        {
            return BodyToBufferRequestHandler(responseBlock:self.response)
        }
    }
}

private class BodyToStringRequestHandler : BodyToTemplateRequestHandler<String>
{
    override init(responseBlock:ResponseBlockType) { super.init(responseBlock:responseBlock) }
    override func sendData(connectedClient:ConnectedClient, data:String)
    {
        connectedClient.sendString(data)
    }
}

private class StringBodyToTemplateRequestHandler<ResponseDataType> : BodyRequestHandler<String, ResponseDataType>
{
    override init(responseBlock:ResponseBlockType) { super.init(responseBlock:responseBlock) }
    override func allocBody(contentLength:Int)
    {
        self.requestBody.reserveCapacity(contentLength+1) // +1 for NULL termination
    }
    
    override func convertBody() -> String?
    {
        self.requestBody.append(0)
        //if let str = String(bytes: body, encoding: NSUTF8StringEncoding) {
        if let str = String.fromCString(UnsafePointer(self.requestBody)) {
            return str
        }
        return nil
    }
}

private class StringBodyToBufferRequestHandler : StringBodyToTemplateRequestHandler<[UInt8]>
{
    override init(responseBlock:ResponseBlockType) { super.init(responseBlock:responseBlock) }
    override func sendData(connectedClient:ConnectedClient, data:[UInt8])
    {
        connectedClient.sendData(data)
    }
    private class Condition : RequestConditionBase<String, [UInt8]>, RequestPredicate
    {
        override init(_ predicate: RequestHandlerPredicate, responseBlock: ResponseBlockType) { super.init(predicate, responseBlock: responseBlock) }
        func createHandler() -> RequestHandler
        {
            return StringBodyToBufferRequestHandler(responseBlock:self.response)
        }
    }
}

private class StringBodyToStringRequestHandler : StringBodyToTemplateRequestHandler<String>
{
    override init(responseBlock:ResponseBlockType) { super.init(responseBlock:responseBlock) }
    override func sendData(connectedClient:ConnectedClient, data:String)
    {
        connectedClient.sendString(data)
    }
    private class Condition : RequestConditionBase<String, String>, RequestPredicate
    {
        override init(_ predicate: RequestHandlerPredicate, responseBlock: ResponseBlockType) { super.init(predicate, responseBlock: responseBlock) }
        func createHandler() -> RequestHandler
        {
            return StringBodyToStringRequestHandler(responseBlock:self.response)
        }
    }
}

private let utf8Ampersand:UInt8 = 38
private let utf8Equal:UInt8 = 61
private class FormBodyToTemplateRequestHandler : BodyRequestHandler<Dictionary<String,String>, String>
{
    override init(responseBlock:ResponseBlockType) { super.init(responseBlock:responseBlock) }
    
    override func didReceiveHeader(connectedClient:ConnectedClient, request:Request<EmptyType>)
    {
        super.didReceiveHeader(connectedClient, request: request)
        //check that the content-type is correct
        guard let request = self.request
            else {
                connectedClient.send(.Status_400)
                return
        }
        
        if let contentType = request.headers["CONTENT_TYPE"] {
            //TODO multipart encoding
            if contentType.lowercaseString != "application/x-www-form-urlencoded" {
                connectedClient.send(.Status_400)
            }
        } else {
            connectedClient.send(.Status_400)
        }
        
    }
    
    override func allocBody(contentLength:Int)
    {
        self.requestBody.reserveCapacity(contentLength+1)
    }
    
    override func convertBody() -> Dictionary<String,String>?
    {
        var formFields:Dictionary<String,String> = Dictionary<String,String>()
        self.requestBody.append(0)
        //if let str = String(bytes: body, encoding: NSUTF8StringEncoding) {
        if let str = String.fromCString(UnsafePointer(self.requestBody)) {
            let array = str.utf8.split(utf8Ampersand)
            print(array)
            for kvp in array {
                if let index = kvp.indexOf(utf8Equal) {
                    if let key = String(kvp.prefixUpTo(index)),
                       let value = String(kvp.suffixFrom(index.advancedBy(1))) {
                        //TODO unescape space(+) + URLdecode
                            formFields.updateValue(value, forKey: key)
                    }
                }
            }
        }
        return formFields
    }
    override func sendData(connectedClient:ConnectedClient, data:String)
    {
        connectedClient.sendString(data)
    }
    private class Condition : RequestConditionBase<Dictionary<String,String>, String>, RequestPredicate
    {
        override init(_ predicate: RequestHandlerPredicate, responseBlock: ResponseBlockType) { super.init(predicate, responseBlock: responseBlock) }
        func createHandler() -> RequestHandler
        {
            return FormBodyToTemplateRequestHandler(responseBlock:self.response)
        }
    }
}


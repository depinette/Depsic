//
//  MessageApp.swift
//  Depsic
//
//  Created by depinette on 27/12/2015.
//  Copyright © 2015 depsys. All rights reserved.
//  This is a sample REST app.
//  Public messages are written to Dictionary of messageId to messageContent.


import Foundation
#if os(Linux)
    import Glibc
    import CDispatch
#else
    import Darwin
#endif

//REST API : Method (POST/GET/PUT/DELETE) + URI:/message</id> + BODY:message
public class MessageApp 
{
    private var mutexMessages = pthread_mutex_t() //TODO replace with dispatch_barrier based algo when sure that Dictionary are read safe
    var messages:Dictionary<Int, String> = [:]
    let apiRoot = "/message"
    let api:String
    let MaxNumberOfMessage = 100
    
    init()
    {
        api = apiRoot+"/"
    }

    func requestPredicate(request:RequestInfo) -> Bool
    {
        return request.uri.hasPrefix(self.apiRoot)
    }
   
    func requestHandler(request:Request<String>) throws -> Response<String>
    {
        //get message id
        var uriContent:String = ""
        var responseBody:String = ""

        if (request.uri.characters.count > api.characters.count) {
            uriContent = String(request.uri.utf8.dropFirst(api.characters.count))
        }

        if self.messages.count > MaxNumberOfMessage {
            throw HTTPCode.Status_500
        }
        
        
        if request.method == "POST" {
            //add new message
            if let body = request.body {
                pthread_mutex_lock(&self.mutexMessages)
                
                let messageId = messages.reduce(0, combine: {max($0, $1.0) })+1
                messages[messageId] = body
                pthread_mutex_unlock(&self.mutexMessages)
                responseBody = String(messageId)
            } else {
                throw HTTPCode.Status_400
            }
            
        }
        else if let messageId = Int(uriContent) {
            switch (request.method)
            {
            case "PUT":
                if let body = request.body {
                    //create/replace a message for messageId
                    pthread_mutex_lock(&self.mutexMessages)
                    messages[messageId] = body
                    pthread_mutex_unlock(&self.mutexMessages)
                } else {
                    throw HTTPCode.Status_400
                }
            case "GET":
                //retrieve a message by messageId
                pthread_mutex_lock(&self.mutexMessages)
                let message = messages[messageId]
                pthread_mutex_unlock(&self.mutexMessages)
                if message != nil {
                    responseBody = "{\"id\":\"" + String(messageId) + "\", \"msg\":\"" + message! + "\"}"
                } else {
                    throw HTTPCode.Status_404
                }
            case "DELETE":
                //remove a message by messageId
                pthread_mutex_lock(&self.mutexMessages)
                let message = messages.removeValueForKey(messageId)
                pthread_mutex_unlock(&self.mutexMessages)
                if  message != nil {
                    responseBody = "{\"id\":\"" + String(messageId) + "\", \"msg\":\"" + message! + "\"}"
                } else {
                    throw HTTPCode.Status_404
                }
            default:
                throw HTTPCode.Status_400
            }
        }
        else if (request.method == "GET") {

            pthread_mutex_lock(&self.mutexMessages)
            
            responseBody.appendContentsOf("[")
            for kvp in self.messages {
                //better use a json library when available on linux
                responseBody.appendContentsOf("{\"id\":\"" + String(kvp.0) + "\", \"msg\":\"" + kvp.1 + "\"},")
            }
            responseBody.appendContentsOf("]")
            pthread_mutex_unlock(&self.mutexMessages)
        } else {
            throw HTTPCode.Status_400
        }
        return Response<String>(headers:["Content-Type":"text/json", "Cache-control":"no-cache"], content:responseBody)
    }
}

